/**
 * 仓库类
 * 提供实体的 CRUD 操作接口
 */

import { relationalStore } from '@kit.ArkData'
import { EntityMetadata } from '../core/EntityMetadata'
import { MetadataStorage } from '../core/MetadataStorage'
import { HooksProcessor } from '../core/HooksProcessor'
import { OrmContext } from '../core/OrmContext'
import { DataMapper } from '../mapping/DataMapper'
import { EntityData } from '../mapping/EntityData'
import { ResultSetRow } from '../mapping/ResultSetRow'
import { QueryBuilder } from '../query/QueryBuilder'
import { QueryExecutor } from '../query/QueryExecutor'
import { PaginatedResult } from '../query/PaginatedResult'
import { DatabaseManager } from '../database/DatabaseManager'
import { Logger } from '../logging/Logger'
import { ValueType } from '../types/ValueTypes'
import { ColumnType } from '../types/ColumnType'
import { EntityNotRegisteredError, PrimaryKeyNotDefinedError } from '../errors/MetadataError'
import { ExecutionError } from '../errors/DatabaseError'
import { HookExecutionError } from '../errors/HookError'
import { BatchInsertResult } from './BatchInsertResult'
import { BatchInsertOptions } from './BatchInsertOptions'
import { TransactionOptions } from './TransactionOptions'
import { QueryCache } from '../query/QueryCache'
import { ResultSetUtils } from '../mapping/ResultSetUtils'
import { CascadeHandler } from './CascadeHandler'
import { SaveResult } from './SaveResult'
import { DeleteResult } from './DeleteResult'
import { TransactionResult } from './TransactionResult'
import { RelationManager } from './RelationManager'
import { TransactionManager } from './TransactionManager'
import { BatchOperations } from './BatchOperations'
import { CrudOperations } from './CrudOperations'
import { DeleteOperations } from './DeleteOperations'

/**
 * 泛型仓库类
 * 提供实体的基本 CRUD 操作
 */
export class Repository {
  /** 实体元数据 */
  private entityMetadata: EntityMetadata
  /** 数据映射器 */
  private dataMapper: DataMapper
  /** 实体名称 */
  private entityName: string
  /** 钩子处理器 */
  private hooksProcessor: HooksProcessor
  /** 日志记录器 */
  private logger: Logger
  /** 查询缓存 */
  private queryCache: QueryCache
  /** 级联处理器 */
  private cascadeHandler: CascadeHandler
  /** 关系管理器 */
  private relationManager: RelationManager
  /** 事务管理器 */
  private transactionManager: TransactionManager
  /** 批量操作管理器 */
  private batchOperations: BatchOperations
  /** CRUD 操作管理器 */
  private crudOperations: CrudOperations
  /** 删除操作管理器 */
  private deleteOperations: DeleteOperations
  /** 事务严格模式深度（>0 表示事务回调中失败结果应抛错） */
  private strictTransactionDepth: number = 0

