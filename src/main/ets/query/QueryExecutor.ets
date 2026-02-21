/**
 * 查询执行器
 * 负责执行 QueryBuilder 构建的查询并返回结果
 */

import { relationalStore } from '@kit.ArkData'
import { QueryBuilder, BatchUpdateValues } from './QueryBuilder'
import { PredicateBuilder } from './PredicateBuilder'
import { DataMapper } from '../mapping/DataMapper'
import { EntityData, RelatedDataValue } from '../mapping/EntityData'
import { ResultSetRow } from '../mapping/ResultSetRow'
import { DatabaseManager } from '../database/DatabaseManager'
import { ExecutionError } from '../errors/DatabaseError'
import { ColumnType } from '../types/ColumnType'
import { RelationLoader } from './RelationLoader'
import { PaginatedResult } from './PaginatedResult'
import { Logger } from '../logging/Logger'
import { SubQuery } from './SubQuery'
import { MetadataStorage } from '../core/MetadataStorage'
import { EntityMetadata } from '../core/EntityMetadata'
import { RelationType } from '../types/RelationType'
import { ValueType, OrderByClause } from '../types/ValueTypes'
import { ConditionOperator } from '../types/ConditionOperator'
import { WhereCondition, LogicalOperator } from './WhereCondition'
import { RelationQueryOptions } from './RelationQueryOptions'
import { ResultSetUtils } from '../mapping/ResultSetUtils'
import { AggregateResult } from './AggregateResult'
import { QueryResultTransformer } from './QueryResultTransformer'
import { AggregateExecutor } from './AggregateExecutor'
import { SubQueryExecutor } from './SubQueryExecutor'
import { SubQueryRelationExecutor } from './SubQueryRelationExecutor'
import { QueryCache } from './QueryCache'
import { OrmContext } from '../core/OrmContext'

class WhereClauseResult {
  whereClause: string
  args: Array<relationalStore.ValueType>

  constructor(whereClause: string, args: Array<relationalStore.ValueType>) {
    this.whereClause = whereClause
    this.args = args
  }
}

class QuerySqlResult {
  sql: string
  args: Array<relationalStore.ValueType>

  constructor(sql: string, args: Array<relationalStore.ValueType>) {
    this.sql = sql
    this.args = args
  }
}

class SubQueryExecutionContext {
  originalConditionCount: number
  originalLimit: number
  originalOffset: number
  subQueryFilterApplied: boolean = false
  limitAdjusted: boolean = false
  noMatch: boolean = false
  inMemoryFilterIds: Set<string> | null = null

  constructor(originalConditionCount: number, originalLimit: number, originalOffset: number) {
    this.originalConditionCount = originalConditionCount
    this.originalLimit = originalLimit
    this.originalOffset = originalOffset
  }
}

interface CloseableLike {
  close: () => void
}

/**
 * 查询执行器类
 * 执行 QueryBuilder 构建的查询并返回映射后的实体数据
 */
export class QueryExecutor {
  /** 查询构建器 */
  private queryBuilder: QueryBuilder
  /** 数据映射器 */
  private dataMapper: DataMapper
  /** 关联数据加载器 */
  private relationLoader: RelationLoader
  /** 日志记录器 */
  private logger: Logger
  /** 查询结果转换器 */
  private queryResultTransformer: QueryResultTransformer
  /** 聚合执行器 */
  private aggregateExecutor: AggregateExecutor
  /** 子查询执行器 */
  private subQueryExecutor: SubQueryExecutor
  /** 子查询关系执行器 */
  private subQueryRelationExecutor: SubQueryRelationExecutor

  /** TaskPool 优化阈值：数据量超过此值时启用 TaskPool */
  private static readonly TASKPOOL_THRESHOLD: number = 100
  /** 子查询 IN 条件参数数量限制 */
  private static readonly SUBQUERY_IN_LIMIT: number = 500

  /**
   * 构造函数
   * @param queryBuilder 查询构建器
   */
  constructor(queryBuilder: QueryBuilder) {
    this.queryBuilder = queryBuilder
    this.dataMapper = new DataMapper(queryBuilder.getEntityName())
    this.relationLoader = new RelationLoader(queryBuilder.getEntityName())
    this.logger = Logger.getInstance()
    this.queryResultTransformer = new QueryResultTransformer(
      this.dataMapper,
      this.logger,
      (resultSet: relationalStore.ResultSet) => this.resultSetToRow(resultSet)
    )
    this.aggregateExecutor = new AggregateExecutor({
      queryBuilder: this.queryBuilder,
      acquireQuerySlot: async (): Promise<void> => await DatabaseManager.getInstance().acquireQuerySlot(),
      releaseQuerySlot: (): void => DatabaseManager.getInstance().releaseQuerySlot(),
      getStore: (): relationalStore.RdbStore => this.getStore(),
      withQueryTimeout: async (
        task: Promise<relationalStore.ResultSet>,
        operation: string
      ): Promise<relationalStore.ResultSet> => await this.withQueryTimeout(task, operation),
      closeResultSet: (resultSet: relationalStore.ResultSet | null): void => this.closeResultSet(resultSet),
      buildWhereClause: (conditions: Array<WhereCondition>) => this.buildWhereClause(conditions),
      escapeIdentifier: (identifier: string): string => this.escapeIdentifier(identifier),
      resolveColumnName: (metadata: EntityMetadata, column: string): string | null => this.resolveColumnName(metadata, column),
      toRdbValue: (value: ValueType | Array<ValueType> | null): relationalStore.ValueType => this.toRdbValue(value)
    })
    this.subQueryRelationExecutor = new SubQueryRelationExecutor({
      logger: this.logger,
      withQueryTimeout: async (
        task: Promise<relationalStore.ResultSet>,
        operation: string
      ): Promise<relationalStore.ResultSet> => await this.withQueryTimeout(task, operation),
      closeResultSet: (resultSet: relationalStore.ResultSet | null): void => this.closeResultSet(resultSet),
      toRdbValue: (value: ValueType | Array<ValueType> | null): relationalStore.ValueType => this.toRdbValue(value)
    })
    this.subQueryExecutor = new SubQueryExecutor({
      queryBuilder: this.queryBuilder,
      logger: this.logger,
      getStore: (): relationalStore.RdbStore => this.getStore(),
      executeOneSubQuery: async (
        subQuery: SubQuery,
        store: relationalStore.RdbStore,
        entityName: string,
        sourcePkColumn: string
      ): Promise<Array<ValueType>> =>
        await this.subQueryRelationExecutor.executeOneSubQuery(subQuery, store, entityName, sourcePkColumn)
    })
  }

  /**
   * 获取 RdbStore 实例
   * @returns RdbStore 实例
   * @throws ExecutionError 如果数据库未初始化
   */
  private getStore(): relationalStore.RdbStore {
    try {
      return DatabaseManager.getInstance().getStore()
    } catch (e) {
      const errorMessage = e instanceof Error ? e.message : String(e)
      throw new ExecutionError('DATABASE', errorMessage)
    }
  }

  private closeResultSet(resultSet: relationalStore.ResultSet | null): void {
    if (resultSet === null) {
      return
    }
    try {
      resultSet.close()
    } catch (e) {
      // ignore
    }
  }

  private closeLateResultSet(value: object | null): void {
    if (value === null) {
      return
    }
    const closable = value as CloseableLike
    if (typeof closable.close !== 'function') {
      return
    }
    try {
      closable.close()
    } catch (e) {
      // ignore
    }
  }

