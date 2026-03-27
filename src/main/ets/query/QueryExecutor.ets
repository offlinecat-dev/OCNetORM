/**
 * 查询执行器
 * 负责执行 QueryBuilder 构建的查询并返回结果
 */

import { relationalStore } from '@kit.ArkData'
import { QueryBuilder, BatchUpdateValues } from './QueryBuilder'
import { PredicateBuilder } from './PredicateBuilder'
import { DataMapper } from '../mapping/DataMapper'
import { EntityData } from '../mapping/EntityData'
import { ResultSetRow } from '../mapping/ResultSetRow'
import { DatabaseManager } from '../database/DatabaseManager'
import { ExecutionError } from '../errors/DatabaseError'
import { ColumnType } from '../types/ColumnType'
import { RelationLoader } from './RelationLoader'
import { PaginatedResult } from './PaginatedResult'
import { Logger } from '../logging/Logger'
import { SubQuery } from './SubQuery'
import { EntityMetadata } from '../core/EntityMetadata'
import { ValueType } from '../types/ValueTypes'
import { WhereCondition } from './WhereCondition'
import { ResultSetUtils } from '../mapping/ResultSetUtils'
import { AggregateResult } from './AggregateResult'
import { QueryResultTransformer } from './QueryResultTransformer'
import { AggregateExecutor } from './AggregateExecutor'
import { SubQueryExecutor } from './SubQueryExecutor'
import { SubQueryRelationExecutor } from './SubQueryRelationExecutor'
import { QueryExecutorRelationSupport } from './QueryExecutorRelationSupport'
import {
  QueryExecutorSqlSupport,
  QueryExecutorSqlResult,
  QueryExecutorWhereClauseResult
} from './QueryExecutorSqlSupport'
import { QueryCache } from './QueryCache'
import { OrmContext } from '../core/OrmContext'
import { OrmError } from '../errors/OrmError'
import { sanitizeErrorMessage, sanitizeSqlPreview } from '../errors/ErrorSanitizer'
import {
  applyLimitOffset as applyLimitOffsetUtil,
  buildIdSetFromValues,
  compareOrderValues as compareOrderValuesUtil,
  filterEntitiesByIdSet,
  hasOrConditions,
  normalizeSubQueryIds,
  restoreConditions as restoreConditionsUtil,
  splitIntoBatches as splitIntoBatchesUtil,
  toIdKey as toIdKeyUtil
} from './QueryExecutionUtils'

class SubQueryExecutionContext {
  originalConditionCount: number
  originalLimit: number
  originalOffset: number
  subQueryFilterApplied: boolean = false
  limitAdjusted: boolean = false
  noMatch: boolean = false
  inMemoryFilterIds: Set<string> | null = null
  subQueryIdBatches: Array<Array<ValueType>> | null = null

  constructor(originalConditionCount: number, originalLimit: number, originalOffset: number) {
    this.originalConditionCount = originalConditionCount
    this.originalLimit = originalLimit
    this.originalOffset = originalOffset
  }
}

interface OrderDefinition {
  propertyName: string
  direction: string
}