  /**
   * 构造函数
   * @param entityName 实体名称
   * @throws EntityNotRegisteredError 如果实体未注册
   */
  constructor(entityName: string) {
    this.entityName = entityName
    const metadata = MetadataStorage.getInstance().getEntityMetadata(entityName)
    if (metadata === null) {
      throw new EntityNotRegisteredError(entityName)
    }
    this.entityMetadata = metadata
    this.dataMapper = new DataMapper(entityName)
    this.hooksProcessor = HooksProcessor.getInstance()
    this.logger = Logger.getInstance()
    this.queryCache = QueryCache.getInstance()
    this.cascadeHandler = CascadeHandler.getInstance()
    this.relationManager = new RelationManager(
      this.entityName,
      this.logger,
      () => this.getStore(),
      (value) => this.toRdbValue(value),
      (resultSet) => this.closeResultSet(resultSet)
    )
    this.transactionManager = new TransactionManager(
      this.logger,
      () => this.getStore()
    )
    this.batchOperations = new BatchOperations(
      this.entityName,
      this.entityMetadata.tableName,
      this.dataMapper,
      this.hooksProcessor,
      this.logger,
      this.queryCache,
      () => this.getStore(),
      async (entityData) => await this.save(entityData)
    )
    this.crudOperations = new CrudOperations(
      this.entityName,
      this.entityMetadata,
      this.dataMapper,
      this.hooksProcessor,
      this.logger,
      this.queryCache,
      this.cascadeHandler,
      () => this.getStore(),
      () => this.getUpdatedAtColumnName(),
      (value) => this.toRdbValue(value),
      () => this,
      (name) => new Repository(name)
    )
    this.deleteOperations = new DeleteOperations(
      this.entityName,
      this.entityMetadata,
      this.dataMapper,
      this.hooksProcessor,
      this.logger,
      this.queryCache,
      this.cascadeHandler,
      () => this.getStore(),
      (value) => this.toRdbValue(value),
      () => this,
      (name) => new Repository(name)
    )
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

  /**
   * 保存实体（插入或更新）
   * 根据主键值判断是 INSERT 还是 UPDATE
   * 在数据库操作前执行 beforeSave 钩子
   * @param entityData 实体数据
   * @returns Promise<SaveResult>
   */
  async save(entityData: EntityData): Promise<SaveResult> {
    const result = await this.crudOperations.save(entityData)
    return this.ensureSaveResultSuccess(result, 'SAVE')
  }

  /**
   * 根据主键查询单个实体
   * 如果实体启用了软删除，默认只查询未删除的数据
   * 查询成功后执行 afterLoad 钩子
   * 支持查询缓存（启用缓存时优先从缓存读取）
   * @param id 主键值
   * @param includeDeleted 是否包含已删除的数据，默认 false
   * @param useCache 是否使用缓存，默认 true
   * @returns Promise<EntityData | null>
   */
  async findById(id: ValueType, includeDeleted: boolean = false, useCache: boolean = true): Promise<EntityData | null> {
    const startTime = Date.now()

    // 尝试从缓存获取（仅在不包含已删除数据时使用缓存）
    if (useCache && !includeDeleted && this.queryCache.isEnabled()) {
      const cached = this.queryCache.get(this.entityName, id)
      if (cached !== null) {
        this.logger.logDebug(`缓存命中: ${this.entityName}:${String(id)}`)
        return cached
      }
    }

    try {
      const store = this.getStore()
      const pkColumn = this.entityMetadata.getPrimaryKeyColumn()

      if (pkColumn === null) {
        throw new PrimaryKeyNotDefinedError(this.entityName)
      }

      const predicates = new relationalStore.RdbPredicates(this.entityMetadata.tableName)
      predicates.equalTo(pkColumn.columnName, this.toRdbValue(id))

      // 如果启用软删除且不包含已删除数据，添加过滤条件
      if (this.entityMetadata.isSoftDeleteEnabled() && !includeDeleted) {
        const deletedAtColumn = this.entityMetadata.getDeletedAtColumn()
        predicates.isNull(deletedAtColumn)
      }

      let resultSet: relationalStore.ResultSet | null = null
      try {
        resultSet = await store.query(predicates)

        // 记录查询日志
        const duration = Date.now() - startTime
        this.logger.logQuery(`SELECT * FROM ${this.entityMetadata.tableName} WHERE ${pkColumn.columnName} = ${String(id)}`, duration)

        if (resultSet.goToFirstRow()) {
          const row = ResultSetUtils.toRow(resultSet, this.entityMetadata)
          const entityData = this.dataMapper.fromResultSetRow(row)

          // 执行 afterLoad 钩子
          await this.hooksProcessor.executeAfterLoad(this.entityName, entityData)

          // 缓存查询结果（仅在不包含已删除数据时缓存）
          if (useCache && !includeDeleted && this.queryCache.isEnabled()) {
            this.queryCache.set(this.entityName, id, entityData)
          }

          return entityData
        }

        return null
      } finally {
        this.closeResultSet(resultSet)
      }
    } catch (error) {
      // 如果是钩子执行错误，直接抛出
      if (error instanceof HookExecutionError) {
        throw error
      }
      const errorMessage = error instanceof Error ? error.message : String(error)
      // 记录错误日志
      this.logger.logError(`SELECT 失败: ${errorMessage}`)
      throw new ExecutionError('SELECT', errorMessage)
    }
  }

  /**
   * 查询所有实体
   * 如果实体启用了软删除，默认只查询未删除的数据
   * 查询成功后对每条记录执行 afterLoad 钩子
   * @param includeDeleted 是否包含已删除的数据，默认 false
   * @returns Promise<Array<EntityData>>
   */
  async findAll(includeDeleted: boolean = false): Promise<Array<EntityData>> {
    const startTime = Date.now()
    try {
      const store = this.getStore()
      const predicates = new relationalStore.RdbPredicates(this.entityMetadata.tableName)

      // 如果启用软删除且不包含已删除数据，添加过滤条件
      if (this.entityMetadata.isSoftDeleteEnabled() && !includeDeleted) {
        const deletedAtColumn = this.entityMetadata.getDeletedAtColumn()
        predicates.isNull(deletedAtColumn)
      }

      let resultSet: relationalStore.ResultSet | null = null
      const results: Array<EntityData> = []
      try {
        resultSet = await store.query(predicates)

        // 记录查询日志
        const duration = Date.now() - startTime
        this.logger.logQuery(`SELECT * FROM ${this.entityMetadata.tableName}`, duration)

        while (resultSet.goToNextRow()) {
          const row = this.resultSetToRow(resultSet)
          results.push(this.dataMapper.fromResultSetRow(row))
        }
      } finally {
        this.closeResultSet(resultSet)
      }

      // 批量执行 afterLoad 钩子
      await this.hooksProcessor.executeAfterLoadBatch(this.entityName, results)

      return results
    } catch (error) {
      // 如果是钩子执行错误，直接抛出
      if (error instanceof HookExecutionError) {
        throw error
      }
      const errorMessage = error instanceof Error ? error.message : String(error)
      // 记录错误日志
      this.logger.logError(`SELECT 失败: ${errorMessage}`)
      throw new ExecutionError('SELECT', errorMessage)
    }
  }

  /**
   * 异步查询所有实体（使用 TaskPool 优化大数据量场景）
   * 当数据量超过阈值时，使用 TaskPool 在后台线程执行数据转换
   * 如果实体启用了软删除，默认只查询未删除的数据
   * 查询成功后对每条记录执行 afterLoad 钩子
   * 
   * @param includeDeleted 是否包含已删除的数据，默认 false
   * @returns Promise<Array<EntityData>>
   * Requirements: 1.3
   */
  async findAllAsync(includeDeleted: boolean = false): Promise<Array<EntityData>> {
    const startTime = Date.now()
    try {
      // 创建查询构建器
      const queryBuilder = this.createQueryBuilder()

      // 处理软删除
      if (includeDeleted) {
        queryBuilder.withDeleted()
      }

      // 使用 QueryExecutor 的 getAsync 方法执行异步查询
      const executor = new QueryExecutor(queryBuilder)
      const results = await executor.getAsync()

      // 记录查询日志
      const duration = Date.now() - startTime
      this.logger.logQuery(`SELECT * FROM ${this.entityMetadata.tableName} (异步, 数据量: ${results.length})`, duration)

      // 批量执行 afterLoad 钩子
      if (results.length > 0) {
        await this.hooksProcessor.executeAfterLoadBatch(this.entityName, results)
      }

      return results
    } catch (error) {
      // 如果是钩子执行错误，直接抛出
      if (error instanceof HookExecutionError) {
        throw error
      }
      const errorMessage = error instanceof Error ? error.message : String(error)
      // 记录错误日志
      this.logger.logError(`异步查询失败: ${errorMessage}`)
      throw new ExecutionError('SELECT', errorMessage)
    }
  }

  /**
   * 删除实体
   * 如果实体启用了软删除，则执行软删除（设置 deleted_at 字段）
   * 否则执行物理删除
   * 在数据库操作前执行 beforeDelete 钩子
   * @param entityData 实体数据
   * @returns Promise<DeleteResult>
   */
  async remove(entityData: EntityData): Promise<DeleteResult> {
    const result = await this.deleteOperations.remove(entityData)
    return this.ensureDeleteResultSuccess(result, 'REMOVE')
  }

  /**
   * 根据主键删除实体
   * 如果实体启用了软删除，则执行软删除（设置 deleted_at 字段）
   * 否则执行物理删除
   * @param id 主键值
   * @returns Promise<DeleteResult>
   */
  async removeById(id: ValueType): Promise<DeleteResult> {
    const result = await this.deleteOperations.removeById(id)
    return this.ensureDeleteResultSuccess(result, 'REMOVE_BY_ID')
  }

  /**
   * 强制物理删除（忽略软删除设置）
   * @param entityData 实体数据
   * @returns Promise<DeleteResult>
   */
  async forceRemove(entityData: EntityData): Promise<DeleteResult> {
    const result = await this.deleteOperations.forceRemove(entityData)
    return this.ensureDeleteResultSuccess(result, 'FORCE_REMOVE')
  }

  /**
   * 根据主键强制物理删除（忽略软删除设置）
   * @param id 主键值
   * @returns Promise<DeleteResult>
   */
  async forceRemoveById(id: ValueType): Promise<DeleteResult> {
    const result = await this.deleteOperations.forceRemoveById(id)
    return this.ensureDeleteResultSuccess(result, 'FORCE_REMOVE_BY_ID')
  }

  /**
   * 恢复被软删除的实体
   * 将 deleted_at 字段设置为 null
   * @param id 主键值
   * @returns Promise<SaveResult>
   * @throws SoftDeleteNotEnabledError 如果实体未启用软删除
   */
  async restore(id: ValueType): Promise<SaveResult> {
    const result = await this.deleteOperations.restore(id)
    return this.ensureSaveResultSuccess(result, 'RESTORE')
  }

  /**
   * 统计实体数量
   * 如果实体启用了软删除，默认只统计未删除的数据
   * @param includeDeleted 是否包含已删除的数据，默认 false
   * @returns Promise<number>
   */
  async count(includeDeleted: boolean = false): Promise<number> {
    const startTime = Date.now()
    try {
      const queryBuilder = this.createQueryBuilder()
      if (includeDeleted) {
        queryBuilder.withDeleted()
      }
      const executor = new QueryExecutor(queryBuilder)
      const count = await executor.count()

      // 记录查询日志
      const duration = Date.now() - startTime
      this.logger.logQuery(`SELECT COUNT(*) FROM ${this.entityMetadata.tableName}`, duration)

      return count
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      // 记录错误日志
      this.logger.logError(`COUNT 失败: ${errorMessage}`)
      throw new ExecutionError('COUNT', errorMessage)
    }
  }

  /**
   * 分页查询实体
   * 如果实体启用了软删除，默认只查询未删除的数据
   * 查询成功后对每条记录执行 afterLoad 钩子
   * @param page 页码（从 1 开始）
   * @param pageSize 每页数量
   * @param includeDeleted 是否包含已删除的数据，默认 false
   * @returns Promise<PaginatedResult>
   * Requirements: 2.7
   */
  async findPaginated(page: number, pageSize: number, includeDeleted: boolean = false): Promise<PaginatedResult> {
    const startTime = Date.now()
    try {
      // 创建查询构建器
      const queryBuilder = this.createQueryBuilder()

      // 设置分页参数
      queryBuilder.paginate(page, pageSize)

      // 处理软删除
      if (includeDeleted) {
        queryBuilder.withDeleted()
      }

      // 使用 QueryExecutor 执行分页查询
      const executor = new QueryExecutor(queryBuilder)
      const result = await executor.getPaginated()

      // 记录查询日志
      const duration = Date.now() - startTime
      this.logger.logQuery(`SELECT * FROM ${this.entityMetadata.tableName} (分页: page=${page}, pageSize=${pageSize})`, duration)

      // 批量执行 afterLoad 钩子
      if (result.data.length > 0) {
        await this.hooksProcessor.executeAfterLoadBatch(this.entityName, result.data)
      }

      return result
    } catch (error) {
      // 如果是钩子执行错误，直接抛出
      if (error instanceof HookExecutionError) {
        throw error
      }
      const errorMessage = error instanceof Error ? error.message : String(error)
      // 记录错误日志
      this.logger.logError(`分页查询失败: ${errorMessage}`)
      throw new ExecutionError('SELECT', errorMessage)
    }
  }

  /**
   * 创建查询构建器
   * @returns QueryBuilder 实例
   */
  createQueryBuilder(): QueryBuilder {
    return new QueryBuilder(this.entityName)
  }

  /**
   * 获取实体元数据
   * @returns 实体元数据
   */
  getMetadata(): EntityMetadata {
    return this.entityMetadata
  }

  /**
   * 获取数据映射器
   * @returns 数据映射器
   */
  getDataMapper(): DataMapper {
    return this.dataMapper
  }

  /**
   * 将 ValueType 转换为 RdbPredicates 支持的值类型
   */
  private toRdbValue(value: ValueType): relationalStore.ValueType {
    if (value === null) {
      return null
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
    if (typeof value === 'string' || typeof value === 'number') {
      return value
    }
    return null
  }

  private getUpdatedAtColumnName(): string | null {
    const columnByName = this.entityMetadata.getColumnByName('updated_at')
    if (columnByName !== null) {
      return columnByName.columnName
    }
    const columnByProperty = this.entityMetadata.getColumnByProperty('updatedAt')
    if (columnByProperty !== null) {
      return columnByProperty.columnName
    }
    return null
  }

  /**
   * 将 ResultSet 当前行转换为 ResultSetRow
   */
  private resultSetToRow(resultSet: relationalStore.ResultSet): ResultSetRow {
    const row = new ResultSetRow()
    const columnNames = resultSet.columnNames

    for (let i = 0; i < columnNames.length; i++) {
      const columnName = columnNames[i]
      try {
        const columnIndex = resultSet.getColumnIndex(columnName)

        // 根据列类型获取值
        if (resultSet.isColumnNull(columnIndex)) {
          row.set(columnName, null)
        } else {
          // 尝试获取不同类型的值
          const columnMetadata = this.entityMetadata.getColumnByName(columnName)
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

  private async withStrictTransactionGuard(callback: () => Promise<void>): Promise<void> {
    this.strictTransactionDepth += 1
    try {
      await callback()
    } finally {
      this.strictTransactionDepth -= 1
    }
  }

  private inStrictTransaction(): boolean {
    return this.strictTransactionDepth > 0
  }

  private ensureSaveResultSuccess(result: SaveResult, operation: string): SaveResult {
    if (!this.inStrictTransaction() || result.success) {
      return result
    }
    const message = result.errorMessage.length > 0 ? result.errorMessage : `${operation} 返回失败结果`
    throw new ExecutionError(operation, message)
  }

  private ensureDeleteResultSuccess(result: DeleteResult, operation: string): DeleteResult {
    if (!this.inStrictTransaction() || result.success) {
      return result
    }
    const message = result.errorMessage.length > 0 ? result.errorMessage : `${operation} 返回失败结果`
    throw new ExecutionError(operation, message)
  }

  private ensureBatchInsertResultSuccess(result: BatchInsertResult): BatchInsertResult {
    if (!this.inStrictTransaction() || result.success) {
      return result
    }
    const message = result.errorMessage.length > 0 ? result.errorMessage : 'BATCH_INSERT 返回失败结果'
    throw new ExecutionError('BATCH_INSERT', message)
  }

  private ensureSaveAllResultsSuccess(results: Array<SaveResult>): Array<SaveResult> {
    if (!this.inStrictTransaction()) {
      return results
    }
    for (let i = 0; i < results.length; i++) {
      if (results[i].success) {
        continue
      }
      const base = results[i].errorMessage.length > 0 ? results[i].errorMessage : 'SAVE_ALL 子项失败'
      throw new ExecutionError('SAVE_ALL', `第 ${i} 项失败: ${base}`)
    }
    return results
  }

  /**
   * 在事务中执行操作
   * 如果回调函数执行成功，事务将被提交
   * 如果回调函数抛出异常，事务将被回滚
   * @param callback 事务回调函数
   * @returns Promise<TransactionResult>
   */
  async transaction(callback: TransactionCallback): Promise<TransactionResult> {
    return await this.transactionManager.transaction(async () => {
      await this.withStrictTransactionGuard(async () => {
        await callback(this)
      })
    })
  }

  /**
   * 在事务中执行操作（带选项）
   * 支持事务超时、重试机制
   * @param callback 事务回调函数
   * @param options 事务选项
   * @returns Promise<TransactionResult>
   */
  async transactionWithOptions(
    callback: TransactionCallback,
    options: TransactionOptions
  ): Promise<TransactionResult> {
    return await this.transactionManager.transactionWithOptions(async () => {
      await this.withStrictTransactionGuard(async () => {
        await callback(this)
      })
    }, options)
  }


  /**
   * 批量保存实体
   * @param entities 实体数据数组
   * @returns Promise<Array<SaveResult>>
   */
  async saveAll(entities: Array<EntityData>): Promise<Array<SaveResult>> {
    const results = await this.batchOperations.saveAll(entities)
    return this.ensureSaveAllResultsSuccess(results)
  }

  /**
   * 批量插入实体
   * 使用 RdbStore.batchInsert API 批量插入数据
   * 支持事务和钩子执行选项
   * @param entities 实体数据数组
   * @param options 批量插入选项（可选，默认使用事务和执行钩子）
   * @returns Promise<BatchInsertResult>
   * Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 4.8
   */
  async batchInsert(
    entities: Array<EntityData>,
    options: BatchInsertOptions = BatchInsertOptions.createDefault()
  ): Promise<BatchInsertResult> {
    const result = await this.batchOperations.batchInsert(entities, options)
    return this.ensureBatchInsertResultSuccess(result)
  }

  /**
   * 建立多对多关联
   * 在中间表中插入一条关联记录
   * @param sourceId 源实体主键值
   * @param targetId 目标实体主键值
   * @param relationName 关联属性名
   * @returns Promise<SaveResult>
   * @throws RelationNotFoundError 如果关联关系未注册
   * Requirements: 5.5
   */
  async attach(sourceId: ValueType, targetId: ValueType, relationName: string): Promise<SaveResult> {
    const result = await this.relationManager.attach(sourceId, targetId, relationName)
    return this.ensureSaveResultSuccess(result, 'ATTACH')
  }

  /**
   * 解除多对多关联
   * 从中间表中删除一条关联记录
   * @param sourceId 源实体主键值
   * @param targetId 目标实体主键值
   * @param relationName 关联属性名
   * @returns Promise<DeleteResult>
   * @throws RelationNotFoundError 如果关联关系未注册
   * Requirements: 5.6
   */
  async detach(sourceId: ValueType, targetId: ValueType, relationName: string): Promise<DeleteResult> {
    const result = await this.relationManager.detach(sourceId, targetId, relationName)
    return this.ensureDeleteResultSuccess(result, 'DETACH')
  }

  /**
   * 同步多对多关联（替换所有关联）
   * 删除源实体的所有现有关联，然后建立新的关联
   * @param sourceId 源实体主键值
   * @param targetIds 目标实体主键值数组
   * @param relationName 关联属性名
   * @returns Promise<SaveResult>
   * @throws RelationNotFoundError 如果关联关系未注册
   * Requirements: 5.7
   */
  async sync(sourceId: ValueType, targetIds: Array<ValueType>, relationName: string): Promise<SaveResult> {
    const result = await this.relationManager.sync(sourceId, targetIds, relationName)
    return this.ensureSaveResultSuccess(result, 'SYNC')
  }

  // ==================== 聚合函数 ====================

  /**
   * 计算指定列的总和
   * @param column 列名或属性名
   * @returns Promise<number>
   */
  async sum(column: string): Promise<number> {
    const queryBuilder = this.createQueryBuilder()
    const executor = new QueryExecutor(queryBuilder)
    return await executor.sum(column)
  }

  /**
   * 计算指定列的平均值
   * @param column 列名或属性名
   * @returns Promise<number>
   */
  async avg(column: string): Promise<number> {
    const queryBuilder = this.createQueryBuilder()
    const executor = new QueryExecutor(queryBuilder)
    return await executor.avg(column)
  }

  /**
   * 获取指定列的最大值
   * @param column 列名或属性名
   * @returns Promise<ValueType>
   */
  async max(column: string): Promise<ValueType> {
    const queryBuilder = this.createQueryBuilder()
    const executor = new QueryExecutor(queryBuilder)
    return await executor.max(column)
  }

  /**
   * 获取指定列的最小值
   * @param column 列名或属性名
   * @returns Promise<ValueType>
   */
  async min(column: string): Promise<ValueType> {
    const queryBuilder = this.createQueryBuilder()
    const executor = new QueryExecutor(queryBuilder)
    return await executor.min(column)
  }

  // ==================== 原生 SQL 查询 ====================

  /**
   * 执行原生 SQL 查询（只读）
   * @param sql SQL 查询语句
   * @param args 查询参数
   * @returns Promise<Array<EntityData>>
   */
  async rawQuery(sql: string, args: Array<ValueType> = []): Promise<Array<EntityData>> {
    const startTime = Date.now()
    try {
      const normalizedSql = this.validateRawQuerySql(sql)
      const store = this.getStore()
      const rdbArgs: Array<relationalStore.ValueType> = []
      for (let i = 0; i < args.length; i++) {
        rdbArgs.push(this.toRdbValue(args[i]))
      }

      let resultSet: relationalStore.ResultSet | null = null
      const results: Array<EntityData> = []
      try {
        resultSet = await store.querySql(normalizedSql, rdbArgs)

        const duration = Date.now() - startTime
        this.logger.logQuery(`RAW: ${normalizedSql}`, duration)
        await OrmContext.emitSlowQuery('RAW_QUERY', normalizedSql, duration, this.entityName)

        while (resultSet.goToNextRow()) {
          const row = this.resultSetToRow(resultSet)
          results.push(this.dataMapper.fromResultSetRow(row))
        }
      } finally {
        this.closeResultSet(resultSet)
      }

      return results
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      if (this.isExpectedRawQueryGuardError(errorMessage)) {
        this.logger.logWarn(`[W_RAW_QUERY_READONLY_GUARD] RAW QUERY 拒绝: ${errorMessage}`)
      } else {
        this.logger.logError(`RAW QUERY 失败: ${errorMessage}`)
      }
      throw new ExecutionError('RAW_QUERY', errorMessage)
    }
  }

  /**
   * 执行原生 SQL 语句（写操作）
   * @param sql SQL 语句
   * @param args 参数
   * @returns Promise<number> 受影响的行数（注意：SQLite 不总是返回准确的受影响行数）
   */
  async rawExecute(sql: string, args: Array<ValueType> = []): Promise<void> {
    const startTime = Date.now()
    try {
      const normalizedSql = this.validateRawExecuteSql(sql, args.length)
      const store = this.getStore()
      const rdbArgs: Array<relationalStore.ValueType> = []
      for (let i = 0; i < args.length; i++) {
        rdbArgs.push(this.toRdbValue(args[i]))
      }

      await store.executeSql(normalizedSql, rdbArgs)

      const duration = Date.now() - startTime
      this.logger.logQuery(`RAW EXECUTE: ${normalizedSql}`, duration)
      await OrmContext.emitSlowQuery('RAW_EXECUTE', normalizedSql, duration, this.entityName)

      // 原生 SQL 可能跨实体写入，保守策略：清空缓存
      this.queryCache.clear()
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      if (this.isExpectedRawExecuteGuardError(errorMessage)) {
        this.logger.logWarn(`[W_RAW_EXECUTE_GUARD] RAW EXECUTE 拒绝: ${errorMessage}`)
      } else {
        this.logger.logError(`RAW EXECUTE 失败: ${errorMessage}`)
      }
      throw new ExecutionError('RAW_EXECUTE', errorMessage)
    }
  }

  private isExpectedRawQueryGuardError(errorMessage: string): boolean {
    const normalized = errorMessage.toLowerCase()
    return normalized.includes('raw_query 仅允许') ||
      normalized.includes('raw_query 禁止写操作') ||
      normalized.includes('raw_query 不允许执行多条 sql') ||
      normalized.includes('sql 语句不能为空') ||
      normalized.includes('raw_query only allows') ||
      normalized.includes('raw_query write is not allowed')
  }

  private isExpectedRawExecuteGuardError(errorMessage: string): boolean {
    const normalized = errorMessage.toLowerCase()
    return normalized.includes('raw_execute 仅允许') ||
      normalized.includes('raw_execute 不允许执行多条 sql') ||
      normalized.includes('raw_execute 禁止') ||
      normalized.includes('raw_execute 参数数量') ||
      normalized.includes('sql 语句不能为空') ||
      normalized.includes('raw_execute only allows')
  }

  private countPlaceholder(sql: string): number {
    const matches = sql.match(/\?/g)
    return matches ? matches.length : 0
  }

  private validateRawExecuteSql(sql: string, argsLength: number): string {
    const trimmedSql = sql.trim()
    if (trimmedSql.length === 0) {
      throw new ExecutionError('RAW_EXECUTE', 'SQL 语句不能为空')
    }
    const normalized = trimmedSql.endsWith(';') ? trimmedSql.slice(0, trimmedSql.length - 1).trim() : trimmedSql
    if (normalized.includes(';')) {
      throw new ExecutionError('RAW_EXECUTE', 'RAW_EXECUTE 不允许执行多条 SQL')
    }
    if (normalized.includes('--') || normalized.includes('/*') || normalized.includes('*/')) {
      throw new ExecutionError('RAW_EXECUTE', 'RAW_EXECUTE 禁止 SQL 注释片段')
    }

    const upperSql = normalized.toUpperCase()
    const allowedWrite = upperSql.startsWith('INSERT ') || upperSql.startsWith('UPDATE ') ||
      upperSql.startsWith('DELETE ') || upperSql.startsWith('REPLACE ')
    if (!allowedWrite) {
      throw new ExecutionError('RAW_EXECUTE', 'RAW_EXECUTE 仅允许 INSERT/UPDATE/DELETE/REPLACE')
    }

    const forbiddenKeywords = /\b(DROP|ALTER|CREATE|TRUNCATE|ATTACH|DETACH|VACUUM|REINDEX|PRAGMA)\b/
    if (forbiddenKeywords.test(upperSql)) {
      throw new ExecutionError('RAW_EXECUTE', 'RAW_EXECUTE 禁止危险 SQL 关键字')
    }

    const placeholderCount = this.countPlaceholder(normalized)
    if (placeholderCount <= 0) {
      throw new ExecutionError('RAW_EXECUTE', 'RAW_EXECUTE 仅允许参数化 SQL（必须使用 ? 占位符）')
    }
    if (placeholderCount !== argsLength) {
      throw new ExecutionError('RAW_EXECUTE', 'RAW_EXECUTE 参数数量与占位符数量不一致')
    }
    return normalized
  }

  private validateRawQuerySql(sql: string): string {
    const trimmedSql = sql.trim()
    if (trimmedSql.length === 0) {
      throw new ExecutionError('RAW_QUERY', 'SQL 语句不能为空')
    }
    const normalized = trimmedSql.endsWith(';') ? trimmedSql.slice(0, trimmedSql.length - 1).trim() : trimmedSql
    if (normalized.includes(';')) {
      throw new ExecutionError('RAW_QUERY', 'RAW_QUERY 不允许执行多条 SQL')
    }
    const upperSql = normalized.toUpperCase()
    if (!upperSql.startsWith('SELECT ') && !upperSql.startsWith('WITH ') &&
      !upperSql.startsWith('EXPLAIN ')) {
      throw new ExecutionError('RAW_QUERY', 'RAW_QUERY 仅允许 SELECT/WITH/EXPLAIN 只读 SQL')
    }
    const hasWriteKeyword = /\b(INSERT|UPDATE|DELETE|REPLACE|DROP|ALTER|CREATE|TRUNCATE|ATTACH|DETACH|VACUUM|REINDEX)\b/.test(upperSql)
    if (hasWriteKeyword) {
      throw new ExecutionError('RAW_QUERY', 'RAW_QUERY 禁止写操作 SQL')
    }
    return normalized
  }
}

/**
 * 事务回调函数类型
 */
export type TransactionCallback = (repo: Repository) => Promise<void>