  private getEffectiveQueryTimeoutMs(): number {
    const queryLevelTimeout = this.queryBuilder.getQueryTimeoutMs()
    if (queryLevelTimeout > 0) {
      return queryLevelTimeout
    }
    return DatabaseManager.getInstance().getQueryTimeoutMs()
  }

  private async withQueryTimeout<T>(task: Promise<T>, operation: string): Promise<T> {
    const timeoutMs = this.getEffectiveQueryTimeoutMs()
    if (timeoutMs <= 0) {
      return await task
    }

    return await new Promise<T>((resolve, reject) => {
      let settled = false
      const timeoutId = setTimeout(() => {
        if (settled) {
          return
        }
        settled = true
        reject(new ExecutionError(operation, `查询超时 (${timeoutMs}ms)`))
      }, timeoutMs)

      task.then((value: T) => {
        if (settled) {
          if (value !== null && typeof value === 'object') {
            this.closeLateResultSet(value as object)
          }
          return
        }
        settled = true
        clearTimeout(timeoutId)
        resolve(value)
      }).catch((error: Error | Object | string) => {
        if (settled) {
          return
        }
        settled = true
        clearTimeout(timeoutId)
        reject(error)
      })
    })
  }

  toSQL(): string {
    return this.buildSelectSql().sql
  }

  getSqlArgs(): Array<relationalStore.ValueType> {
    return this.buildSelectSql().args
  }

  async explain(): Promise<Array<EntityData>> {
    await DatabaseManager.getInstance().acquireQuerySlot()
    try {
      const store = this.getStore()
      const sqlResult = this.buildSelectSql()
      const queryPlanSql = `EXPLAIN QUERY PLAN ${sqlResult.sql}`
      const queryPlanRows = await this.queryExplainRows(store, queryPlanSql, sqlResult.args)
      if (queryPlanRows.length > 0) {
        return queryPlanRows
      }
      const explainSql = `EXPLAIN ${sqlResult.sql}`
      const explainRows = await this.queryExplainRows(store, explainSql, sqlResult.args)
      if (explainRows.length > 0) {
        return explainRows
      }
      const fallbackRow = this.createExplainFallbackRow(sqlResult.sql, 'UNAVAILABLE')
      return [fallbackRow]
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      throw new ExecutionError('EXPLAIN', errorMessage)
    } finally {
      DatabaseManager.getInstance().releaseQuerySlot()
    }
  }

  private async queryExplainRows(
    store: relationalStore.RdbStore,
    sql: string,
    args: Array<relationalStore.ValueType>
  ): Promise<Array<EntityData>> {
    let resultSet: relationalStore.ResultSet | null = null
    const plans: Array<EntityData> = []
    try {
      resultSet = await this.withQueryTimeout(store.querySql(sql, args), 'EXPLAIN')
      while (resultSet.goToNextRow()) {
        plans.push(this.resultSetToDynamicEntity(resultSet, 'QueryExplain'))
      }
    } catch (e) {
      return []
    } finally {
      this.closeResultSet(resultSet)
    }
    return plans
  }

  private createExplainFallbackRow(sql: string, status: string): EntityData {
    const row = new EntityData('QueryExplain')
    row.addProperty('status', status, 'string')
    row.addProperty('sql', sql, 'string')
    return row
  }

  private async emitSlowQuery(operation: string, sql: string, duration: number): Promise<void> {
    await OrmContext.emitSlowQuery(operation, sql, duration, this.queryBuilder.getEntityName())
  }

  /**
   * 执行查询并返回所有结果
   * @returns Promise<Array<EntityData>>
   */
  async get(): Promise<Array<EntityData>> {
    const startTime = Date.now()
    const subQueryContext = this.createSubQueryExecutionContext()
    await DatabaseManager.getInstance().acquireQuerySlot()
    try {
      const store = this.getStore()

      await this.prepareSubQueries(subQueryContext, true)
      if (subQueryContext.noMatch) {
        await this.emitSlowQuery('SELECT', this.toSQL(), Date.now() - startTime)
        return []
      }

      const predicates = this.buildPredicatesOrThrow('SELECT')
      const selectedColumns = this.queryBuilder.getSelectedColumns()
      const queryColumns = subQueryContext.inMemoryFilterIds ? this.ensurePrimaryKeySelected(selectedColumns) : selectedColumns
      let results = await this.queryEntities(store, predicates, queryColumns)

      if (subQueryContext.inMemoryFilterIds) {
        results = this.filterByIds(results, subQueryContext.inMemoryFilterIds)
        results = this.applyLimitOffset(results, subQueryContext.originalLimit, subQueryContext.originalOffset)
      }

      results = await this.applyRelationProcessing(results)
      await this.emitSlowQuery('SELECT', this.toSQL(), Date.now() - startTime)
      return results
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      throw new ExecutionError('SELECT', errorMessage)
    } finally {
      DatabaseManager.getInstance().releaseQuerySlot()
      this.finalizeSubQueryContext(subQueryContext)
    }
  }

  /**
   * 加载关联数据
   * 支持嵌套关联路径（如 posts.comments.author）
   * 并按路径顺序递归加载关联数据
   * @param entities 主实体数据数组
   * @returns 带有关联数据的实体数组
   */
  private async loadRelations(entities: Array<EntityData>): Promise<Array<EntityData>> {
    const relationNames = this.queryBuilder.getRelationNames()

    if (relationNames.length === 0) {
      return entities
    }

    const result = entities
    for (let i = 0; i < relationNames.length; i++) {
      const relationPath = relationNames[i]
      const segments = this.splitRelationPath(relationPath)
      if (segments.length === 0) {
        continue
      }
      try {
        await this.loadRelationPath(result, this.queryBuilder.getEntityName(), segments, 0, '')
      } catch (e) {
        const errorMessage = e instanceof Error ? e.message : String(e)
        throw new ExecutionError('RELATION_LOAD', errorMessage)
      }
    }

    return result
  }

  private splitRelationPath(relationPath: string): Array<string> {
    const normalized = relationPath.trim()
    if (normalized.length === 0) {
      return []
    }
    const parts = normalized.split('.')
    const result: Array<string> = []
    for (let i = 0; i < parts.length; i++) {
      const part = parts[i].trim()
      if (part.length > 0) {
        result.push(part)
      }
    }
    return result
  }

  private collectRelationChildren(
    entities: Array<EntityData>,
    relationName: string,
    relationType: RelationType
  ): Array<EntityData> {
    const children: Array<EntityData> = []
    for (let i = 0; i < entities.length; i++) {
      if (relationType === RelationType.ONE_TO_MANY || relationType === RelationType.MANY_TO_MANY) {
        const related = entities[i].getRelatedArray(relationName)
        for (let j = 0; j < related.length; j++) {
          children.push(related[j])
        }
      } else {
        const related = entities[i].getRelatedSingle(relationName)
        if (related !== null) {
          children.push(related)
        }
      }
    }
    return children
  }

  private collectMorphChildrenByEntity(
    entities: Array<EntityData>,
    relationName: string
  ): Map<string, Array<EntityData>> {
    const groupedChildren: Map<string, Array<EntityData>> = new Map()
    for (let i = 0; i < entities.length; i++) {
      const child = entities[i].getRelatedSingle(relationName)
      if (child === null) {
        continue
      }
      let grouped = groupedChildren.get(child.entityName)
      if (grouped === undefined) {
        grouped = []
        groupedChildren.set(child.entityName, grouped)
      }
      grouped.push(child)
    }
    return groupedChildren
  }