type QueryObserver = (operation: string) => void
type LateResultSetObserver = () => void
type RelationPathObserver = (phase: string, relationPath: string) => Promise<void> | void
type AsyncFailure = Error | object | string | number | boolean | null | undefined

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
  /** 查询关系路径加载支持 */
  private relationSupport: QueryExecutorRelationSupport
  /** 查询 SQL 构建支持 */
  private sqlSupport: QueryExecutorSqlSupport
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
  /** 当前租约绑定的连接（仅在连接池启用时生效） */
  private leasedStore: relationalStore.RdbStore | null = null
  /** 防止同一 QueryExecutor 实例被并发复用 */
  private operationInProgress: boolean = false

  /** TaskPool 优化阈值：数据量超过此值时启用 TaskPool */
  private static readonly TASKPOOL_THRESHOLD: number = 100
  /** 子查询 IN 条件参数数量限制 */
  private static readonly DEFAULT_SUBQUERY_IN_LIMIT: number = 500
  private static subQueryInLimit: number = QueryExecutor.DEFAULT_SUBQUERY_IN_LIMIT
  private static queryObserverForTest: QueryObserver | null = null
  private static lateResultSetObserverForTest: LateResultSetObserver | null = null
  private static relationPathObserverForTest: RelationPathObserver | null = null
  private static resultSetDelayMsForTest: number = 0

  /**
   * 构造函数
   * @param queryBuilder 查询构建器
   */
  constructor(queryBuilder: QueryBuilder) {
    this.queryBuilder = queryBuilder.clone()
    this.dataMapper = new DataMapper(queryBuilder.getEntityName())
    this.relationLoader = new RelationLoader(this.queryBuilder.getEntityName(), () => this.getStore())
    this.sqlSupport = new QueryExecutorSqlSupport(
      this.queryBuilder,
      (value: ValueType | Array<ValueType> | null): relationalStore.ValueType => this.toRdbValue(value)
    )
    this.relationSupport = new QueryExecutorRelationSupport({
      queryBuilder: this.queryBuilder,
      relationLoader: this.relationLoader,
      getStore: () => this.getStore(),
      notifyRelationPath: async (phase: string, relationPath: string): Promise<void> => {
        await QueryExecutor.notifyRelationPathObserverForTest(phase, relationPath)
      }
    })
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

  static setSubQueryInLimitForTest(limit: number): void {
    QueryExecutor.subQueryInLimit = limit > 0 ? Math.floor(limit) : 1
  }

  static getSubQueryInLimitForTest(): number {
    return QueryExecutor.subQueryInLimit
  }

  static setQueryObserverForTest(observer: ((operation: string) => void) | null): void {
    QueryExecutor.queryObserverForTest = observer
  }

  static setLateResultSetObserverForTest(observer: (() => void) | null): void {
    QueryExecutor.lateResultSetObserverForTest = observer
  }

  static setRelationPathObserverForTest(
    observer: ((phase: string, relationPath: string) => Promise<void> | void) | null
  ): void {
    QueryExecutor.relationPathObserverForTest = observer
  }

  static setResultSetDelayMsForTest(delayMs: number): void {
    QueryExecutor.resultSetDelayMsForTest = delayMs > 0 ? Math.floor(delayMs) : 0
  }

  static resetTestHooks(): void {
    QueryExecutor.subQueryInLimit = QueryExecutor.DEFAULT_SUBQUERY_IN_LIMIT
    QueryExecutor.queryObserverForTest = null
    QueryExecutor.lateResultSetObserverForTest = null
    QueryExecutor.relationPathObserverForTest = null
    QueryExecutor.resultSetDelayMsForTest = 0
  }

  async loadRelationsForTest(entities: Array<EntityData>): Promise<Array<EntityData>> {
    return await this.loadRelations(entities)
  }

  private static notifyQueryObserverForTest(operation: string): void {
    const observer = QueryExecutor.queryObserverForTest
    if (observer !== null) {
      observer(operation)
    }
  }

  private static notifyLateResultSetObserverForTest(): void {
    const observer = QueryExecutor.lateResultSetObserverForTest
    if (observer !== null) {
      observer()
    }
  }

  private static async notifyRelationPathObserverForTest(phase: string, relationPath: string): Promise<void> {
    const observer = QueryExecutor.relationPathObserverForTest
    if (observer === null) {
      return
    }
    await observer(phase, relationPath)
  }

  /**
   * 获取 RdbStore 实例
   * @returns RdbStore 实例
   * @throws ExecutionError 如果数据库未初始化
   */
  private getStore(): relationalStore.RdbStore {
    if (this.leasedStore !== null) {
      return this.leasedStore
    }
    try {
      return DatabaseManager.getInstance().getStore()
    } catch (e) {
      const errorMessage = e instanceof Error ? e.message : String(e)
      throw new ExecutionError('DATABASE', errorMessage)
    }
  }

  private async withStoreLease<T>(operation: () => Promise<T>): Promise<T> {
    if (this.operationInProgress) {
      throw new ExecutionError('QUERY_EXECUTOR', '同一 QueryExecutor 实例不支持并发复用，请为并发操作创建独立实例')
    }
    this.operationInProgress = true
    try {
      if (this.leasedStore !== null) {
        return await operation()
      }
      const manager = DatabaseManager.getInstance()
      if (!manager.isPoolEnabled()) {
        return await operation()
      }
      return await manager.withStoreLease(async (lease) => {
        this.leasedStore = lease.store
        try {
          return await operation()
        } finally {
          this.leasedStore = null
        }
      })
    } finally {
      this.operationInProgress = false
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

  private closeLateResultSet(value: relationalStore.ResultSet | null): void {
    if (value === null) {
      return
    }
    try {
      value.close()
      QueryExecutor.notifyLateResultSetObserverForTest()
    } catch (e) {
      // ignore
    }
  }

  private resolveErrorMessage(error: AsyncFailure): string {
    if (error instanceof OrmError) {
      return sanitizeErrorMessage(error.getFullMessage())
    }
    if (error instanceof Error) {
      return sanitizeErrorMessage(error.message)
    }
    return sanitizeErrorMessage(String(error))
  }

  private logWarnWithError(context: string, error: AsyncFailure): void {
    this.logger.logWarn(`${context}: ${this.resolveErrorMessage(error)}`)
  }

  private getEffectiveQueryTimeoutMs(): number {
    const queryLevelTimeout = this.queryBuilder.getQueryTimeoutMs()
    if (queryLevelTimeout > 0) {
      return queryLevelTimeout
    }
    return DatabaseManager.getInstance().getQueryTimeoutMs()
  }

  private async withQueryTimeout(
    task: Promise<relationalStore.ResultSet>,
    operation: string
  ): Promise<relationalStore.ResultSet> {
    const timeoutMs = this.getEffectiveQueryTimeoutMs()
    const delayedTask = this.delayQueryResultForTest(task)
    QueryExecutor.notifyQueryObserverForTest(operation)
    if (timeoutMs <= 0) {
      return await delayedTask
    }

    return await new Promise<relationalStore.ResultSet>((resolve, reject) => {
      let settled = false
      const timeoutId = setTimeout(() => {
        if (settled) {
          return
        }
        settled = true
        reject(new ExecutionError(operation, `查询超时 (${timeoutMs}ms)`))
      }, timeoutMs)

      delayedTask.then((value: relationalStore.ResultSet) => {
        if (settled) {
          this.closeLateResultSet(value)
          return
        }
        settled = true
        clearTimeout(timeoutId)
        resolve(value)
      }).catch((error: AsyncFailure) => {
        if (settled) {
          return
        }
        settled = true
        clearTimeout(timeoutId)
        reject(error)
      })
    })
  }

  private delayQueryResultForTest<T>(task: Promise<T>): Promise<T> {
    const delayMs = QueryExecutor.resultSetDelayMsForTest
    if (delayMs <= 0) {
      return task
    }
    return task.then((value: T) => {
      return new Promise<T>((resolve) => {
        setTimeout(() => {
          resolve(value)
        }, delayMs)
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
    return await this.withStoreLease(async () => {
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
        const errorMessage = this.resolveErrorMessage(error)
        throw new ExecutionError('EXPLAIN', errorMessage)
      } finally {
        DatabaseManager.getInstance().releaseQuerySlot()
      }
    })
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
      this.logWarnWithError(
        `EXPLAIN 查询失败, sql=${sanitizeSqlPreview(sql)}`,
        e
      )
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

  private ensureEntityQueryMode(operation: string): void {
    if (this.queryBuilder.hasSelectRaw() ||
      this.queryBuilder.hasGroupBy() ||
      this.queryBuilder.getHavingClause().length > 0) {
      throw new ExecutionError(operation, '实体查询不支持 selectRaw/groupBy/having，请使用 getRaw() 或 aggregate()')
    }
  }

  /**
   * 执行查询并返回所有结果
   * @returns Promise<Array<EntityData>>
   */
  async get(): Promise<Array<EntityData>> {
    return await this.withStoreLease(async () => {
      this.ensureEntityQueryMode('SELECT')
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

        const selectedColumns = this.queryBuilder.getSelectedColumns()
        const queryColumns = subQueryContext.inMemoryFilterIds ? this.ensurePrimaryKeySelected(selectedColumns) : selectedColumns
        let results: Array<EntityData> = []

        if (subQueryContext.subQueryIdBatches) {
          const batchColumns = this.ensureOrderBySelected(selectedColumns)
          results = await this.queryEntitiesBySubQueryBatches(
            store,
            batchColumns,
            subQueryContext.subQueryIdBatches,
            subQueryContext.originalConditionCount
          )
          results = this.sortResultsByOrder(results)
          results = applyLimitOffsetUtil(results, subQueryContext.originalLimit, subQueryContext.originalOffset)
        } else {
          const predicates = this.buildPredicatesOrThrow('SELECT')
          results = await this.queryEntities(store, predicates, queryColumns)
          if (subQueryContext.inMemoryFilterIds) {
            results = filterEntitiesByIdSet(
              results,
              subQueryContext.inMemoryFilterIds,
              (entity) => this.dataMapper.getPrimaryKeyValue(entity)
            )
            results = applyLimitOffsetUtil(results, subQueryContext.originalLimit, subQueryContext.originalOffset)
          }
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
    })
  }

  /**
   * 加载关联数据
   * 支持嵌套关联路径（如 posts.comments.author）
   * 并按路径顺序递归加载关联数据
   * @param entities 主实体数据数组
   * @returns 带有关联数据的实体数组
   */
  private async loadRelations(entities: Array<EntityData>): Promise<Array<EntityData>> {
    return await this.relationSupport.loadRelations(entities)
  }

  private splitRelationPath(relationPath: string): Array<string> {
    return this.relationSupport.splitRelationPath(relationPath)
  }

  private async loadRelationPath(
    entities: Array<EntityData>,
    sourceEntityName: string,
    segments: Array<string>,
    index: number,
    prefix: string
  ): Promise<void> {
    await this.relationSupport.loadRelationPath(entities, sourceEntityName, segments, index, prefix)
  }

  /**
   * 为查询结果设置延迟加载的关联处理器
   * @param entities 主实体数据数组
   */
  private attachLazyRelations(entities: Array<EntityData>): void {
    this.relationSupport.attachLazyRelations(entities)
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
    return await this.withStoreLease(async () => {
      this.ensureEntityQueryMode('COUNT')
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
        if (subQueryContext.subQueryIdBatches) {
          const total = await this.countBySubQueryBatches(
            store,
            subQueryContext.subQueryIdBatches,
            subQueryContext.originalConditionCount
          )
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
    })
  }

  /**
   * 执行分页查询
   * 返回分页结果，包含当前页数据、总数、页码、每页数量和总页数
   * @returns Promise<PaginatedResult>
   * Requirements: 2.4, 2.5, 2.6
   */
  async getPaginated(): Promise<PaginatedResult> {
    return await this.withStoreLease(async () => {
      this.ensureEntityQueryMode('SELECT')
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

        if (subQueryContext.subQueryIdBatches) {
          const selectedColumns = this.queryBuilder.getSelectedColumns()
          const batchColumns = this.ensureOrderBySelected(selectedColumns)
          let results = await this.queryEntitiesBySubQueryBatches(
            store,
            batchColumns,
            subQueryContext.subQueryIdBatches,
            subQueryContext.originalConditionCount
          )
          results = this.sortResultsByOrder(results)
          const total = results.length
          const totalPages = PaginatedResult.calculateTotalPages(total, pageSize)

          if (page > totalPages && totalPages > 0) {
            await this.emitSlowQuery('SELECT', this.toSQL(), Date.now() - startTime)
            return PaginatedResult.create([], total, page, pageSize)
          }

          results = applyLimitOffsetUtil(results, pageSize, (page - 1) * pageSize)

          results = await this.applyRelationProcessing(results)
          await this.emitSlowQuery('SELECT', this.toSQL(), Date.now() - startTime)
          return PaginatedResult.create(results, total, page, pageSize)
        }

        if (subQueryContext.inMemoryFilterIds) {
          const predicates = this.buildPredicatesOrThrow('SELECT')
          const selectedColumns = this.queryBuilder.getSelectedColumns()
          const queryColumns = this.ensurePrimaryKeySelected(selectedColumns)
          let results = await this.queryEntities(store, predicates, queryColumns)

          results = filterEntitiesByIdSet(
            results,
            subQueryContext.inMemoryFilterIds,
            (entity) => this.dataMapper.getPrimaryKeyValue(entity)
          )
          const total = results.length
          const totalPages = PaginatedResult.calculateTotalPages(total, pageSize)

          if (page > totalPages && totalPages > 0) {
            await this.emitSlowQuery('SELECT', this.toSQL(), Date.now() - startTime)
            return PaginatedResult.create([], total, page, pageSize)
          }

          results = applyLimitOffsetUtil(results, pageSize, (page - 1) * pageSize)

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
    })
  }

  /**
   * 批量更新（不加载实体）
   * @param values 更新字段和值（属性名或列名）
   * @returns 受影响行数
   */
  async update(values: BatchUpdateValues): Promise<number> {
    return await this.withStoreLease(async () => {
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
    })
  }

  /**
   * 批量删除（不加载实体）
   * @returns 受影响行数
   */
  async delete(): Promise<number> {
    return await this.withStoreLease(async () => {
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
    })
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

  /**
   * 将 ResultSet 当前行转换为 ResultSetRow（原生查询）
   */
  private resultSetToRawRow(resultSet: relationalStore.ResultSet): ResultSetRow {
    const row = new ResultSetRow()
    const columnNames = resultSet.columnNames
    for (let i = 0; i < columnNames.length; i++) {
      const columnName = columnNames[i]
      try {
        const columnIndex = resultSet.getColumnIndex(columnName)
        row.set(columnName, ResultSetUtils.getValueByRuntimeType(resultSet, columnIndex))
      } catch (e) {
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
    return await this.withStoreLease(async () => {
      this.ensureEntityQueryMode('SELECT')
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

        if (subQueryContext.subQueryIdBatches) {
          const batchColumns = this.ensureOrderBySelected(this.queryBuilder.getSelectedColumns())
          let results = await this.queryEntitiesBySubQueryBatchesAsync(
            store,
            batchColumns,
            subQueryContext.subQueryIdBatches,
            subQueryContext.originalConditionCount
          )
          const rowCount = results.length
          const duration = Date.now() - startTime
          this.logger.logDebug(`getAsync 执行完成，数据量: ${rowCount}，耗时: ${duration}ms`)

          results = this.sortResultsByOrder(results)
          results = applyLimitOffsetUtil(results, subQueryContext.originalLimit, subQueryContext.originalOffset)
          results = await this.applyRelationProcessing(results)
          await this.emitSlowQuery('SELECT', this.toSQL(), Date.now() - startTime)
          return results
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
          results = filterEntitiesByIdSet(
            results,
            subQueryContext.inMemoryFilterIds,
            (entity) => this.dataMapper.getPrimaryKeyValue(entity)
          )
          results = applyLimitOffsetUtil(results, subQueryContext.originalLimit, subQueryContext.originalOffset)
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
    })
  }

  /**
   * 原生查询（返回 ResultSetRow 数组）
   * 支持 selectRaw/groupBy/having 等原生表达式
   */
  async getRaw(): Promise<Array<ResultSetRow>> {
    return await this.withStoreLease(async () => {
      const startTime = Date.now()
      const subQueryContext = this.createSubQueryExecutionContext()
      await DatabaseManager.getInstance().acquireQuerySlot()
      try {
        const store = this.getStore()

        await this.prepareSubQueries(subQueryContext, true)
        if (subQueryContext.noMatch) {
          await this.emitSlowQuery('RAW_SELECT', this.toSQL(), Date.now() - startTime)
          return []
        }
        if (subQueryContext.subQueryIdBatches) {
          if (!this.canSortRawByOrder()) {
            throw new ExecutionError('RAW_SELECT', 'getRaw 子查询分批要求 SELECT 显式包含 ORDER BY 列')
          }
          let rows = await this.queryRawBySubQueryBatches(
            store,
            subQueryContext.subQueryIdBatches,
            subQueryContext.originalConditionCount
          )
          rows = this.sortRowsByOrder(rows)
          rows = applyLimitOffsetUtil(rows, subQueryContext.originalLimit, subQueryContext.originalOffset)
          await this.emitSlowQuery('RAW_SELECT', this.toSQL(), Date.now() - startTime)
          return rows
        }
        if (subQueryContext.inMemoryFilterIds) {
          throw new ExecutionError('RAW_SELECT', 'getRaw 不支持 whereExists 的内存过滤，请调整查询条件')
        }

        const sqlResult = this.buildSelectSql()
        let resultSet: relationalStore.ResultSet | null = null
        const rows: Array<ResultSetRow> = []
        try {
          resultSet = await this.withQueryTimeout(store.querySql(sqlResult.sql, sqlResult.args), 'RAW_SELECT')
          while (resultSet.goToNextRow()) {
            rows.push(this.resultSetToRawRow(resultSet))
          }
        } finally {
          this.closeResultSet(resultSet)
        }
        await this.emitSlowQuery('RAW_SELECT', sqlResult.sql, Date.now() - startTime)
        return rows
      } catch (error) {
        const errorMessage = error instanceof Error ? error.message : String(error)
        throw new ExecutionError('RAW_SELECT', errorMessage)
      } finally {
        DatabaseManager.getInstance().releaseQuerySlot()
        this.finalizeSubQueryContext(subQueryContext)
      }
    })
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

    const subQueryIds = normalizeSubQueryIds(await this.subQueryExecutor.executeSubQueries())
    if (subQueryIds.length === 0) {
      context.noMatch = true
      return
    }

    if (hasOrConditions(this.queryBuilder.getConditions())) {
      context.inMemoryFilterIds = buildIdSetFromValues(subQueryIds)
      if (adjustLimitOffsetWhenInMemory && (context.originalLimit > 0 || context.originalOffset > 0)) {
        this.queryBuilder.limit(0)
        this.queryBuilder.offset(0)
        context.limitAdjusted = true
      }
      return
    }

    if (subQueryIds.length > QueryExecutor.subQueryInLimit) {
      context.subQueryIdBatches = splitIntoBatchesUtil(subQueryIds, QueryExecutor.subQueryInLimit)
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
    try {
      if (selectedColumns.length > 0) {
        return await this.withQueryTimeout(store.query(predicates, selectedColumns), operation)
      }
      return await this.withQueryTimeout(store.query(predicates), operation)
    } catch (e) {
      if (e instanceof Error) {
        throw e
      }
      throw new Error(String(e))
    }
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

      try {
        while (queriedResultSet.goToNextRow()) {
          const row = this.resultSetToRow(queriedResultSet)
          results.push(this.dataMapper.fromResultSetRow(row))
        }
      } catch (e) {
        if (e instanceof Error) {
          throw e
        }
        throw new Error(String(e))
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
        if (rawValue !== null && !(rawValue instanceof Uint8Array) && idSet.has(toIdKeyUtil(rawValue as ValueType))) {
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

  private buildSelectSql(): QueryExecutorSqlResult {
    return this.sqlSupport.buildSelectSql()
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
  ): QueryExecutorWhereClauseResult {
    return this.sqlSupport.buildWhereClause(conditions)
  }

  private escapeIdentifier(identifier: string): string {
    return this.sqlSupport.escapeIdentifier(identifier)
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

  private ensureOrderBySelected(selectedColumns: Array<string>): Array<string> {
    if (selectedColumns.length === 0) {
      return selectedColumns
    }
    const orderByColumns = this.queryBuilder.getOrderByColumns()
    if (orderByColumns.length === 0) {
      return selectedColumns
    }
    const columns: Array<string> = []
    for (let i = 0; i < selectedColumns.length; i++) {
      columns.push(selectedColumns[i])
    }
    for (let i = 0; i < orderByColumns.length; i++) {
      const columnName = orderByColumns[i].column
      if (!columns.includes(columnName)) {
        columns.push(columnName)
      }
    }
    return columns
  }

  private sortResultsByOrder(results: Array<EntityData>): Array<EntityData> {
    const orderByColumns = this.queryBuilder.getOrderByColumns()
    if (orderByColumns.length === 0 || results.length <= 1) {
      return results
    }
    const metadata = this.queryBuilder.getEntityMetadata()
    const orderDefs: Array<OrderDefinition> = []
    for (let i = 0; i < orderByColumns.length; i++) {
      const columnName = orderByColumns[i].column
      const columnMeta = metadata.getColumnByName(columnName) ?? metadata.getColumnByProperty(columnName)
      const propertyName = columnMeta ? columnMeta.propertyName : columnName
      const orderDef: OrderDefinition = {
        propertyName,
        direction: String(orderByColumns[i].direction)
      }
      orderDefs.push(orderDef)
    }
    results.sort((left, right) => {
      for (let i = 0; i < orderDefs.length; i++) {
        const def = orderDefs[i]
        const aValue = left.getPropertyValue(def.propertyName)
        const bValue = right.getPropertyValue(def.propertyName)
        const cmp = compareOrderValuesUtil(aValue, bValue, def.direction)
        if (cmp !== 0) {
          return cmp
        }
      }
      return 0
    })
    return results
  }

  private sortRowsByOrder(rows: Array<ResultSetRow>): Array<ResultSetRow> {
    const orderByColumns = this.queryBuilder.getOrderByColumns()
    if (orderByColumns.length === 0 || rows.length <= 1) {
      return rows
    }
    rows.sort((left, right) => {
      for (let i = 0; i < orderByColumns.length; i++) {
        const columnName = orderByColumns[i].column
        const aValue = left.get(columnName) as ValueType
        const bValue = right.get(columnName) as ValueType
        const cmp = compareOrderValuesUtil(aValue, bValue, String(orderByColumns[i].direction))
        if (cmp !== 0) {
          return cmp
        }
      }
      return 0
    })
    return rows
  }

  private canSortRawByOrder(): boolean {
    const orderByColumns = this.queryBuilder.getOrderByColumns()
    if (orderByColumns.length === 0) {
      return true
    }
    const selectedColumns = this.queryBuilder.getSelectedColumns()
    if (selectedColumns.length === 0) {
      return true
    }
    for (let i = 0; i < orderByColumns.length; i++) {
      if (!selectedColumns.includes(orderByColumns[i].column)) {
        return false
      }
    }
    return true
  }

  private restoreConditions(originalCount: number): void {
    restoreConditionsUtil(this.queryBuilder.getConditions(), originalCount)
  }

  private async queryEntitiesBySubQueryBatches(
    store: relationalStore.RdbStore,
    selectedColumns: Array<string>,
    batches: Array<Array<ValueType>>,
    originalConditionCount: number
  ): Promise<Array<EntityData>> {
    const results: Array<EntityData> = []
    for (let i = 0; i < batches.length; i++) {
      const batch = batches[i]
      try {
        if (!this.applySubQueryFilter(batch)) {
          return []
        }
        const predicates = this.buildPredicatesOrThrow('SELECT')
        const batchResults = await this.queryEntities(store, predicates, selectedColumns)
        for (let j = 0; j < batchResults.length; j++) {
          results.push(batchResults[j])
        }
      } finally {
        this.restoreConditions(originalConditionCount)
      }
    }
    return results
  }

  private async queryEntitiesBySubQueryBatchesAsync(
    store: relationalStore.RdbStore,
    selectedColumns: Array<string>,
    batches: Array<Array<ValueType>>,
    originalConditionCount: number
  ): Promise<Array<EntityData>> {
    const results: Array<EntityData> = []
    for (let i = 0; i < batches.length; i++) {
      const batch = batches[i]
      let resultSet: relationalStore.ResultSet | null = null
      try {
        if (!this.applySubQueryFilter(batch)) {
          return []
        }
        const predicates = this.buildPredicatesOrThrow('SELECT')
        const queriedResultSet = await this.queryResultSet(store, predicates, selectedColumns, 'SELECT')
        resultSet = queriedResultSet
        const rowCount = queriedResultSet.rowCount
        let batchResults: Array<EntityData> = []
        if (rowCount > QueryExecutor.TASKPOOL_THRESHOLD) {
          batchResults = await this.queryResultTransformer.transformWithTaskPool(queriedResultSet)
        } else {
          batchResults = this.queryResultTransformer.transformInMainThread(queriedResultSet)
        }
        for (let j = 0; j < batchResults.length; j++) {
          results.push(batchResults[j])
        }
      } finally {
        this.closeResultSet(resultSet)
        this.restoreConditions(originalConditionCount)
      }
    }
    return results
  }

  private async countBySubQueryBatches(
    store: relationalStore.RdbStore,
    batches: Array<Array<ValueType>>,
    originalConditionCount: number
  ): Promise<number> {
    let total = 0
    for (let i = 0; i < batches.length; i++) {
      const batch = batches[i]
      try {
        if (!this.applySubQueryFilter(batch)) {
          return 0
        }
        total += await this.countByPredicates(store)
      } finally {
        this.restoreConditions(originalConditionCount)
      }
    }
    return total
  }

  private async queryRawBySubQueryBatches(
    store: relationalStore.RdbStore,
    batches: Array<Array<ValueType>>,
    originalConditionCount: number
  ): Promise<Array<ResultSetRow>> {
    const rows: Array<ResultSetRow> = []
    for (let i = 0; i < batches.length; i++) {
      const batch = batches[i]
      let resultSet: relationalStore.ResultSet | null = null
      try {
        if (!this.applySubQueryFilter(batch)) {
          return []
        }
        const sqlResult = this.buildSelectSql()
        try {
          resultSet = await this.withQueryTimeout(store.querySql(sqlResult.sql, sqlResult.args), 'RAW_SELECT')
        } catch (e) {
          const error = e instanceof Error ? e : new Error(String(e))
          throw error
        }
        try {
          while (resultSet.goToNextRow()) {
            rows.push(this.resultSetToRawRow(resultSet))
          }
        } catch (e) {
          const error = e instanceof Error ? e : new Error(String(e))
          throw error
        }
      } finally {
        this.closeResultSet(resultSet)
        this.restoreConditions(originalConditionCount)
      }
    }
    return rows
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
    return await this.withStoreLease(async () => {
      return await this.aggregateExecutor.sum(column)
    })
  }

  /**
   * 计算指定列的平均值
   * @param column 列名或属性名
   * @returns Promise<number>
   */
  async avg(column: string): Promise<number> {
    return await this.withStoreLease(async () => {
      return await this.aggregateExecutor.avg(column)
    })
  }

  /**
   * 获取指定列的最大值
   * @param column 列名或属性名
   * @returns Promise<ValueType>
   */
  async max(column: string): Promise<ValueType> {
    return await this.withStoreLease(async () => {
      return await this.aggregateExecutor.max(column)
    })
  }

  /**
   * 获取指定列的最小值
   * @param column 列名或属性名
   * @returns Promise<ValueType>
   */
  async min(column: string): Promise<ValueType> {
    return await this.withStoreLease(async () => {
      return await this.aggregateExecutor.min(column)
    })
  }

  /**
   * 执行分组聚合查询
   * 使用 selectRaw() 和 groupBy() 构建的查询
   * @returns Promise<AggregateResult>
   */
  async aggregate(): Promise<AggregateResult> {
    return await this.withStoreLease(async () => {
      return await this.aggregateExecutor.aggregate()
    })
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
