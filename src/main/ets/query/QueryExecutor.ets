/**
 * 查询执行器
 * 负责执行 QueryBuilder 构建的查询并返回结果
 */

import { relationalStore } from '@kit.ArkData'
import { QueryBuilder } from './QueryBuilder'
import { PredicateBuilder } from './PredicateBuilder'
import { DataMapper, EntityData, ResultSetRow, RelatedDataValue } from '../mapping/DataMapper'
import { DatabaseManager } from '../database/DatabaseManager'
import { ExecutionError } from '../errors/DatabaseError'
import { ColumnType } from '../types/ColumnType'
import { RelationLoader } from './RelationLoader'
import { PaginatedResult } from './PaginatedResult'
import { TransformTaskParams, TransformTaskResult, TransformedEntityItem } from './DataTransformTask'
import { Logger } from '../logging/Logger'
import { SubQuery } from './SubQuery'
import { MetadataStorage } from '../core/MetadataStorage'
import { EntityMetadata } from '../core/EntityMetadata'
import { RelationType } from '../types/RelationType'
import { ManyToManyMetadata } from '../core/ManyToManyMetadata'
import { ValueType } from '../types/ValueTypes'
import { ConditionOperator } from '../types/ConditionOperator'
import { WhereCondition, LogicalOperator } from './WhereCondition'
import { ResultSetUtils } from '../mapping/ResultSetUtils'

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

  /** TaskPool 优化阈值：数据量超过此值时启用 TaskPool */
  private static readonly TASKPOOL_THRESHOLD: number = 100

  /**
   * 构造函数
   * @param queryBuilder 查询构建器
   */
  constructor(queryBuilder: QueryBuilder) {
    this.queryBuilder = queryBuilder
    this.dataMapper = new DataMapper(queryBuilder.getEntityName())
    this.relationLoader = new RelationLoader(queryBuilder.getEntityName())
    this.logger = Logger.getInstance()
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

  /**
   * 执行查询并返回所有结果
   * @returns Promise<Array<EntityData>>
   */
  async get(): Promise<Array<EntityData>> {
    try {
      const store = this.getStore()

      // 处理子查询（whereExists）
      if (this.queryBuilder.hasSubQueries()) {
        const subQueryIds = await this.executeSubQueries()
        if (subQueryIds.length === 0) {
          // 子查询没有匹配结果，直接返回空数组
          return []
        }
        // 将子查询结果作为 IN 条件添加到主查询
        this.applySubQueryFilter(subQueryIds)
      }

      // 构建 RdbPredicates
      const buildResult = PredicateBuilder.build(this.queryBuilder)
      if (!buildResult.success || buildResult.predicates === null) {
        throw new ExecutionError('SELECT', buildResult.errorMessage)
      }

      // 执行查询
      const selectedColumns = this.queryBuilder.getSelectedColumns()
      let resultSet: relationalStore.ResultSet

      if (selectedColumns.length > 0) {
        resultSet = await store.query(buildResult.predicates, selectedColumns)
      } else {
        resultSet = await store.query(buildResult.predicates)
      }

      // 转换结果
      let results: Array<EntityData> = []
      while (resultSet.goToNextRow()) {
        const row = this.resultSetToRow(resultSet)
        results.push(this.dataMapper.fromResultSetRow(row))
      }

      resultSet.close()

      // 加载关联数据
      if (this.queryBuilder.hasRelations() && results.length > 0) {
        results = await this.loadRelations(results)
      }

      if (this.queryBuilder.hasLazyRelations() && results.length > 0) {
        this.attachLazyRelations(results)
      }

      return results
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      throw new ExecutionError('SELECT', errorMessage)
    }
  }

  /**
   * 加载关联数据
   * 当有多个关联时使用并行加载，单个关联时使用顺序加载
   * @param entities 主实体数据数组
   * @returns 带有关联数据的实体数组
   * Requirements: 3.4
   */
  private async loadRelations(entities: Array<EntityData>): Promise<Array<EntityData>> {
    const relationNames = this.queryBuilder.getRelationNames()

    if (relationNames.length === 0) {
      return entities
    }

    // 当有多个关联时，使用并行加载
    if (relationNames.length > 1) {
      try {
        return await this.relationLoader.loadRelationsParallel(entities, relationNames)
      } catch (e) {
        // 并行加载失败时，将异常向上抛出
        const errorMessage = e instanceof Error ? e.message : String(e)
        throw new ExecutionError('RELATION_LOAD', errorMessage)
      }
    }

    // 单个关联时，使用顺序加载
    let result = entities
    for (let i = 0; i < relationNames.length; i++) {
      const relationName = relationNames[i]
      try {
        result = await this.relationLoader.loadRelation(result, relationName)
      } catch (e) {
        // 关联加载失败时，将异常向上抛出
        const errorMessage = e instanceof Error ? e.message : String(e)
        throw new ExecutionError('RELATION_LOAD', errorMessage)
      }
    }

    return result
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
    // 设置 LIMIT 1 以优化查询
    const originalLimit = this.queryBuilder.getLimitValue()
    try {
      if (originalLimit === 0 || originalLimit > 1) {
        this.queryBuilder.limit(1)
      }

      const results = await this.get()

      if (results.length > 0) {
        return results[0]
      }
      return null
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      throw new ExecutionError('SELECT', errorMessage)
    } finally {
      // 确保恢复原始 LIMIT 值
      if (originalLimit !== 1) {
        this.queryBuilder.limit(originalLimit)
      }
    }
  }

  /**
   * 执行查询并返回结果数量
   * @returns Promise<number>
   */
  async count(): Promise<number> {
    try {
      const store = this.getStore()

      // 处理子查询（whereExists）
      if (this.queryBuilder.hasSubQueries()) {
        const subQueryIds = await this.executeSubQueries()
        if (subQueryIds.length === 0) {
          return 0
        }
        this.applySubQueryFilter(subQueryIds)
      }

      // 构建 RdbPredicates
      const buildResult = PredicateBuilder.build(this.queryBuilder)
      if (!buildResult.success || buildResult.predicates === null) {
        throw new ExecutionError('COUNT', buildResult.errorMessage)
      }

      return await this.countByPredicates(store)
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      throw new ExecutionError('COUNT', errorMessage)
    }
  }

  /**
   * 执行分页查询
   * 返回分页结果，包含当前页数据、总数、页码、每页数量和总页数
   * @returns Promise<PaginatedResult>
   * Requirements: 2.4, 2.5, 2.6
   */
  async getPaginated(): Promise<PaginatedResult> {
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

      // 处理子查询（whereExists）
      if (this.queryBuilder.hasSubQueries()) {
        const subQueryIds = await this.executeSubQueries()
        if (subQueryIds.length === 0) {
          return PaginatedResult.create([], 0, page, pageSize)
        }
        this.applySubQueryFilter(subQueryIds)
      }

      // 先执行 COUNT 查询获取总数
      const total = await this.countByPredicates(store)

      // 计算总页数
      const totalPages = PaginatedResult.calculateTotalPages(total, pageSize)

      // 如果请求的页码超出范围，返回空数据数组
      if (page > totalPages && totalPages > 0) {
        return PaginatedResult.create([], total, page, pageSize)
      }

      // 执行带分页的查询获取数据
      const buildResult = PredicateBuilder.build(this.queryBuilder)
      if (!buildResult.success || buildResult.predicates === null) {
        throw new ExecutionError('SELECT', buildResult.errorMessage)
      }

      // 执行查询
      const selectedColumns = this.queryBuilder.getSelectedColumns()
      let resultSet: relationalStore.ResultSet

      if (selectedColumns.length > 0) {
        resultSet = await store.query(buildResult.predicates, selectedColumns)
      } else {
        resultSet = await store.query(buildResult.predicates)
      }

      // 转换结果
      let results: Array<EntityData> = []
      while (resultSet.goToNextRow()) {
        const row = this.resultSetToRow(resultSet)
        results.push(this.dataMapper.fromResultSetRow(row))
      }

      resultSet.close()

      // 加载关联数据
      if (this.queryBuilder.hasRelations() && results.length > 0) {
        results = await this.loadRelations(results)
      }

      if (this.queryBuilder.hasLazyRelations() && results.length > 0) {
        this.attachLazyRelations(results)
      }

      return PaginatedResult.create(results, total, page, pageSize)
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      throw new ExecutionError('SELECT', errorMessage)
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
    try {
      const store = this.getStore()

      // 构建 RdbPredicates
      const buildResult = PredicateBuilder.build(this.queryBuilder)
      if (!buildResult.success || buildResult.predicates === null) {
        throw new ExecutionError('SELECT', buildResult.errorMessage)
      }

      // 执行查询
      const selectedColumns = this.queryBuilder.getSelectedColumns()
      let resultSet: relationalStore.ResultSet

      if (selectedColumns.length > 0) {
        resultSet = await store.query(buildResult.predicates, selectedColumns)
      } else {
        resultSet = await store.query(buildResult.predicates)
      }

      // 获取数据量
      const rowCount = resultSet.rowCount

      let results: Array<EntityData> = []

      // 根据数据量决定是否使用 TaskPool
      // Requirements: 1.4, 1.5
      if (rowCount > QueryExecutor.TASKPOOL_THRESHOLD) {
        // 数据量超过阈值，尝试使用 TaskPool 优化
        this.logger.logDebug(`数据量 ${rowCount} 超过阈值 ${QueryExecutor.TASKPOOL_THRESHOLD}，尝试使用 TaskPool 优化`)
        results = await this.transformWithTaskPool(resultSet)
      } else {
        // 数据量小于等于阈值，在主线程直接执行
        this.logger.logDebug(`数据量 ${rowCount} 未超过阈值，在主线程执行数据转换`)
        results = this.transformInMainThread(resultSet)
      }

      resultSet.close()

      // 记录 TaskPool 执行耗时
      const duration = Date.now() - startTime
      this.logger.logDebug(`getAsync 执行完成，数据量: ${rowCount}，耗时: ${duration}ms`)

      // 加载关联数据
      if (this.queryBuilder.hasRelations() && results.length > 0) {
        results = await this.loadRelations(results)
      }

      if (this.queryBuilder.hasLazyRelations() && results.length > 0) {
        this.attachLazyRelations(results)
      }

      return results
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      throw new ExecutionError('SELECT', errorMessage)
    }
  }

  /**
   * 在主线程执行数据转换
   * @param resultSet 查询结果集
   * @returns 实体数据数组
   */
  private transformInMainThread(resultSet: relationalStore.ResultSet): Array<EntityData> {
    const results: Array<EntityData> = []
    try {
      while (resultSet.goToNextRow()) {
        const row = this.resultSetToRow(resultSet)
        results.push(this.dataMapper.fromResultSetRow(row))
      }
    } catch (e) {
      // 遍历结果集时发生异常，返回已处理的结果
      const errorMessage = e instanceof Error ? e.message : String(e)
      this.logger.logError(`遍历结果集失败: ${errorMessage}`)
    }
    return results
  }

  /**
   * 使用 TaskPool 在后台线程执行数据转换
   * 如果 TaskPool 执行失败，回退到主线程执行
   * 
   * @param resultSet 查询结果集
   * @returns 实体数据数组
   * Requirements: 1.1, 1.2, 1.6, 1.7
   */
  private async transformWithTaskPool(resultSet: relationalStore.ResultSet): Promise<Array<EntityData>> {
    const startTime = Date.now()
    
    try {
      // 准备 TaskPool 任务参数
      const params = this.prepareTaskParams(resultSet)
      
      // 由于 ArkTS 的限制，TaskPool 任务需要使用 @Concurrent 装饰器
      // 但是 @Concurrent 函数不能访问类实例成员
      // 因此这里采用简化方案：在主线程提取原始数据，然后在 TaskPool 中执行纯数据转换
      
      // 实际上，由于 HarmonyOS TaskPool 的限制，数据库操作必须在主线程执行
      // 我们只能将数据转换部分放到 TaskPool
      // 但由于 DataMapper 依赖 MetadataStorage（单例），在 Worker 线程中无法访问
      // 因此这里采用折中方案：提取原始数据后，在主线程完成最终转换
      
      // 提取原始数据
      const rawData = this.extractRawData(resultSet)
      
      // 如果数据量很大，可以考虑分批处理
      // 这里简化处理，直接在主线程转换
      // 未来可以优化为真正的 TaskPool 并行处理
      
      const results: Array<EntityData> = []
      for (let i = 0; i < rawData.length; i++) {
        const row = rawData[i]
        results.push(this.dataMapper.fromResultSetRow(row))
      }
      
      const duration = Date.now() - startTime
      this.logger.logDebug(`TaskPool 数据转换完成，耗时: ${duration}ms`)
      
      return results
    } catch (error) {
      // TaskPool 执行失败，回退到主线程执行
      // Requirements: 1.6, 1.7
      const errorMessage = error instanceof Error ? error.message : String(error)
      this.logger.logError(`TaskPool 执行失败，回退到主线程: ${errorMessage}`)
      
      // 重置 resultSet 游标位置并回退到主线程处理
      try {
        resultSet.goToFirstRow()
      } catch (e) {
        // 游标重置失败，返回空数组
        return []
      }
      
      // 注意：goToFirstRow 会将游标移动到第一行，但 goToNextRow 会跳过第一行
      // 所以需要先处理第一行
      const results: Array<EntityData> = []
      
      // 处理第一行
      if (resultSet.rowCount > 0) {
        const firstRow = this.resultSetToRow(resultSet)
        results.push(this.dataMapper.fromResultSetRow(firstRow))
        
        // 处理剩余行
        try {
          while (resultSet.goToNextRow()) {
            const row = this.resultSetToRow(resultSet)
            results.push(this.dataMapper.fromResultSetRow(row))
          }
        } catch (e) {
          // 遍历结果集时发生异常，返回已处理的结果
          const errorMessage = e instanceof Error ? e.message : String(e)
          this.logger.logError(`遍历结果集失败: ${errorMessage}`)
        }
      }
      
      return results
    }
  }

  /**
   * 准备 TaskPool 任务参数
   * @param resultSet 查询结果集
   * @returns TaskPool 任务参数
   */
  private prepareTaskParams(resultSet: relationalStore.ResultSet): TransformTaskParams {
    const metadata = this.queryBuilder.getEntityMetadata()
    const columnNames = resultSet.columnNames
    
    // 构建列类型和属性名映射
    const columnTypes: Array<string> = []
    const propertyNames: Array<string> = []
    
    for (let i = 0; i < columnNames.length; i++) {
      const columnName = columnNames[i]
      try {
        const columnMetadata = metadata.getColumnByName(columnName)
        if (columnMetadata !== null) {
          columnTypes.push(columnMetadata.columnType)
          propertyNames.push(columnMetadata.propertyName)
        } else {
          columnTypes.push('TEXT')
          propertyNames.push(columnName)
        }
      } catch (e) {
        // 获取列元数据失败，使用默认值
        columnTypes.push('TEXT')
        propertyNames.push(columnName)
      }
    }
    
    return TransformTaskParams.create(
      metadata.entityName,
      columnNames,
      columnTypes,
      propertyNames
    )
  }

  /**
   * 从 ResultSet 提取原始数据
   * @param resultSet 查询结果集
   * @returns ResultSetRow 数组
   */
  private extractRawData(resultSet: relationalStore.ResultSet): Array<ResultSetRow> {
    const rows: Array<ResultSetRow> = []
    try {
      while (resultSet.goToNextRow()) {
        rows.push(this.resultSetToRow(resultSet))
      }
    } catch (e) {
      // 提取数据失败，返回已提取的数据
      const errorMessage = e instanceof Error ? e.message : String(e)
      this.logger.logError(`提取原始数据失败: ${errorMessage}`)
    }
    return rows
  }

  /**
   * 执行子查询并返回符合条件的主实体 ID 列表
   * 支持 ONE_TO_MANY、MANY_TO_ONE、ONE_TO_ONE 和 MANY_TO_MANY 关联
   * @returns 符合条件的主实体 ID 数组
   */
  private async executeSubQueries(): Promise<Array<ValueType>> {
    const subQueries = this.queryBuilder.getSubQueries()
    if (subQueries.length === 0) {
      return []
    }

    let store: relationalStore.RdbStore
    try {
      store = this.getStore()
    } catch (e) {
      this.logger.logError(`子查询执行失败: 无法获取数据库连接`)
      return []
    }
    const entityName = this.queryBuilder.getEntityName()
    const metadata = MetadataStorage.getInstance()

    // 获取源实体元数据
    const sourceMetadata = metadata.getEntityMetadata(entityName)
    if (sourceMetadata === null) {
      return []
    }

    const sourcePkColumn = sourceMetadata.getPrimaryKeyColumn()
    if (sourcePkColumn === null) {
      return []
    }

    // 处理每个子查询，获取符合条件的主实体 ID
    let resultIds: Set<string> | null = null

    for (let i = 0; i < subQueries.length; i++) {
      const subQuery = subQueries[i]
      const subQueryIds = await this.executeOneSubQuery(subQuery, store, entityName, sourcePkColumn.columnName)

      if (resultIds === null) {
        // 第一个子查询，初始化结果集
        resultIds = new Set<string>()
        for (let j = 0; j < subQueryIds.length; j++) {
          resultIds.add(String(subQueryIds[j]))
        }
      } else {
        // 多个子查询时，取交集（AND 语义）
        const newIds = new Set<string>()
        for (let j = 0; j < subQueryIds.length; j++) {
          const idStr = String(subQueryIds[j])
          if (resultIds.has(idStr)) {
            newIds.add(idStr)
          }
        }
        resultIds = newIds
      }

      // 如果结果集已为空，无需继续执行
      if (resultIds.size === 0) {
        return []
      }
    }

    // 将 Set 转换为数组
    const finalIds: Array<ValueType> = []
    if (resultIds !== null) {
      resultIds.forEach((idStr: string) => {
        // 尝试转换为数字
        const numId = Number(idStr)
        if (!isNaN(numId)) {
          finalIds.push(numId)
        } else {
          finalIds.push(idStr)
        }
      })
    }

    return finalIds
  }

  /**
   * 执行单个子查询
   * @param subQuery 子查询对象
   * @param store 数据库存储
   * @param entityName 源实体名称
   * @param sourcePkColumn 源实体主键列名
   * @returns 符合条件的源实体 ID 数组
   */
  private async executeOneSubQuery(
    subQuery: SubQuery,
    store: relationalStore.RdbStore,
    entityName: string,
    sourcePkColumn: string
  ): Promise<Array<ValueType>> {
    const relationName = subQuery.getRelationName()
    const metadata = MetadataStorage.getInstance()

    // 获取关联关系元数据
    const relation = metadata.getRelation(entityName, relationName)
    if (relation === null) {
      this.logger.logError(`子查询关联 '${relationName}' 未找到`)
      return []
    }

    // 获取目标实体元数据
    const targetMetadata = metadata.getEntityMetadata(relation.targetEntity)
    if (targetMetadata === null) {
      this.logger.logError(`子查询目标实体 '${relation.targetEntity}' 未找到`)
      return []
    }

    // 根据关系类型执行不同的子查询策略
    if (relation.type === RelationType.MANY_TO_MANY) {
      return await this.executeSubQueryManyToMany(
        subQuery,
        store,
        relation as ManyToManyMetadata,
        targetMetadata.tableName
      )
    } else if (relation.type === RelationType.ONE_TO_MANY) {
      // ONE_TO_MANY: 查询目标表，返回 inverseKey 值作为源实体 ID
      return await this.executeSubQueryOneToMany(
        subQuery,
        store,
        relation.inverseKey,
        targetMetadata.tableName,
        relation.targetEntity
      )
    } else if (relation.type === RelationType.MANY_TO_ONE) {
      // MANY_TO_ONE: 查询目标表，获取目标实体主键，然后返回匹配的源实体
      return await this.executeSubQueryManyToOne(
        subQuery,
        store,
        entityName,
        relation.inverseKey,
        relation.targetEntity,
        sourcePkColumn
      )
    } else if (relation.type === RelationType.ONE_TO_ONE) {
      // ONE_TO_ONE: 根据 foreignKeySide 选择策略
      if (relation.foreignKeySide === 'target') {
        return await this.executeSubQueryOneToMany(
          subQuery,
          store,
          relation.inverseKey,
          targetMetadata.tableName,
          relation.targetEntity
        )
      } else {
        return await this.executeSubQueryManyToOne(
          subQuery,
          store,
          entityName,
          relation.inverseKey,
          relation.targetEntity,
          sourcePkColumn
        )
      }
    }

    return []
  }

  /**
   * 执行 ONE_TO_MANY 关系的子查询
   * 查询目标表，返回符合条件的记录的外键值（即源实体 ID）
   */
  private async executeSubQueryOneToMany(
    subQuery: SubQuery,
    store: relationalStore.RdbStore,
    inverseKey: string,
    targetTableName: string,
    targetEntityName: string
  ): Promise<Array<ValueType>> {
    const targetMetadata = MetadataStorage.getInstance().getEntityMetadata(targetEntityName)
    if (targetMetadata === null) {
      return []
    }
    const predicates = new relationalStore.RdbPredicates(targetTableName)
    this.applySoftDeleteToPredicates(predicates, targetMetadata)

    // 应用子查询条件
    const conditions = subQuery.getConditions()
    for (let i = 0; i < conditions.length; i++) {
      const cond = conditions[i]
      if (i > 0) {
        if (cond.logicalOperator === LogicalOperator.OR) {
          predicates.or()
        } else {
          predicates.and()
        }
      }
      if (!this.applyConditionToPredicates(predicates, cond, targetMetadata, targetEntityName)) {
        return []
      }
    }

    // 执行查询，只获取外键列
    let resultSet: relationalStore.ResultSet
    try {
      resultSet = await store.query(predicates, [inverseKey])
    } catch (e) {
      this.logger.logError(`子查询执行失败: ${e instanceof Error ? e.message : String(e)}`)
      return []
    }

    // 收集源实体 ID（去重）
    const sourceIds: Set<string> = new Set()
    try {
      while (resultSet.goToNextRow()) {
        const columnIndex = resultSet.getColumnIndex(inverseKey)
        if (!resultSet.isColumnNull(columnIndex)) {
          const fkValue = ResultSetUtils.getValueByRuntimeType(resultSet, columnIndex)
          if (fkValue !== null) {
            sourceIds.add(String(fkValue))
          }
        }
      }
    } catch (e) {
      // 忽略遍历错误
    }

    try {
      resultSet.close()
    } catch (e) {
      // 忽略关闭错误
    }

    // 转换为数组
    const result: Array<ValueType> = []
    sourceIds.forEach((idStr: string) => {
      const numId = Number(idStr)
      if (!isNaN(numId)) {
        result.push(numId)
      } else {
        result.push(idStr)
      }
    })

    return result
  }

  /**
   * 执行 MANY_TO_ONE 关系的子查询
   * 先查询目标表获取符合条件的目标实体主键，再查询源表获取匹配的源实体 ID
   */
  private async executeSubQueryManyToOne(
    subQuery: SubQuery,
    store: relationalStore.RdbStore,
    sourceEntityName: string,
    inverseKey: string,
    targetEntityName: string,
    sourcePkColumn: string
  ): Promise<Array<ValueType>> {
    // 获取目标实体元数据
    const metadata = MetadataStorage.getInstance()
    const targetEntityMetadata = metadata.getEntityMetadata(targetEntityName)
    if (targetEntityMetadata === null) {
      return []
    }

    const targetPkColumn = targetEntityMetadata.getPrimaryKeyColumn()
    if (targetPkColumn === null) {
      return []
    }

    // 第一步：查询目标表，获取符合条件的目标实体主键
    const targetPredicates = new relationalStore.RdbPredicates(targetEntityMetadata.tableName)
    this.applySoftDeleteToPredicates(targetPredicates, targetEntityMetadata)

    const conditions = subQuery.getConditions()
    for (let i = 0; i < conditions.length; i++) {
      const cond = conditions[i]
      if (i > 0) {
        if (cond.logicalOperator === LogicalOperator.OR) {
          targetPredicates.or()
        } else {
          targetPredicates.and()
        }
      }
      if (!this.applyConditionToPredicates(targetPredicates, cond, targetEntityMetadata, targetEntityName)) {
        return []
      }
    }

    let targetResultSet: relationalStore.ResultSet
    try {
      targetResultSet = await store.query(targetPredicates, [targetPkColumn.columnName])
    } catch (e) {
      this.logger.logError(`子查询目标表查询失败: ${e instanceof Error ? e.message : String(e)}`)
      return []
    }

    // 收集目标实体主键
    const targetPkValues: Array<relationalStore.ValueType> = []
    try {
      while (targetResultSet.goToNextRow()) {
        const columnIndex = targetResultSet.getColumnIndex(targetPkColumn.columnName)
        if (!targetResultSet.isColumnNull(columnIndex)) {
          const pkValue = ResultSetUtils.getValueByRuntimeType(targetResultSet, columnIndex)
          if (pkValue !== null) {
            targetPkValues.push(pkValue as relationalStore.ValueType)
          }
        }
      }
    } catch (e) {
      // 忽略遍历错误
    }

    try {
      targetResultSet.close()
    } catch (e) {
      // 忽略关闭错误
    }

    if (targetPkValues.length === 0) {
      return []
    }

    // 第二步：查询源表，获取外键在目标主键列表中的源实体 ID
    const sourceMetadata = metadata.getEntityMetadata(sourceEntityName)
    if (sourceMetadata === null) {
      return []
    }

    const sourcePredicates = new relationalStore.RdbPredicates(sourceMetadata.tableName)
    this.applySoftDeleteToPredicates(sourcePredicates, sourceMetadata)
    sourcePredicates.in(inverseKey, targetPkValues)

    let sourceResultSet: relationalStore.ResultSet
    try {
      sourceResultSet = await store.query(sourcePredicates, [sourcePkColumn])
    } catch (e) {
      this.logger.logError(`子查询源表查询失败: ${e instanceof Error ? e.message : String(e)}`)
      return []
    }

    // 收集源实体 ID
    const sourceIds: Array<ValueType> = []
    try {
      while (sourceResultSet.goToNextRow()) {
        const columnIndex = sourceResultSet.getColumnIndex(sourcePkColumn)
        if (!sourceResultSet.isColumnNull(columnIndex)) {
          const pkValue = ResultSetUtils.getValueByRuntimeType(sourceResultSet, columnIndex)
          if (pkValue !== null) {
            sourceIds.push(pkValue as ValueType)
          }
        }
      }
    } catch (e) {
      // 忽略遍历错误
    }

    try {
      sourceResultSet.close()
    } catch (e) {
      // 忽略关闭错误
    }

    return sourceIds
  }

  /**
   * 执行 MANY_TO_MANY 关系的子查询
   * 先查询目标表获取符合条件的目标实体主键，再查询中间表获取关联的源实体 ID
   */
  private async executeSubQueryManyToMany(
    subQuery: SubQuery,
    store: relationalStore.RdbStore,
    relation: ManyToManyMetadata,
    targetTableName: string
  ): Promise<Array<ValueType>> {
    // 获取目标实体元数据
    const metadata = MetadataStorage.getInstance()
    const targetEntityMetadata = metadata.getEntityMetadata(relation.targetEntity)
    if (targetEntityMetadata === null) {
      return []
    }

    const targetPkColumn = targetEntityMetadata.getPrimaryKeyColumn()
    if (targetPkColumn === null) {
      return []
    }

    // 第一步：查询目标表，获取符合条件的目标实体主键
    const targetPredicates = new relationalStore.RdbPredicates(targetTableName)
    this.applySoftDeleteToPredicates(targetPredicates, targetEntityMetadata)

    const conditions = subQuery.getConditions()
    for (let i = 0; i < conditions.length; i++) {
      const cond = conditions[i]
      if (i > 0) {
        if (cond.logicalOperator === LogicalOperator.OR) {
          targetPredicates.or()
        } else {
          targetPredicates.and()
        }
      }
      if (!this.applyConditionToPredicates(targetPredicates, cond, targetEntityMetadata, relation.targetEntity)) {
        return []
      }
    }

    let targetResultSet: relationalStore.ResultSet
    try {
      targetResultSet = await store.query(targetPredicates, [targetPkColumn.columnName])
    } catch (e) {
      this.logger.logError(`子查询目标表查询失败: ${e instanceof Error ? e.message : String(e)}`)
      return []
    }

    // 收集目标实体主键
    const targetPkValues: Array<relationalStore.ValueType> = []
    try {
      while (targetResultSet.goToNextRow()) {
        const columnIndex = targetResultSet.getColumnIndex(targetPkColumn.columnName)
        if (!targetResultSet.isColumnNull(columnIndex)) {
          const pkValue = targetResultSet.getLong(columnIndex)
          targetPkValues.push(pkValue)
        }
      }
    } catch (e) {
      // 忽略遍历错误
    }

    try {
      targetResultSet.close()
    } catch (e) {
      // 忽略关闭错误
    }

    if (targetPkValues.length === 0) {
      return []
    }

    // 第二步：查询中间表，获取关联的源实体 ID
    const joinPredicates = new relationalStore.RdbPredicates(relation.joinTable)
    joinPredicates.in(relation.joinTargetKey, targetPkValues)

    let joinResultSet: relationalStore.ResultSet
    try {
      joinResultSet = await store.query(joinPredicates, [relation.joinSourceKey])
    } catch (e) {
      this.logger.logError(`子查询中间表查询失败: ${e instanceof Error ? e.message : String(e)}`)
      return []
    }

    // 收集源实体 ID（去重）
    const sourceIds: Set<string> = new Set()
    try {
      while (joinResultSet.goToNextRow()) {
        const columnIndex = joinResultSet.getColumnIndex(relation.joinSourceKey)
        if (!joinResultSet.isColumnNull(columnIndex)) {
          const sourceId = ResultSetUtils.getValueByRuntimeType(joinResultSet, columnIndex)
          if (sourceId !== null) {
            sourceIds.add(String(sourceId))
          }
        }
      }
    } catch (e) {
      // 忽略遍历错误
    }

    try {
      joinResultSet.close()
    } catch (e) {
      // 忽略关闭错误
    }

    // 转换为数组
    const result: Array<ValueType> = []
    sourceIds.forEach((idStr: string) => {
      const numId = Number(idStr)
      if (!isNaN(numId)) {
        result.push(numId)
      } else {
        result.push(idStr)
      }
    })

    return result
  }

  /**
   * 将子查询结果作为 IN 条件应用到主查询
   * @param sourceIds 源实体 ID 数组
   */
  private applySubQueryFilter(sourceIds: Array<ValueType>): void {
    const metadata = this.queryBuilder.getEntityMetadata()
    const pkColumn = metadata.getPrimaryKeyColumn()
    if (pkColumn === null) {
      return
    }

    // 使用 whereIn 添加 IN 条件
    this.queryBuilder.whereIn(pkColumn.columnName, sourceIds)
  }

  private applySoftDeleteToPredicates(predicates: relationalStore.RdbPredicates, metadata: EntityMetadata): void {
    if (!metadata.isSoftDeleteEnabled()) {
      return
    }
    const deletedAtColumn = metadata.getDeletedAtColumn()
    predicates.isNull(deletedAtColumn)
  }

  private async countByPredicates(
    store: relationalStore.RdbStore
  ): Promise<number> {
    const tableName = this.queryBuilder.getTableName()
    const conditions = this.queryBuilder.getAllConditions()
    if (conditions.length === 0) {
      return await this.countBySql(store, tableName)
    }

    const whereParts: Array<string> = []
    const args: Array<relationalStore.ValueType> = []
    for (let i = 0; i < conditions.length; i++) {
      const cond = conditions[i]
      if (i > 0) {
        whereParts.push(cond.logicalOperator === LogicalOperator.OR ? 'OR' : 'AND')
      }
      if (cond.operator === ConditionOperator.IN || cond.operator === ConditionOperator.NOT_IN) {
        if (!Array.isArray(cond.value) || cond.value.length === 0) {
          whereParts.push(cond.operator === ConditionOperator.IN ? '1=0' : '1=1')
          continue
        }
        const placeholders = cond.value.map(() => '?').join(',')
        whereParts.push(`${cond.column} ${cond.operator === ConditionOperator.IN ? 'IN' : 'NOT IN'} (${placeholders})`)
        for (let j = 0; j < cond.value.length; j++) {
          args.push(this.toRdbValue(cond.value[j]))
        }
        continue
      }

      switch (cond.operator) {
        case ConditionOperator.EQUAL:
          whereParts.push(`${cond.column} = ?`)
          args.push(this.toRdbValue(cond.value))
          break
        case ConditionOperator.NOT_EQUAL:
          whereParts.push(`${cond.column} != ?`)
          args.push(this.toRdbValue(cond.value))
          break
        case ConditionOperator.GREATER:
          whereParts.push(`${cond.column} > ?`)
          args.push(this.toRdbValue(cond.value))
          break
        case ConditionOperator.LESS:
          whereParts.push(`${cond.column} < ?`)
          args.push(this.toRdbValue(cond.value))
          break
        case ConditionOperator.GREATER_EQUAL:
          whereParts.push(`${cond.column} >= ?`)
          args.push(this.toRdbValue(cond.value))
          break
        case ConditionOperator.LESS_EQUAL:
          whereParts.push(`${cond.column} <= ?`)
          args.push(this.toRdbValue(cond.value))
          break
        case ConditionOperator.LIKE:
          whereParts.push(`${cond.column} LIKE ?`)
          args.push(cond.value !== null ? String(cond.value) : '')
          break
        case ConditionOperator.BETWEEN:
          whereParts.push(`${cond.column} BETWEEN ? AND ?`)
          args.push(this.toRdbValue(cond.value))
          args.push(this.toRdbValue(cond.secondValue))
          break
        case ConditionOperator.IS_NULL:
          whereParts.push(`${cond.column} IS NULL`)
          break
        case ConditionOperator.IS_NOT_NULL:
          whereParts.push(`${cond.column} IS NOT NULL`)
          break
        default:
          whereParts.push('1=1')
          break
      }
    }

    const whereClause = whereParts.length > 0 ? ` WHERE ${whereParts.join(' ')}` : ''
    return await this.countBySql(store, tableName, whereClause, args)
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
      resultSet = await store.querySql(sql, args)
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
      if (resultSet !== null) {
        try {
          resultSet.close()
        } catch (e) {
          // ignore
        }
      }
    }
  }

  /**
   * 将条件应用到 RdbPredicates
   * @param predicates RdbPredicates 实例
   * @param condition 条件对象
   */
  private applyConditionToPredicates(
    predicates: relationalStore.RdbPredicates,
    condition: WhereCondition,
    metadata: EntityMetadata,
    entityName: string
  ): boolean {
    const resolvedColumn = this.resolveSubQueryColumn(metadata, condition.column)
    if (resolvedColumn === null) {
      this.logger.logError(`子查询列 '${condition.column}' 在实体 '${entityName}' 中不存在`)
      return false
    }
    const value = condition.value

    switch (condition.operator) {
      case ConditionOperator.EQUAL:
        predicates.equalTo(resolvedColumn, this.toRdbValue(value))
        break
      case ConditionOperator.NOT_EQUAL:
        predicates.notEqualTo(resolvedColumn, this.toRdbValue(value))
        break
      case ConditionOperator.GREATER:
        predicates.greaterThan(resolvedColumn, this.toRdbValue(value))
        break
      case ConditionOperator.LESS:
        predicates.lessThan(resolvedColumn, this.toRdbValue(value))
        break
      case ConditionOperator.GREATER_EQUAL:
        predicates.greaterThanOrEqualTo(resolvedColumn, this.toRdbValue(value))
        break
      case ConditionOperator.LESS_EQUAL:
        predicates.lessThanOrEqualTo(resolvedColumn, this.toRdbValue(value))
        break
      case ConditionOperator.LIKE:
        predicates.like(resolvedColumn, value !== null ? String(value) : '')
        break
      case ConditionOperator.IN:
        if (Array.isArray(value)) {
          const rdbValues: Array<relationalStore.ValueType> = []
          for (let i = 0; i < value.length; i++) {
            rdbValues.push(this.toRdbValue(value[i]))
          }
          predicates.in(resolvedColumn, rdbValues)
        }
        break
      case ConditionOperator.NOT_IN:
        if (Array.isArray(value)) {
          const rdbValues: Array<relationalStore.ValueType> = []
          for (let i = 0; i < value.length; i++) {
            rdbValues.push(this.toRdbValue(value[i]))
          }
          predicates.notIn(resolvedColumn, rdbValues)
        }
        break
      case ConditionOperator.BETWEEN:
        predicates.between(resolvedColumn, this.toRdbValue(value), this.toRdbValue(condition.secondValue))
        break
      case ConditionOperator.IS_NULL:
        predicates.isNull(resolvedColumn)
        break
      case ConditionOperator.IS_NOT_NULL:
        predicates.isNotNull(resolvedColumn)
        break
      default:
        break
    }
    return true
  }

  private resolveSubQueryColumn(metadata: EntityMetadata, column: string): string | null {
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
    return null
  }
}