  private buildRelationQueryOptionsFromCallback(
    targetEntityName: string,
    callback: (qb: QueryBuilder) => void
  ): RelationQueryOptions {
    const relationBuilder = new QueryBuilder(targetEntityName)
    callback(relationBuilder)
    const options = new RelationQueryOptions()
    const conditions = relationBuilder.getConditions()
    for (let i = 0; i < conditions.length; i++) {
      const source = conditions[i]
      const target = new WhereCondition()
      target.column = source.column
      target.operator = source.operator
      target.value = source.value
      target.secondValue = source.secondValue
      target.logicalOperator = source.logicalOperator
      options.conditions.push(target)
    }
    const orderByColumns = relationBuilder.getOrderByColumns()
    for (let i = 0; i < orderByColumns.length; i++) {
      const item = orderByColumns[i]
      options.orderByColumns.push(new OrderByClause(item.column, item.direction))
    }
    options.limitValue = relationBuilder.getLimitValue()
    options.offsetValue = relationBuilder.getOffsetValue()
    options.includeDeleted = relationBuilder.isIncludeDeleted()
    options.onlyDeleted = relationBuilder.isOnlyDeleted()
    return options
  }

  private async loadRelationPath(
    entities: Array<EntityData>,
    sourceEntityName: string,
    segments: Array<string>,
    index: number,
    prefix: string
  ): Promise<void> {
    if (index >= segments.length || entities.length === 0) {
      return
    }

    const relationName = segments[index]
    const fullPath = prefix.length > 0 ? `${prefix}.${relationName}` : relationName
    const relation = MetadataStorage.getInstance().getRelation(sourceEntityName, relationName)
    if (relation === null) {
      throw new ExecutionError('RELATION_LOAD', `关联 '${fullPath}' 未注册`)
    }

    const loader = sourceEntityName === this.queryBuilder.getEntityName()
      ? this.relationLoader
      : new RelationLoader(sourceEntityName)
    let options = this.queryBuilder.getRelationQueryOptions(fullPath)
    const morphCallback = this.queryBuilder.getMorphRelationQueryCallback(fullPath)
    if (options === null && morphCallback !== null && relation.targetEntity.length > 0) {
      options = this.buildRelationQueryOptionsFromCallback(relation.targetEntity, morphCallback)
    }
    await loader.loadRelation(entities, relationName, options, morphCallback)

    if (index >= segments.length - 1) {
      return
    }

    if (relation.type === RelationType.MORPH_TO) {
      const morphChildren = this.collectMorphChildrenByEntity(entities, relationName)
      if (morphChildren.size === 0) {
        return
      }
      const nextRelationName = segments[index + 1]
      let hasSupportedTarget = false
      const entries = Array.from(morphChildren.entries())
      for (let i = 0; i < entries.length; i++) {
        const targetEntityName = entries[i][0]
        const targetChildren = entries[i][1]
        const nextRelation = MetadataStorage.getInstance().getRelation(targetEntityName, nextRelationName)
        if (nextRelation === null) {
          continue
        }
        hasSupportedTarget = true
        await this.loadRelationPath(targetChildren, targetEntityName, segments, index + 1, fullPath)
      }
      if (!hasSupportedTarget) {
        throw new ExecutionError('RELATION_LOAD', `关联 '${fullPath}.${nextRelationName}' 未注册`)
      }
      return
    }

    const children = this.collectRelationChildren(entities, relationName, relation.type)
    if (children.length === 0) {
      return
    }
    await this.loadRelationPath(children, relation.targetEntity, segments, index + 1, fullPath)
  }

  /**
   * 为查询结果设置延迟加载的关联处理器
   * @param entities 主实体数据数组
   */
  private attachLazyRelations(entities: Array<EntityData>): void {
    const relationNames = this.queryBuilder.getLazyRelationNames()
    if (relationNames.length === 0 || entities.length === 0) {
      return
    }

    const storage = MetadataStorage.getInstance()

    for (let i = 0; i < relationNames.length; i++) {
      const relationName = relationNames[i]
      const relation = storage.getRelation(this.queryBuilder.getEntityName(), relationName)
      if (relation === null) {
        continue
      }

      for (let j = 0; j < entities.length; j++) {
        const entity = entities[j]
        if (entity.hasRelated(relationName) || entity.hasLazyRelation(relationName)) {
          continue
        }

        entity.setLazyRelation(relationName, async () => {
          await this.relationLoader.loadRelation([entity], relationName)
          const loaded = entity.getRelatedValue(relationName)
          if (loaded) {
            return loaded
          }

          let fallback: RelatedDataValue
          if (relation.type === RelationType.ONE_TO_MANY || relation.type === RelationType.MANY_TO_MANY) {
            fallback = RelatedDataValue.fromArray([])
          } else {
            fallback = RelatedDataValue.fromSingle(null)
          }
          entity.setRelated(relationName, fallback)
          return fallback
        })
      }
    }
  }

  /**
   * 执行查询并返回第一条结果
   * @returns Promise<EntityData | null>
   */
  async getOne(): Promise<EntityData | null> {
    try {
      return await this.runWithTemporaryLimit(1, async (): Promise<EntityData | null> => {
        const results = await this.get()
        return results.length > 0 ? results[0] : null
      })
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      throw new ExecutionError('SELECT', errorMessage)
    }
  }

  /**
   * 分块查询（大数据量场景）
   * 按指定批大小逐批加载数据并回调处理，避免一次性加载全部数据
   * @param batchSize 每批数量，必须大于 0
   * @param callback 每批处理回调
   */
  async chunk(
    batchSize: number,
    callback: (entities: Array<EntityData>, chunkIndex: number) => Promise<void> | void
  ): Promise<void> {
    const normalizedBatchSize = Math.floor(batchSize)
    if (normalizedBatchSize <= 0) {
      throw new ExecutionError('CHUNK', 'chunk 大小必须大于 0')
    }

    const originalLimit = this.queryBuilder.getLimitValue()
    const originalOffset = this.queryBuilder.getOffsetValue()
    const hasLimit = originalLimit > 0
    const baseOffset = originalOffset > 0 ? originalOffset : 0
    let processed = 0
    let chunkIndex = 0

    try {
      while (true) {
        if (hasLimit && processed >= originalLimit) {
          break
        }

        let currentLimit = normalizedBatchSize
        if (hasLimit) {
          const remaining = originalLimit - processed
          if (remaining < currentLimit) {
            currentLimit = remaining
          }
        }

        this.queryBuilder.limit(currentLimit)
        this.queryBuilder.offset(baseOffset + processed)

        const batch = await this.get()
        if (batch.length === 0) {
          break
        }

        await callback(batch, chunkIndex)
        chunkIndex += 1
        processed += batch.length

        if (batch.length < currentLimit) {
          break
        }
      }
    } finally {
      this.queryBuilder.limit(originalLimit)
      this.queryBuilder.offset(originalOffset)
    }
  }

  /**
   * 执行查询并返回结果数量
   * @returns Promise<number>
   */
  async count(): Promise<number> {
    const startTime = Date.now()
    const subQueryContext = this.createSubQueryExecutionContext()
    await DatabaseManager.getInstance().acquireQuerySlot()
    try {
      const store = this.getStore()

      await this.prepareSubQueries(subQueryContext, false)
      if (subQueryContext.noMatch) {
        await this.emitSlowQuery('COUNT', this.toSQL(), Date.now() - startTime)
        return 0
      }

      if (subQueryContext.inMemoryFilterIds) {
        const total = await this.countWithInMemoryFilter(store, subQueryContext.inMemoryFilterIds)
        await this.emitSlowQuery('COUNT', this.toSQL(), Date.now() - startTime)
        return total
      }

      const total = await this.countByPredicates(store)
      await this.emitSlowQuery('COUNT', this.toSQL(), Date.now() - startTime)
      return total
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      throw new ExecutionError('COUNT', errorMessage)
    } finally {
      DatabaseManager.getInstance().releaseQuerySlot()
      this.finalizeSubQueryContext(subQueryContext)
    }
  }

  /**
   * 执行分页查询
   * 返回分页结果，包含当前页数据、总数、页码、每页数量和总页数
   * @returns Promise<PaginatedResult>
   * Requirements: 2.4, 2.5, 2.6
   */
  async getPaginated(): Promise<PaginatedResult> {
    const startTime = Date.now()
    const subQueryContext = this.createSubQueryExecutionContext()
    await DatabaseManager.getInstance().acquireQuerySlot()
    try {
      const store = this.getStore()

      // 获取分页参数
      const paginationParams = this.queryBuilder.getPaginationParams()
      if (paginationParams === null) {
        // 如果没有设置分页参数，使用默认值
        const page = 1
        const pageSize = 20
        this.queryBuilder.paginate(page, pageSize)
      }

      const page = this.queryBuilder.getPageNumber()
      const pageSize = this.queryBuilder.getPageSizeValue()

      await this.prepareSubQueries(subQueryContext, true)
      if (subQueryContext.noMatch) {
        await this.emitSlowQuery('SELECT', this.toSQL(), Date.now() - startTime)
        return PaginatedResult.create([], 0, page, pageSize)
      }

      if (subQueryContext.inMemoryFilterIds) {
        const predicates = this.buildPredicatesOrThrow('SELECT')
        const selectedColumns = this.queryBuilder.getSelectedColumns()
        const queryColumns = this.ensurePrimaryKeySelected(selectedColumns)
        let results = await this.queryEntities(store, predicates, queryColumns)

        results = this.filterByIds(results, subQueryContext.inMemoryFilterIds)
        const total = results.length
        const totalPages = PaginatedResult.calculateTotalPages(total, pageSize)

        if (page > totalPages && totalPages > 0) {
          await this.emitSlowQuery('SELECT', this.toSQL(), Date.now() - startTime)
          return PaginatedResult.create([], total, page, pageSize)
        }

        results = this.applyLimitOffset(results, pageSize, (page - 1) * pageSize)

        results = await this.applyRelationProcessing(results)
        await this.emitSlowQuery('SELECT', this.toSQL(), Date.now() - startTime)
        return PaginatedResult.create(results, total, page, pageSize)
      }

      // 先执行 COUNT 查询获取总数
      const total = await this.countByPredicates(store)

      // 计算总页数
      const totalPages = PaginatedResult.calculateTotalPages(total, pageSize)

      // 如果请求的页码超出范围，返回空数据数组
      if (page > totalPages && totalPages > 0) {
        await this.emitSlowQuery('SELECT', this.toSQL(), Date.now() - startTime)
        return PaginatedResult.create([], total, page, pageSize)
      }

      const predicates = this.buildPredicatesOrThrow('SELECT')
      const selectedColumns = this.queryBuilder.getSelectedColumns()
      let results = await this.queryEntities(store, predicates, selectedColumns)

      results = await this.applyRelationProcessing(results)
      await this.emitSlowQuery('SELECT', this.toSQL(), Date.now() - startTime)
      return PaginatedResult.create(results, total, page, pageSize)
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      throw new ExecutionError('SELECT', errorMessage)
    } finally {
      DatabaseManager.getInstance().releaseQuerySlot()
      this.finalizeSubQueryContext(subQueryContext)
    }
  }

  /**
   * 批量更新（不加载实体）
   * @param values 更新字段和值（属性名或列名）
   * @returns 受影响行数
   */
  async update(values: BatchUpdateValues): Promise<number> {
    const startTime = Date.now()
    await DatabaseManager.getInstance().acquireQuerySlot()
    try {
      this.validateMutationQuery('UPDATE')
      const resolvedValues = this.resolveUpdateValues(values)
      const setKeys = resolvedValues.keys()
      if (setKeys.length === 0) {
        throw new ExecutionError('UPDATE', '更新字段不能为空')
      }

      const setClauses: Array<string> = []
      const args: Array<relationalStore.ValueType> = []
      for (let i = 0; i < setKeys.length; i++) {
        const columnName = setKeys[i]
        setClauses.push(`${this.escapeIdentifier(columnName)} = ?`)
        args.push(this.toRdbValue(resolvedValues.get(columnName)))
      }

      const store = this.getStore()
      const whereResult = this.buildWhereClause(this.queryBuilder.getAllConditions())
      const tableName = this.escapeIdentifier(this.queryBuilder.getTableName())
      const matchedRows = await this.countBySql(store, tableName, whereResult.whereClause, whereResult.args)
      const sql = `UPDATE ${tableName} SET ${setClauses.join(', ')}${whereResult.whereClause}`
      const executeArgs = args.concat(whereResult.args)
      await store.executeSql(sql, executeArgs)
      const duration = Date.now() - startTime
      this.logger.logQuery(sql, duration)
      await this.emitSlowQuery('UPDATE', sql, duration)
      QueryCache.getInstance().invalidateEntity(this.queryBuilder.getEntityName())
      return matchedRows
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      throw new ExecutionError('UPDATE', errorMessage)
    } finally {
      DatabaseManager.getInstance().releaseQuerySlot()
    }
  }

  /**
   * 批量删除（不加载实体）
   * @returns 受影响行数
   */
  async delete(): Promise<number> {
    const startTime = Date.now()
    await DatabaseManager.getInstance().acquireQuerySlot()
    try {
      this.validateMutationQuery('DELETE')
      const store = this.getStore()
      const whereResult = this.buildWhereClause(this.queryBuilder.getAllConditions())
      const tableName = this.escapeIdentifier(this.queryBuilder.getTableName())
      const matchedRows = await this.countBySql(store, tableName, whereResult.whereClause, whereResult.args)
      const sql = `DELETE FROM ${tableName}${whereResult.whereClause}`
      await store.executeSql(sql, whereResult.args)
      const duration = Date.now() - startTime
      this.logger.logQuery(sql, duration)
      await this.emitSlowQuery('DELETE', sql, duration)
      QueryCache.getInstance().invalidateEntity(this.queryBuilder.getEntityName())
      return matchedRows
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      throw new ExecutionError('DELETE', errorMessage)
    } finally {
      DatabaseManager.getInstance().releaseQuerySlot()
    }
  }

  /**
   * 将 ResultSet 当前行转换为 ResultSetRow
   */
  private resultSetToRow(resultSet: relationalStore.ResultSet): ResultSetRow {
    const row = new ResultSetRow()
    const columnNames = resultSet.columnNames
    const metadata = this.queryBuilder.getEntityMetadata()

    for (let i = 0; i < columnNames.length; i++) {
      const columnName = columnNames[i]
      try {
        const columnIndex = resultSet.getColumnIndex(columnName)

        // 根据列类型获取值
        if (resultSet.isColumnNull(columnIndex)) {
          row.set(columnName, null)
        } else {
          // 尝试获取不同类型的值
          const columnMetadata = metadata.getColumnByName(columnName)
          if (columnMetadata !== null) {
            switch (columnMetadata.columnType) {
              case ColumnType.INTEGER:
                row.set(columnName, resultSet.getLong(columnIndex))
                break
              case ColumnType.REAL:
                row.set(columnName, resultSet.getDouble(columnIndex))
                break
              case ColumnType.TEXT:
                row.set(columnName, resultSet.getString(columnIndex))
                break
              case ColumnType.BLOB:
                row.set(columnName, resultSet.getBlob(columnIndex))
                break
              default:
                row.set(columnName, resultSet.getString(columnIndex))
            }
          } else {
            // 默认作为字符串处理
            row.set(columnName, resultSet.getString(columnIndex))
          }
        }
      } catch (e) {
        // 忽略单个列的读取错误，继续处理其他列
        row.set(columnName, null)
      }
    }

    return row
  }

  private resolveValueTypeName(value: ValueType): string {
    if (value === null) {
      return 'null'
    }
    if (value instanceof Uint8Array) {
      return 'blob'
    }
    return typeof value
  }

  private resultSetToDynamicEntity(resultSet: relationalStore.ResultSet, entityName: string): EntityData {
    const entity = new EntityData(entityName)
    const columnNames = resultSet.columnNames
    for (let i = 0; i < columnNames.length; i++) {
      const columnName = columnNames[i]
      let value: ValueType = null
      try {
        const columnIndex = resultSet.getColumnIndex(columnName)
        if (!resultSet.isColumnNull(columnIndex)) {
          value = ResultSetUtils.getValueByRuntimeType(resultSet, columnIndex) as ValueType
        }
      } catch (e) {
        value = null
      }
      entity.addProperty(columnName, value, this.resolveValueTypeName(value))
    }
    return entity
  }

  /**
   * 异步执行查询（使用 TaskPool 优化大数据量场景）
   * 当数据量超过阈值时，使用 TaskPool 在后台线程执行数据转换
   * 当数据量小于等于阈值时，在主线程直接执行以避免线程切换开销
   * 
   * @returns Promise<Array<EntityData>>
   * Requirements: 1.1, 1.4, 1.5
   */
  async getAsync(): Promise<Array<EntityData>> {
    const startTime = Date.now()
    const subQueryContext = this.createSubQueryExecutionContext()
    await DatabaseManager.getInstance().acquireQuerySlot()
    try {
      const store = this.getStore()

      await this.prepareSubQueries(subQueryContext, true)
      if (subQueryContext.noMatch) {
        await this.emitSlowQuery('SELECT', this.toSQL(), Date.now() - startTime)
        return []
      }

      const predicates = this.buildPredicatesOrThrow('SELECT')

      // 执行查询
      const selectedColumns = this.queryBuilder.getSelectedColumns()
      const queryColumns = subQueryContext.inMemoryFilterIds ? this.ensurePrimaryKeySelected(selectedColumns) : selectedColumns
      let resultSet: relationalStore.ResultSet | null = null
      let rowCount = 0
      let results: Array<EntityData> = []
      try {
        const queriedResultSet = await this.queryResultSet(store, predicates, queryColumns, 'SELECT')
        resultSet = queriedResultSet
        rowCount = queriedResultSet.rowCount

        if (rowCount > QueryExecutor.TASKPOOL_THRESHOLD) {
          this.logger.logDebug(`数据量 ${rowCount} 超过阈值 ${QueryExecutor.TASKPOOL_THRESHOLD}，尝试使用 TaskPool 优化`)
          results = await this.queryResultTransformer.transformWithTaskPool(queriedResultSet)
        } else {
          this.logger.logDebug(`数据量 ${rowCount} 未超过阈值，在主线程执行数据转换`)
          results = this.queryResultTransformer.transformInMainThread(queriedResultSet)
        }
      } finally {
        this.closeResultSet(resultSet)
      }

      // 记录 TaskPool 执行耗时
      const duration = Date.now() - startTime
      this.logger.logDebug(`getAsync 执行完成，数据量: ${rowCount}，耗时: ${duration}ms`)

      if (subQueryContext.inMemoryFilterIds) {
        results = this.filterByIds(results, subQueryContext.inMemoryFilterIds)
        results = this.applyLimitOffset(results, subQueryContext.originalLimit, subQueryContext.originalOffset)
      }

      results = await this.applyRelationProcessing(results)
      await this.emitSlowQuery('SELECT', this.toSQL(), Date.now() - startTime)
      return results
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      throw new ExecutionError('SELECT', errorMessage)
    } finally {
      DatabaseManager.getInstance().releaseQuerySlot()
      this.finalizeSubQueryContext(subQueryContext)
    }
  }


  private createSubQueryExecutionContext(): SubQueryExecutionContext {
    return new SubQueryExecutionContext(
      this.queryBuilder.getConditions().length,
      this.queryBuilder.getLimitValue(),
      this.queryBuilder.getOffsetValue()
    )
  }

  private async prepareSubQueries(
    context: SubQueryExecutionContext,
    adjustLimitOffsetWhenInMemory: boolean
  ): Promise<void> {
    if (!this.queryBuilder.hasSubQueries()) {
      return
    }

    const subQueryIds = this.normalizeSubQueryIds(await this.subQueryExecutor.executeSubQueries())
    if (subQueryIds.length === 0) {
      context.noMatch = true
      return
    }

    if (subQueryIds.length > QueryExecutor.SUBQUERY_IN_LIMIT || this.hasOrConditionsInQuery()) {
      context.inMemoryFilterIds = this.buildIdSet(subQueryIds)
      if (adjustLimitOffsetWhenInMemory && (context.originalLimit > 0 || context.originalOffset > 0)) {
        this.queryBuilder.limit(0)
        this.queryBuilder.offset(0)
        context.limitAdjusted = true
      }
      return
    }

    context.subQueryFilterApplied = this.applySubQueryFilter(subQueryIds)
  }

  private finalizeSubQueryContext(context: SubQueryExecutionContext): void {
    if (context.limitAdjusted) {
      this.queryBuilder.limit(context.originalLimit)
      this.queryBuilder.offset(context.originalOffset)
    }
    if (context.subQueryFilterApplied) {
      this.restoreConditions(context.originalConditionCount)
    }
  }

  private hasOrConditionsInQuery(): boolean {
    const conditions = this.queryBuilder.getConditions()
    for (let i = 1; i < conditions.length; i++) {
      if (conditions[i].logicalOperator === LogicalOperator.OR) {
        return true
      }
    }
    return false
  }

  private buildPredicatesOrThrow(operation: string): relationalStore.RdbPredicates {
    const buildResult = PredicateBuilder.build(this.queryBuilder)
    if (!buildResult.success || buildResult.predicates === null) {
      throw new ExecutionError(operation, buildResult.errorMessage)
    }
    return buildResult.predicates
  }

  private async queryResultSet(
    store: relationalStore.RdbStore,
    predicates: relationalStore.RdbPredicates,
    selectedColumns: Array<string>,
    operation: string
  ): Promise<relationalStore.ResultSet> {
    if (selectedColumns.length > 0) {
      return await this.withQueryTimeout(store.query(predicates, selectedColumns), operation)
    }
    return await this.withQueryTimeout(store.query(predicates), operation)
  }

  private async queryEntities(
    store: relationalStore.RdbStore,
    predicates: relationalStore.RdbPredicates,
    selectedColumns: Array<string>
  ): Promise<Array<EntityData>> {
    let resultSet: relationalStore.ResultSet | null = null
    const results: Array<EntityData> = []
    try {
      const queriedResultSet = await this.queryResultSet(store, predicates, selectedColumns, 'SELECT')
      resultSet = queriedResultSet

      while (queriedResultSet.goToNextRow()) {
        const row = this.resultSetToRow(queriedResultSet)
        results.push(this.dataMapper.fromResultSetRow(row))
      }
    } finally {
      this.closeResultSet(resultSet)
    }
    return results
  }

  private async applyRelationProcessing(results: Array<EntityData>): Promise<Array<EntityData>> {
    let processed = results
    if (this.queryBuilder.hasRelations() && processed.length > 0) {
      processed = await this.loadRelations(processed)
    }
    if (this.queryBuilder.hasRelationCounts() && processed.length > 0) {
      await this.attachRelationCounts(processed)
    }
    if (this.queryBuilder.hasLazyRelations() && processed.length > 0) {
      this.attachLazyRelations(processed)
    }
    return processed
  }

  private cloneEntitiesForRelationCount(entities: Array<EntityData>): Array<EntityData> {
    const clones: Array<EntityData> = []
    for (let i = 0; i < entities.length; i++) {
      const source = entities[i]
      const cloned = new EntityData(source.entityName)
      for (let j = 0; j < source.properties.length; j++) {
        const property = source.properties[j]
        cloned.addProperty(property.propertyName, property.value, property.propertyType)
      }
      clones.push(cloned)
    }
    return clones
  }

  private countRelationValue(entity: EntityData, segments: Array<string>, index: number): number {
    if (index >= segments.length) {
      return 0
    }
    const relationName = segments[index]
    const relationValue = entity.getRelatedValue(relationName)
    if (relationValue === null) {
      return 0
    }
    if (index === segments.length - 1) {
      if (relationValue.isArray) {
        return entity.getRelatedArray(relationName).length
      }
      return entity.getRelatedSingle(relationName) === null ? 0 : 1
    }
    if (relationValue.isArray) {
      let total = 0
      const children = entity.getRelatedArray(relationName)
      for (let i = 0; i < children.length; i++) {
        total += this.countRelationValue(children[i], segments, index + 1)
      }
      return total
    }
    const child = entity.getRelatedSingle(relationName)
    if (child === null) {
      return 0
    }
    return this.countRelationValue(child, segments, index + 1)
  }

  private async attachRelationCounts(entities: Array<EntityData>): Promise<void> {
    const countOptions = this.queryBuilder.getRelationCountOptions()
    for (let i = 0; i < countOptions.length; i++) {
      const relationPath = countOptions[i].relationPath
      const alias = countOptions[i].alias
      const segments = this.splitRelationPath(relationPath)
      if (segments.length === 0) {
        continue
      }
      const clonedEntities = this.cloneEntitiesForRelationCount(entities)
      try {
        await this.loadRelationPath(clonedEntities, this.queryBuilder.getEntityName(), segments, 0, '')
      } catch (e) {
        const errorMessage = e instanceof Error ? e.message : String(e)
        throw new ExecutionError('RELATION_COUNT', errorMessage)
      }
      for (let j = 0; j < entities.length; j++) {
        const count = this.countRelationValue(clonedEntities[j], segments, 0)
        if (entities[j].hasProperty(alias)) {
          entities[j].setPropertyValue(alias, count)
        } else {
          entities[j].addProperty(alias, count, 'number')
        }
        entities[j].setTransient(alias, count)
      }
    }
  }

  private async runWithClearedLimitOffset<T>(
    operation: string,
    task: () => Promise<T>
  ): Promise<T> {
    const originalLimit = this.queryBuilder.getLimitValue()
    const originalOffset = this.queryBuilder.getOffsetValue()
    const shouldAdjust = originalLimit > 0 || originalOffset > 0

    if (shouldAdjust) {
      try {
        this.queryBuilder.limit(0)
        this.queryBuilder.offset(0)
      } catch (e) {
        const errorMessage = e instanceof Error ? e.message : String(e)
        throw new ExecutionError(operation, errorMessage)
      }
    }

    try {
      return await task()
    } finally {
      if (shouldAdjust) {
        this.queryBuilder.limit(originalLimit)
        this.queryBuilder.offset(originalOffset)
      }
    }
  }

  private async runWithTemporaryLimit<T>(
    limitValue: number,
    task: () => Promise<T>
  ): Promise<T> {
    const originalLimit = this.queryBuilder.getLimitValue()
    if (originalLimit === 0 || originalLimit > limitValue) {
      this.queryBuilder.limit(limitValue)
    }

    try {
      return await task()
    } finally {
      if (originalLimit !== limitValue) {
        this.queryBuilder.limit(originalLimit)
      }
    }
  }

  private countIdsFromResultSet(
    resultSet: relationalStore.ResultSet,
    pkColumnName: string,
    idSet: Set<string>
  ): number {
    let count = 0
    let columnIndex = -1
    try {
      columnIndex = resultSet.getColumnIndex(pkColumnName)
    } catch (e) {
      columnIndex = -1
    }

    try {
      while (true) {
        let hasRow = false
        try {
          hasRow = resultSet.goToNextRow()
        } catch (e) {
          break
        }
        if (!hasRow) {
          break
        }

        let idx = columnIndex
        if (idx < 0) {
          try {
            idx = resultSet.getColumnIndex(pkColumnName)
          } catch (e) {
            idx = -1
          }
        }
        if (idx < 0) {
          continue
        }

        let isNull = true
        try {
          isNull = resultSet.isColumnNull(idx)
        } catch (e) {
          isNull = true
        }
        if (isNull) {
          continue
        }

        const rawValue = ResultSetUtils.getValueByRuntimeType(resultSet, idx)
        if (rawValue !== null && !(rawValue instanceof Uint8Array) && idSet.has(this.toIdKey(rawValue as ValueType))) {
          count++
        }
      }
    } catch (e) {
      // ignore
    }

    return count
  }

  /**
   * 将子查询结果作为 IN 条件应用到主查询
   * @param sourceIds 源实体 ID 数组
   */
  private applySubQueryFilter(sourceIds: Array<ValueType>): boolean {
    const metadata = this.queryBuilder.getEntityMetadata()
    const pkColumn = metadata.getPrimaryKeyColumn()
    if (pkColumn === null) {
      return false
    }
    if (sourceIds.length === 0) {
      return false
    }

    // 使用 whereIn 添加 IN 条件
    this.queryBuilder.whereIn(pkColumn.columnName, sourceIds)
    return true
  }

  private buildSelectSql(): QuerySqlResult {
    const tableName = this.escapeIdentifier(this.queryBuilder.getTableName())
    const selectClause = this.buildSelectClause()
    const whereResult = this.buildWhereClause(this.queryBuilder.getAllConditions())
    const groupByClause = this.buildGroupByClause()
    const orderByClause = this.buildOrderByClause()
    const limit = this.queryBuilder.getLimitValue()
    const offset = this.queryBuilder.getOffsetValue()
    let sql = `SELECT ${selectClause} FROM ${tableName}${whereResult.whereClause}${groupByClause}`
    const havingClause = this.queryBuilder.getHavingClause()
    if (havingClause.length > 0) {
      sql += ` HAVING ${havingClause}`
      const havingArgs = this.queryBuilder.getHavingArgs()
      for (let i = 0; i < havingArgs.length; i++) {
        whereResult.args.push(this.toRdbValue(havingArgs[i]))
      }
    }
    sql += orderByClause
    if (limit > 0) {
      sql += ` LIMIT ${limit}`
    }
    if (offset > 0) {
      sql += ` OFFSET ${offset}`
    }
    return new QuerySqlResult(sql, whereResult.args)
  }

  private buildSelectClause(): string {
    if (this.queryBuilder.hasSelectRaw()) {
      const expressions = this.queryBuilder.getSelectRawExpressions()
      return expressions.join(', ')
    }
    const selectedColumns = this.queryBuilder.getSelectedColumns()
    if (selectedColumns.length === 0) {
      return '*'
    }
    const escapedColumns: Array<string> = []
    for (let i = 0; i < selectedColumns.length; i++) {
      escapedColumns.push(this.escapeIdentifier(selectedColumns[i]))
    }
    return escapedColumns.join(', ')
  }

  private buildGroupByClause(): string {
    const groupByColumns = this.queryBuilder.getGroupByColumns()
    if (groupByColumns.length === 0) {
      return ''
    }
    return ` GROUP BY ${groupByColumns.map((column) => this.escapeIdentifier(column)).join(', ')}`
  }

  private buildOrderByClause(): string {
    const orderByColumns = this.queryBuilder.getOrderByColumns()
    if (orderByColumns.length === 0) {
      return ''
    }
    const parts = orderByColumns.map((orderBy) =>
      `${this.escapeIdentifier(orderBy.column)} ${this.normalizeOrderDirection(orderBy.direction)}`
    )
    return ` ORDER BY ${parts.join(', ')}`
  }


  private async countByPredicates(
    store: relationalStore.RdbStore
  ): Promise<number> {
    const tableName = this.escapeIdentifier(this.queryBuilder.getTableName())
    const conditions = this.queryBuilder.getAllConditions()
    if (conditions.length === 0) {
      return await this.countBySql(store, tableName)
    }
    const whereResult = this.buildWhereClause(conditions)
    return await this.countBySql(store, tableName, whereResult.whereClause, whereResult.args)
  }

  private async countBySql(
    store: relationalStore.RdbStore,
    tableName: string,
    whereClause: string = '',
    args: Array<relationalStore.ValueType> = []
  ): Promise<number> {
    const sql = `SELECT COUNT(*) AS total FROM ${tableName}${whereClause}`
    let resultSet: relationalStore.ResultSet | null = null
    try {
      resultSet = await this.withQueryTimeout(store.querySql(sql, args), 'COUNT')
      try {
        if (resultSet.goToFirstRow()) {
          const index = resultSet.getColumnIndex('total')
          if (index >= 0) {
            try {
              if (!resultSet.isColumnNull(index)) {
                return resultSet.getLong(index)
              }
            } catch (e) {
              // ignore column read error
            }
          }
        }
      } catch (e) {
        // ignore navigation error
      }
      return 0
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      throw new ExecutionError(sql, `执行统计查询失败: ${errorMessage}`)
    } finally {
      this.closeResultSet(resultSet)
    }
  }

  private buildWhereClause(
    conditions: Array<WhereCondition>
  ): WhereClauseResult {
    const whereParts: Array<string> = []
    const args: Array<relationalStore.ValueType> = []

    for (let i = 0; i < conditions.length; i++) {
      const cond = conditions[i]
      if (i > 0) {
        whereParts.push(cond.logicalOperator === LogicalOperator.OR ? 'OR' : 'AND')
      }

      const column = this.escapeIdentifier(cond.column)

      if (cond.operator === ConditionOperator.IN || cond.operator === ConditionOperator.NOT_IN) {
        if (!Array.isArray(cond.value) || cond.value.length === 0) {
          whereParts.push(cond.operator === ConditionOperator.IN ? '1=0' : '1=1')
          continue
        }
        const placeholders = cond.value.map(() => '?').join(',')
        whereParts.push(`${column} ${cond.operator === ConditionOperator.IN ? 'IN' : 'NOT IN'} (${placeholders})`)
        for (let j = 0; j < cond.value.length; j++) {
          args.push(this.toRdbValue(cond.value[j]))
        }
        continue
      }

      switch (cond.operator) {
        case ConditionOperator.EQUAL:
          whereParts.push(`${column} = ?`)
          args.push(this.toRdbValue(cond.value))
          break
        case ConditionOperator.NOT_EQUAL:
          whereParts.push(`${column} != ?`)
          args.push(this.toRdbValue(cond.value))
          break
        case ConditionOperator.GREATER:
          whereParts.push(`${column} > ?`)
          args.push(this.toRdbValue(cond.value))
          break
        case ConditionOperator.LESS:
          whereParts.push(`${column} < ?`)
          args.push(this.toRdbValue(cond.value))
          break
        case ConditionOperator.GREATER_EQUAL:
          whereParts.push(`${column} >= ?`)
          args.push(this.toRdbValue(cond.value))
          break
        case ConditionOperator.LESS_EQUAL:
          whereParts.push(`${column} <= ?`)
          args.push(this.toRdbValue(cond.value))
          break
        case ConditionOperator.LIKE:
          whereParts.push(`${column} LIKE ?`)
          args.push(cond.value === null || Array.isArray(cond.value) ? '' : String(cond.value))
          break
        case ConditionOperator.BETWEEN:
          whereParts.push(`${column} BETWEEN ? AND ?`)
          args.push(this.toRdbValue(cond.value))
          args.push(this.toRdbValue(cond.secondValue))
          break
        case ConditionOperator.IS_NULL:
          whereParts.push(`${column} IS NULL`)
          break
        case ConditionOperator.IS_NOT_NULL:
          whereParts.push(`${column} IS NOT NULL`)
          break
        default:
          throw new ExecutionError('WHERE', `不支持的条件操作符: ${String(cond.operator)}`)
      }
    }

    const whereClause = whereParts.length > 0 ? ` WHERE ${whereParts.join(' ')}` : ''
    return new WhereClauseResult(whereClause, args)
  }

  private escapeIdentifier(identifier: string): string {
    if (identifier === '*') {
      return identifier
    }
    const parts = identifier.split('.')
    const escapedParts: Array<string> = []
    for (let i = 0; i < parts.length; i++) {
      const part = parts[i].replace(/"/g, '""')
      escapedParts.push(`"${part}"`)
    }
    return escapedParts.join('.')
  }

  private normalizeOrderDirection(direction: string): string {
    const normalized = direction.trim().toUpperCase()
    if (normalized === 'ASC' || normalized === 'DESC') {
      return normalized
    }
    throw new ExecutionError('ORDER BY', `非法排序方向: ${direction}`)
  }

  private validateMutationQuery(operation: string): void {
    if (this.queryBuilder.getConditions().length === 0) {
      throw new ExecutionError(operation, `${operation} 需要至少一个 WHERE 条件`)
    }
    if (this.queryBuilder.hasSubQueries()) {
      throw new ExecutionError(operation, `${operation} 暂不支持 whereExists 子查询`)
    }
    if (this.queryBuilder.getLimitValue() > 0 || this.queryBuilder.getOffsetValue() > 0) {
      throw new ExecutionError(operation, `${operation} 暂不支持 LIMIT/OFFSET`)
    }
    if (this.queryBuilder.getOrderByColumns().length > 0) {
      throw new ExecutionError(operation, `${operation} 暂不支持 ORDER BY`)
    }
    if (this.queryBuilder.hasGroupBy() || this.queryBuilder.getHavingClause().length > 0) {
      throw new ExecutionError(operation, `${operation} 暂不支持 GROUP BY/HAVING`)
    }
    if (this.queryBuilder.hasSelectRaw()) {
      throw new ExecutionError(operation, `${operation} 暂不支持 selectRaw`)
    }
  }

  private resolveUpdateValues(values: BatchUpdateValues): BatchUpdateValues {
    const metadata = this.queryBuilder.getEntityMetadata()
    const primaryKey = metadata.getPrimaryKeyColumn()
    const result = BatchUpdateValues.create()
    const keys = values.keys()
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i]
      const resolvedColumn = this.resolveColumnName(metadata, key)
      if (resolvedColumn === null) {
        throw new ExecutionError('UPDATE', `更新字段 '${key}' 在实体中不存在`)
      }
      if (primaryKey !== null && resolvedColumn === primaryKey.columnName) {
        throw new ExecutionError('UPDATE', `不允许更新主键字段 '${resolvedColumn}'`)
      }
      result.set(resolvedColumn, values.get(key))
    }
    return result
  }

  private ensurePrimaryKeySelected(selectedColumns: Array<string>): Array<string> {
    if (selectedColumns.length === 0) {
      return selectedColumns
    }
    const metadata = this.queryBuilder.getEntityMetadata()
    const pkColumn = metadata.getPrimaryKeyColumn()
    if (pkColumn === null) {
      return selectedColumns
    }
    if (selectedColumns.includes(pkColumn.columnName)) {
      return selectedColumns
    }
    const columns: Array<string> = []
    for (let i = 0; i < selectedColumns.length; i++) {
      columns.push(selectedColumns[i])
    }
    columns.push(pkColumn.columnName)
    return columns
  }

  private restoreConditions(originalCount: number): void {
    const conditions = this.queryBuilder.getConditions()
    if (conditions.length > originalCount) {
      conditions.splice(originalCount, conditions.length - originalCount)
    }
  }

  private normalizeSubQueryIds(sourceIds: Array<ValueType>): Array<ValueType> {
    const result: Array<ValueType> = []
    const seen: Set<string> = new Set()
    for (let i = 0; i < sourceIds.length; i++) {
      const id = sourceIds[i]
      if (id === null) {
        continue
      }
      const key = this.toIdKey(id)
      if (!seen.has(key)) {
        seen.add(key)
        result.push(id)
      }
    }
    return result
  }

  private buildIdSet(sourceIds: Array<ValueType>): Set<string> {
    const idSet: Set<string> = new Set()
    for (let i = 0; i < sourceIds.length; i++) {
      const id = sourceIds[i]
      if (id === null) {
        continue
      }
      idSet.add(this.toIdKey(id))
    }
    return idSet
  }

  private toIdKey(value: ValueType): string {
    if (value === null) {
      return ''
    }
    if (typeof value === 'number') {
      return `n:${value}`
    }
    if (typeof value === 'boolean') {
      return `b:${value ? 1 : 0}`
    }
    return `s:${String(value)}`
  }

  private filterByIds(results: Array<EntityData>, idSet: Set<string>): Array<EntityData> {
    if (idSet.size === 0) {
      return []
    }
    const filtered: Array<EntityData> = []
    for (let i = 0; i < results.length; i++) {
      const entity = results[i]
      const pkValue = this.dataMapper.getPrimaryKeyValue(entity)
      if (pkValue !== null && idSet.has(this.toIdKey(pkValue))) {
        filtered.push(entity)
      }
    }
    return filtered
  }

  private applyLimitOffset(results: Array<EntityData>, limit: number, offset: number): Array<EntityData> {
    const safeOffset = offset > 0 ? offset : 0
    if (limit > 0) {
      return results.slice(safeOffset, safeOffset + limit)
    }
    if (safeOffset > 0) {
      return results.slice(safeOffset)
    }
    return results
  }

  private async countWithInMemoryFilter(
    store: relationalStore.RdbStore,
    idSet: Set<string>
  ): Promise<number> {
    const metadata = this.queryBuilder.getEntityMetadata()
    const pkColumn = metadata.getPrimaryKeyColumn()
    if (pkColumn === null) {
      return 0
    }

    let resultSet: relationalStore.ResultSet | null = null

    try {
      return await this.runWithClearedLimitOffset('COUNT', async (): Promise<number> => {
        const predicates = this.buildPredicatesOrThrow('COUNT')

        try {
          const queriedResultSet = await this.queryResultSet(store, predicates, [pkColumn.columnName], 'COUNT')
          resultSet = queriedResultSet
          return this.countIdsFromResultSet(queriedResultSet, pkColumn.columnName, idSet)
        } catch (e) {
          const errorMessage = e instanceof Error ? e.message : String(e)
          throw new ExecutionError('COUNT', `执行统计查询失败: ${errorMessage}`)
        }
      })
    } catch (error) {
      if (error instanceof ExecutionError) {
        throw error
      }
      const errorMessage = error instanceof Error ? error.message : String(error)
      throw new ExecutionError('COUNT', errorMessage)
    } finally {
      this.closeResultSet(resultSet)
    }
  }


  /**
   * 计算指定列的总和
   * @param column 列名或属性名
   * @returns Promise<number>
   */
  async sum(column: string): Promise<number> {
    return await this.aggregateExecutor.sum(column)
  }

  /**
   * 计算指定列的平均值
   * @param column 列名或属性名
   * @returns Promise<number>
   */
  async avg(column: string): Promise<number> {
    return await this.aggregateExecutor.avg(column)
  }

  /**
   * 获取指定列的最大值
   * @param column 列名或属性名
   * @returns Promise<ValueType>
   */
  async max(column: string): Promise<ValueType> {
    return await this.aggregateExecutor.max(column)
  }

  /**
   * 获取指定列的最小值
   * @param column 列名或属性名
   * @returns Promise<ValueType>
   */
  async min(column: string): Promise<ValueType> {
    return await this.aggregateExecutor.min(column)
  }

  /**
   * 执行分组聚合查询
   * 使用 selectRaw() 和 groupBy() 构建的查询
   * @returns Promise<AggregateResult>
   */
  async aggregate(): Promise<AggregateResult> {
    return await this.aggregateExecutor.aggregate()
  }

  /**
   * 解析列名（属性名或数据库列名）
   * @param metadata 实体元数据
   * @param column 列名或属性名
   * @returns 数据库列名，未找到返回 null
   */
  private resolveColumnName(metadata: EntityMetadata, column: string): string | null {
    const columnByName = metadata.getColumnByName(column)
    if (columnByName !== null) {
      return columnByName.columnName
    }
    const columnByProperty = metadata.getColumnByProperty(column)
    if (columnByProperty !== null) {
      return columnByProperty.columnName
    }
    return null
  }

  /**
   * 将 ValueType 转换为 RdbPredicates 支持的值类型
   */
  private toRdbValue(value: ValueType | Array<ValueType> | null): relationalStore.ValueType {
    if (value === null) {
      return null
    }
    if (Array.isArray(value)) {
      return null
    }
    if (typeof value === 'string') {
      return value
    }
    if (typeof value === 'number') {
      return value
    }
    if (typeof value === 'boolean') {
      return value ? 1 : 0
    }
    if (value instanceof Date) {
      return value.getTime()
    }
    if (value instanceof Uint8Array) {
      return value
    }
    if (typeof value === 'object') {
      try {
        return JSON.stringify(value as object)
      } catch (e) {
        return null
      }
    }
    return null
  }
}
