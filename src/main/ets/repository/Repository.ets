/**
 * 仓库类
 * 提供实体的 CRUD 操作接口
 */

import { relationalStore } from '@kit.ArkData'
import { EntityMetadata } from '../core/EntityMetadata'
import { MetadataStorage } from '../core/MetadataStorage'
import { ManyToManyMetadata } from '../core/ManyToManyMetadata'
import { HooksProcessor } from '../core/HooksProcessor'
import { DataMapper, EntityData, ResultSetRow } from '../mapping/DataMapper'
import { QueryBuilder } from '../query/QueryBuilder'
import { QueryExecutor } from '../query/QueryExecutor'
import { PaginatedResult } from '../query/PaginatedResult'
import { DatabaseManager } from '../database/DatabaseManager'
import { Logger } from '../logging/Logger'
import { ValueType } from '../types/ValueTypes'
import { ColumnType } from '../types/ColumnType'
import { EntityNotRegisteredError, PrimaryKeyNotDefinedError } from '../errors/MetadataError'
import { ExecutionError } from '../errors/DatabaseError'
import { TransactionRollbackError } from '../errors/TransactionError'
import { SoftDeleteNotEnabledError } from '../errors/SoftDeleteError'
import { HookExecutionError } from '../errors/HookError'
import { RelationNotFoundError } from '../errors/RelationError'
import { BatchInsertResult } from './BatchInsertResult'
import { BatchInsertOptions } from './BatchInsertOptions'
import { RelationType } from '../types/RelationType'
import { TransactionOptions, IsolationLevel } from './TransactionOptions'
import { QueryCache } from '../query/QueryCache'
import { ResultSetUtils } from '../mapping/ResultSetUtils'
import { CascadeHandler, CascadeOperation } from './CascadeHandler'
import { EntityValidator } from '../validation/EntityValidator'
import { ValidationError } from '../errors/ValidationError'

class TimeoutState {
  timedOut: boolean = false
  commitStarted: boolean = false
  finished: boolean = false
}

/**
 * 保存结果类
 */
export class SaveResult {
  /** 是否成功 */
  success: boolean = false
  /** 受影响的行数 */
  affectedRows: number = 0
  /** 插入的行 ID（仅 INSERT 操作） */
  insertId: number = 0
  /** 错误信息 */
  errorMessage: string = ''

  static createSuccess(affectedRows: number, insertId: number = 0): SaveResult {
    const result = new SaveResult()
    result.success = true
    result.affectedRows = affectedRows
    result.insertId = insertId
    return result
  }

  static createFailure(errorMessage: string): SaveResult {
    const result = new SaveResult()
    result.success = false
    result.errorMessage = errorMessage
    return result
  }
}

/**
 * 删除结果类
 */
export class DeleteResult {
  /** 是否成功 */
  success: boolean = false
  /** 受影响的行数 */
  affectedRows: number = 0
  /** 错误信息 */
  errorMessage: string = ''

  static createSuccess(affectedRows: number): DeleteResult {
    const result = new DeleteResult()
    result.success = true
    result.affectedRows = affectedRows
    return result
  }

  static createFailure(errorMessage: string): DeleteResult {
    const result = new DeleteResult()
    result.success = false
    result.errorMessage = errorMessage
    return result
  }
}

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
   * 保存实体（插入或更新）
   * 根据主键值判断是 INSERT 还是 UPDATE
   * 在数据库操作前执行 beforeSave 钩子
   * @param entityData 实体数据
   * @returns Promise<SaveResult>
   */
  async save(entityData: EntityData): Promise<SaveResult> {
    try {
      // 执行数据验证
      EntityValidator.validateOrThrow(this.entityName, entityData)

      // 执行 beforeSave 钩子
      await this.hooksProcessor.executeBeforeSave(this.entityName, entityData)

      const isNew = this.dataMapper.isNewRecord(entityData)
      const operation: CascadeOperation = isNew ? 'insert' : 'update'

      // 处理级联保存（先保存依赖实体）
      await this.cascadeHandler.handleBeforeSave(
        this.entityName,
        entityData,
        operation,
        (name) => new Repository(name)
      )

      let result: SaveResult
      if (isNew) {
        // INSERT 操作
        result = await this.insert(entityData)
      } else {
        // UPDATE 操作
        result = await this.update(entityData)
      }

      // 处理级联保存（保存子实体/同步中间表）
      await this.cascadeHandler.handleAfterSave(
        this.entityName,
        entityData,
        operation,
        this,
        (name) => new Repository(name)
      )

      return result
    } catch (error) {
      // 如果是钩子执行错误，直接抛出
      if (error instanceof HookExecutionError) {
        throw error
      }
      if (error instanceof ValidationError) {
        throw error
      }
      const errorMessage = error instanceof Error ? error.message : String(error)
      return SaveResult.createFailure(errorMessage)
    }
  }

  /**
   * 插入新实体
   * @param entityData 实体数据
   * @returns Promise<SaveResult>
   */
  private async insert(entityData: EntityData): Promise<SaveResult> {
    const startTime = Date.now()
    try {
      const store = this.getStore()
      const pkColumn = this.entityMetadata.getPrimaryKeyColumn()
      if (pkColumn === null) {
        throw new PrimaryKeyNotDefinedError(this.entityName)
      }
      const valuesBucket = this.dataMapper.toValuesBucket(entityData, false)

      // 转换为 relationalStore.ValuesBucket
      const rdbValuesBucket: relationalStore.ValuesBucket = {}
      const keys = valuesBucket.keys()
      for (let i = 0; i < keys.length; i++) {
        const key = keys[i]
        if (key === pkColumn.columnName && pkColumn.isAutoIncrement) {
          continue
        }
        const value = valuesBucket.get(key)
        rdbValuesBucket[key] = value
      }

      const updatedAtColumn = this.getUpdatedAtColumnName()
      if (updatedAtColumn !== null) {
        rdbValuesBucket[updatedAtColumn] = Date.now()
      }

      // 确保软删除列被显式设置为 null（新记录未删除）
      if (this.entityMetadata.isSoftDeleteEnabled()) {
        const deletedAtColumn = this.entityMetadata.getDeletedAtColumn()
        if (rdbValuesBucket[deletedAtColumn] === undefined) {
          rdbValuesBucket[deletedAtColumn] = null
        }
      }

      // 使用同步方法 insertSync，以确保事务回滚能正常工作
      // HarmonyOS 的事务控制与同步操作兼容
      const rowId = store.insertSync(this.entityMetadata.tableName, rdbValuesBucket)

      // 记录查询日志
      const duration = Date.now() - startTime
      this.logger.logQuery(`INSERT INTO ${this.entityMetadata.tableName}`, duration)

      // 如果有自增主键，更新实体数据中的主键值
      if (pkColumn.isAutoIncrement) {
        this.dataMapper.setPrimaryKeyValue(entityData, rowId)
      }

      // 使缓存失效
      this.queryCache.invalidateEntity(this.entityName)

      return SaveResult.createSuccess(1, rowId)
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      // 记录错误日志
      this.logger.logError(`INSERT 失败: ${errorMessage}`)
      throw new ExecutionError('INSERT', errorMessage)
    }
  }

  /**
   * 更新已有实体
   * @param entityData 实体数据
   * @returns Promise<SaveResult>
   */
  private async update(entityData: EntityData): Promise<SaveResult> {
    const startTime = Date.now()
    try {
      const store = this.getStore()
      const pkColumn = this.entityMetadata.getPrimaryKeyColumn()

      if (pkColumn === null) {
        throw new PrimaryKeyNotDefinedError(this.entityName)
      }

      const pkValue = this.dataMapper.getPrimaryKeyValue(entityData)
      if (pkValue === null) {
        throw new ExecutionError('UPDATE', '主键值不能为空')
      }

      // 构建更新条件
      const predicates = new relationalStore.RdbPredicates(this.entityMetadata.tableName)
      predicates.equalTo(pkColumn.columnName, this.toRdbValue(pkValue))

      // 转换为 relationalStore.ValuesBucket
      const valuesBucket = this.dataMapper.toValuesBucket(entityData, false)
      const rdbValuesBucket: relationalStore.ValuesBucket = {}
      const keys = valuesBucket.keys()
      for (let i = 0; i < keys.length; i++) {
        const key = keys[i]
        if (key === pkColumn.columnName) {
          continue
        }
        const value = valuesBucket.get(key)
        rdbValuesBucket[key] = value
      }

      const updatedAtColumn = this.getUpdatedAtColumnName()
      if (updatedAtColumn !== null) {
        rdbValuesBucket[updatedAtColumn] = Date.now()
      }

      // 使用同步方法 executeSync 执行 UPDATE，以确保事务回滚能正常工作
      // 构建 UPDATE SQL
      const setClauses: string[] = []
      const values: relationalStore.ValueType[] = []
      const bucketKeys = Object.keys(rdbValuesBucket)
      for (let i = 0; i < bucketKeys.length; i++) {
        const key = bucketKeys[i]
        setClauses.push(`${key} = ?`)
        values.push(rdbValuesBucket[key])
      }
      values.push(this.toRdbValue(pkValue))

      const updateSql = `UPDATE ${this.entityMetadata.tableName} SET ${setClauses.join(', ')} WHERE ${pkColumn.columnName} = ?`
      store.executeSync(updateSql, values)

      // 记录查询日志
      const duration = Date.now() - startTime
      this.logger.logQuery(`UPDATE ${this.entityMetadata.tableName} WHERE ${pkColumn.columnName} = ${String(pkValue)}`, duration)

      // 使缓存失效
      this.queryCache.invalidate(this.entityName, pkValue)

      return SaveResult.createSuccess(1)
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      // 记录错误日志
      this.logger.logError(`UPDATE 失败: ${errorMessage}`)
      throw new ExecutionError('UPDATE', errorMessage)
    }
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

      const resultSet = await store.query(predicates)

      // 记录查询日志
      const duration = Date.now() - startTime
      this.logger.logQuery(`SELECT * FROM ${this.entityMetadata.tableName} WHERE ${pkColumn.columnName} = ${String(id)}`, duration)

      if (resultSet.goToFirstRow()) {
        const row = ResultSetUtils.toRow(resultSet, this.entityMetadata)
        resultSet.close()
        const entityData = this.dataMapper.fromResultSetRow(row)

        // 执行 afterLoad 钩子
        await this.hooksProcessor.executeAfterLoad(this.entityName, entityData)

        // 缓存查询结果（仅在不包含已删除数据时缓存）
        if (useCache && !includeDeleted && this.queryCache.isEnabled()) {
          this.queryCache.set(this.entityName, id, entityData)
        }

        return entityData
      }

      resultSet.close()
      return null
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

      const resultSet = await store.query(predicates)

      // 记录查询日志
      const duration = Date.now() - startTime
      this.logger.logQuery(`SELECT * FROM ${this.entityMetadata.tableName}`, duration)

      const results: Array<EntityData> = []

      while (resultSet.goToNextRow()) {
        const row = this.resultSetToRow(resultSet)
        results.push(this.dataMapper.fromResultSetRow(row))
      }

      resultSet.close()

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
    try {
      const pkValue = this.dataMapper.getPrimaryKeyValue(entityData)
      if (pkValue === null) {
        return DeleteResult.createFailure('实体没有主键值')
      }

      // 执行 beforeDelete 钩子
      await this.hooksProcessor.executeBeforeDelete(this.entityName, entityData)

      // 处理级联删除
      await this.cascadeHandler.handleBeforeRemove(
        this.entityName,
        entityData,
        this,
        (name) => new Repository(name)
      )

      return await this.removeById(pkValue)
    } catch (error) {
      // 如果是钩子执行错误，直接抛出
      if (error instanceof HookExecutionError) {
        throw error
      }
      const errorMessage = error instanceof Error ? error.message : String(error)
      return DeleteResult.createFailure(errorMessage)
    }
  }

  /**
   * 根据主键删除实体
   * 如果实体启用了软删除，则执行软删除（设置 deleted_at 字段）
   * 否则执行物理删除
   * @param id 主键值
   * @returns Promise<DeleteResult>
   */
  async removeById(id: ValueType): Promise<DeleteResult> {
    try {
      // 检查是否启用软删除
      if (this.entityMetadata.isSoftDeleteEnabled()) {
        return await this.softDelete(id)
      }

      // 执行物理删除
      return await this.hardDelete(id)
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      return DeleteResult.createFailure(errorMessage)
    }
  }

  /**
   * 执行软删除
   * 将 deleted_at 字段设置为当前时间戳
   * @param id 主键值
   * @returns Promise<DeleteResult>
   */
  private async softDelete(id: ValueType): Promise<DeleteResult> {
    const startTime = Date.now()
    try {
      const store = this.getStore()
      const pkColumn = this.entityMetadata.getPrimaryKeyColumn()

      if (pkColumn === null) {
        throw new PrimaryKeyNotDefinedError(this.entityName)
      }

      // 构建更新条件
      const predicates = new relationalStore.RdbPredicates(this.entityMetadata.tableName)
      predicates.equalTo(pkColumn.columnName, this.toRdbValue(id))

      // 设置 deleted_at 为当前时间戳
      const deletedAtColumn = this.entityMetadata.getDeletedAtColumn()
      const currentTimestamp = Date.now()
      const rdbValuesBucket: relationalStore.ValuesBucket = {}
      rdbValuesBucket[deletedAtColumn] = currentTimestamp

      // 使用同步方法 executeSync 执行软删除，以确保事务回滚能正常工作
      const updateSql = `UPDATE ${this.entityMetadata.tableName} SET ${deletedAtColumn} = ? WHERE ${pkColumn.columnName} = ?`
      store.executeSync(updateSql, [currentTimestamp, this.toRdbValue(id)])

      // 记录查询日志
      const duration = Date.now() - startTime
      this.logger.logQuery(`UPDATE ${this.entityMetadata.tableName} SET ${deletedAtColumn} = ${currentTimestamp} WHERE ${pkColumn.columnName} = ${String(id)}`, duration)

      // 使缓存失效
      this.queryCache.invalidate(this.entityName, id)

      return DeleteResult.createSuccess(1)
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      // 记录错误日志
      this.logger.logError(`SOFT_DELETE 失败: ${errorMessage}`)
      throw new ExecutionError('SOFT_DELETE', errorMessage)
    }
  }

  /**
   * 执行物理删除
   * @param id 主键值
   * @returns Promise<DeleteResult>
   */
  private async hardDelete(id: ValueType): Promise<DeleteResult> {
    const startTime = Date.now()
    try {
      const store = this.getStore()
      const pkColumn = this.entityMetadata.getPrimaryKeyColumn()

      if (pkColumn === null) {
        throw new PrimaryKeyNotDefinedError(this.entityName)
      }

      // 使用同步方法 executeSync 执行删除，以确保事务回滚能正常工作
      const deleteSql = `DELETE FROM ${this.entityMetadata.tableName} WHERE ${pkColumn.columnName} = ?`
      store.executeSync(deleteSql, [this.toRdbValue(id)])

      // 记录查询日志
      const duration = Date.now() - startTime
      this.logger.logQuery(`DELETE FROM ${this.entityMetadata.tableName} WHERE ${pkColumn.columnName} = ${String(id)}`, duration)

      // 使缓存失效
      this.queryCache.invalidate(this.entityName, id)

      return DeleteResult.createSuccess(1)
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      // 记录错误日志
      this.logger.logError(`DELETE 失败: ${errorMessage}`)
      throw new ExecutionError('DELETE', errorMessage)
    }
  }

  /**
   * 强制物理删除（忽略软删除设置）
   * @param entityData 实体数据
   * @returns Promise<DeleteResult>
   */
  async forceRemove(entityData: EntityData): Promise<DeleteResult> {
    try {
      const pkValue = this.dataMapper.getPrimaryKeyValue(entityData)
      if (pkValue === null) {
        return DeleteResult.createFailure('实体没有主键值')
      }
      return await this.forceRemoveById(pkValue)
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      return DeleteResult.createFailure(errorMessage)
    }
  }

  /**
   * 根据主键强制物理删除（忽略软删除设置）
   * @param id 主键值
   * @returns Promise<DeleteResult>
   */
  async forceRemoveById(id: ValueType): Promise<DeleteResult> {
    try {
      return await this.hardDelete(id)
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      return DeleteResult.createFailure(errorMessage)
    }
  }

  /**
   * 恢复被软删除的实体
   * 将 deleted_at 字段设置为 null
   * @param id 主键值
   * @returns Promise<SaveResult>
   * @throws SoftDeleteNotEnabledError 如果实体未启用软删除
   */
  async restore(id: ValueType): Promise<SaveResult> {
    const startTime = Date.now()
    try {
      // 检查是否启用软删除
      if (!this.entityMetadata.isSoftDeleteEnabled()) {
        throw new SoftDeleteNotEnabledError(this.entityName)
      }

      const store = this.getStore()
      const pkColumn = this.entityMetadata.getPrimaryKeyColumn()

      if (pkColumn === null) {
        throw new PrimaryKeyNotDefinedError(this.entityName)
      }

      // 构建更新条件
      const predicates = new relationalStore.RdbPredicates(this.entityMetadata.tableName)
      predicates.equalTo(pkColumn.columnName, this.toRdbValue(id))

      // 使用同步方法 executeSync 执行恢复，以确保事务回滚能正常工作
      const deletedAtColumn = this.entityMetadata.getDeletedAtColumn()
      const updateSql = `UPDATE ${this.entityMetadata.tableName} SET ${deletedAtColumn} = NULL WHERE ${pkColumn.columnName} = ?`
      store.executeSync(updateSql, [this.toRdbValue(id)])

      // 记录查询日志
      const duration = Date.now() - startTime
      this.logger.logQuery(`UPDATE ${this.entityMetadata.tableName} SET ${deletedAtColumn} = NULL WHERE ${pkColumn.columnName} = ${String(id)}`, duration)

      return SaveResult.createSuccess(1)
    } catch (error) {
      if (error instanceof SoftDeleteNotEnabledError) {
        throw error
      }
      const errorMessage = error instanceof Error ? error.message : String(error)
      // 记录错误日志
      this.logger.logError(`RESTORE 失败: ${errorMessage}`)
      return SaveResult.createFailure(errorMessage)
    }
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

  /**
   * 在事务中执行操作
   * 如果回调函数执行成功，事务将被提交
   * 如果回调函数抛出异常，事务将被回滚
   * @param callback 事务回调函数
   * @returns Promise<TransactionResult>
   */
  async transaction(callback: TransactionCallback): Promise<TransactionResult> {
    let store: relationalStore.RdbStore
    let committed = false

    try {
      store = this.getStore()
    } catch (e) {
      const errorMessage = e instanceof Error ? e.message : String(e)
      this.logger.logError(`获取数据库连接失败: ${errorMessage}`)
      throw new TransactionRollbackError(`获取数据库连接失败: ${errorMessage}`)
    }

    try {
      // 开始事务
      store.beginTransaction()
      // 记录事务开始日志
      this.logger.logTransaction('BEGIN')

      // 执行回调
      try {
        await callback(this)
      } catch (callbackError) {
        if (callbackError instanceof Error) {
          throw callbackError
        }
        throw new Error(String(callbackError))
      }

      // 提交事务
      store.commit()
      committed = true
      // 记录事务提交日志
      this.logger.logTransaction('COMMIT')

      return TransactionResult.createSuccess()
    } catch (error) {
      // 如果事务未提交，尝试回滚
      if (!committed) {
        try {
          store.rollBack()
          // 记录事务回滚日志
          this.logger.logTransaction('ROLLBACK')
        } catch (rollbackError) {
          // 回滚失败，记录错误但不覆盖原始错误
          const rollbackMsg = rollbackError instanceof Error ? rollbackError.message : String(rollbackError)
          const originalMsg = error instanceof Error ? error.message : String(error)
          this.logger.logError(`事务回滚失败: ${rollbackMsg}`)
          throw new TransactionRollbackError(`原始错误: ${originalMsg}, 回滚错误: ${rollbackMsg}`)
        }
      }

      const errorMessage = error instanceof Error ? error.message : String(error)
      this.logger.logError(`事务执行失败: ${errorMessage}`)
      throw new TransactionRollbackError(errorMessage)
    }
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
    let lastError: Error | null = null
    let attempts = 0
    const maxAttempts = options.retries + 1

    while (attempts < maxAttempts) {
      attempts++
      let timeoutId: number = 0
      let isTimedOut = false
      const timeoutState = new TimeoutState()

      try {
        const result = await new Promise<TransactionResult>(
          (resolve: (value: TransactionResult) => void, reject: (reason: Error) => void) => {
            // 设置超时定时器
            timeoutId = setTimeout(() => {
              if (timeoutState.finished || timeoutState.commitStarted) {
                return
              }
              isTimedOut = true
              timeoutState.timedOut = true
              reject(new Error(`事务超时 (${options.timeout}ms)`))
            }, options.timeout)

            // 执行事务（应用隔离级别与只读选项）
            this.executeTransactionWithOptions(callback, options, timeoutState)
              .then((res) => {
                if (!isTimedOut) {
                  clearTimeout(timeoutId)
                  resolve(res)
                }
              })
              .catch((err: Error) => {
                if (!isTimedOut) {
                  clearTimeout(timeoutId)
                  reject(err)
                }
              })
          }
        )
        return result
      } catch (error) {
        // 确保定时器清理
        if (timeoutId !== 0) {
          clearTimeout(timeoutId)
        }
        lastError = error instanceof Error ? error : new Error(String(error))

        // 如果还有重试机会，等待后重试
        if (attempts < maxAttempts) {
          this.logger.logInfo(`事务执行失败，${options.retryDelay}ms 后重试 (${attempts}/${maxAttempts})`)
          await this.delay(options.retryDelay)
        }
      }
    }

    // 所有重试都失败
    const errorMessage = lastError ? lastError.message : '事务执行失败'
    this.logger.logError(`事务执行失败，已重试 ${options.retries} 次: ${errorMessage}`)
    throw new TransactionRollbackError(errorMessage)
  }

  /**
   * 执行带选项的事务
   * @param callback 事务回调函数
   * @param options 事务选项
   */
  private async executeTransactionWithOptions(
    callback: TransactionCallback,
    options: TransactionOptions,
    timeoutState?: TimeoutState
  ): Promise<TransactionResult> {
    let store: relationalStore.RdbStore
    let committed = false
    let isolationApplied = false
    let readOnlyApplied = false

    try {
      store = this.getStore()
    } catch (e) {
      const errorMessage = e instanceof Error ? e.message : String(e)
      this.logger.logError(`获取数据库连接失败: ${errorMessage}`)
      throw new TransactionRollbackError(`获取数据库连接失败: ${errorMessage}`)
    }

    try {
      // 应用隔离级别（SQLite 通过 PRAGMA read_uncommitted 支持 READ_UNCOMMITTED）
      await this.applyIsolationLevel(store, options.isolation)
      isolationApplied = true

      // 应用只读模式（阻止写操作）
      if (options.readOnly) {
        await this.setReadOnlyMode(store, true)
        readOnlyApplied = true
      }

      // 开始事务
      store.beginTransaction()
      const beginLabel = options.readOnly ? 'BEGIN (READ ONLY)' : 'BEGIN'
      this.logger.logTransaction(beginLabel)

      if (timeoutState?.timedOut) {
        throw new TransactionRollbackError(`事务超时 (${options.timeout}ms)`)
      }

      // 执行回调
      try {
        await callback(this)
      } catch (callbackError) {
        if (callbackError instanceof Error) {
          throw callbackError
        }
        throw new Error(String(callbackError))
      }

      if (timeoutState?.timedOut) {
        throw new TransactionRollbackError(`事务超时 (${options.timeout}ms)`)
      }

      // 提交事务
      if (timeoutState) {
        timeoutState.commitStarted = true
      }
      store.commit()
      committed = true
      this.logger.logTransaction('COMMIT')

      return TransactionResult.createSuccess()
    } catch (error) {
      // 如果事务未提交，尝试回滚
      if (!committed) {
        try {
          store.rollBack()
          this.logger.logTransaction('ROLLBACK')
        } catch (rollbackError) {
          const rollbackMsg = rollbackError instanceof Error ? rollbackError.message : String(rollbackError)
          const originalMsg = error instanceof Error ? error.message : String(error)
          this.logger.logError(`事务回滚失败: ${rollbackMsg}`)
          throw new TransactionRollbackError(`原始错误: ${originalMsg}, 回滚错误: ${rollbackMsg}`)
        }
      }

      const errorMessage = error instanceof Error ? error.message : String(error)
      this.logger.logError(`事务执行失败: ${errorMessage}`)
      throw new TransactionRollbackError(errorMessage)
    } finally {
      if (timeoutState) {
        timeoutState.finished = true
      }
      // 恢复事务选项
      await this.resetTransactionOptions(store, isolationApplied, readOnlyApplied)
    }
  }

  /**
   * 应用事务隔离级别
   * @param store RdbStore 实例
   * @param isolation 隔离级别
   */
  private async applyIsolationLevel(store: relationalStore.RdbStore, isolation: IsolationLevel): Promise<void> {
    try {
      if (isolation === IsolationLevel.READ_UNCOMMITTED) {
        await store.executeSql('PRAGMA read_uncommitted = 1')
        return
      }
      // SQLite 对其他隔离级别等价于 READ_COMMITTED
      await store.executeSql('PRAGMA read_uncommitted = 0')
    } catch (e) {
      const errorMessage = e instanceof Error ? e.message : String(e)
      throw new TransactionRollbackError(`设置事务隔离级别失败: ${errorMessage}`)
    }
  }

  /**
   * 设置只读模式
   * @param store RdbStore 实例
   * @param readOnly 是否只读
   */
  private async setReadOnlyMode(store: relationalStore.RdbStore, readOnly: boolean): Promise<void> {
    const value = readOnly ? 1 : 0
    try {
      await store.executeSql(`PRAGMA query_only = ${value}`)
    } catch (e) {
      const errorMessage = e instanceof Error ? e.message : String(e)
      throw new TransactionRollbackError(`设置只读模式失败: ${errorMessage}`)
    }
  }

  /**
   * 恢复事务选项（隔离级别/只读）
   * @param store RdbStore 实例
   * @param isolationApplied 是否应用了隔离级别
   * @param readOnlyApplied 是否应用了只读模式
   */
  private async resetTransactionOptions(
    store: relationalStore.RdbStore,
    isolationApplied: boolean,
    readOnlyApplied: boolean
  ): Promise<void> {
    if (readOnlyApplied) {
      try {
        await this.setReadOnlyMode(store, false)
      } catch (e) {
        const errorMessage = e instanceof Error ? e.message : String(e)
        this.logger.logError(`恢复只读模式失败: ${errorMessage}`)
      }
    }

    if (isolationApplied) {
      try {
        await this.applyIsolationLevel(store, IsolationLevel.READ_COMMITTED)
      } catch (e) {
        const errorMessage = e instanceof Error ? e.message : String(e)
        this.logger.logError(`恢复事务隔离级别失败: ${errorMessage}`)
      }
    }
  }

  /**
   * 延迟函数
   * @param ms 延迟毫秒数
   */
  private delay(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve()
      }, ms)
    })
  }

  /**
   * 批量保存实体
   * @param entities 实体数据数组
   * @returns Promise<Array<SaveResult>>
   */
  async saveAll(entities: Array<EntityData>): Promise<Array<SaveResult>> {
    const results: Array<SaveResult> = []
    for (let i = 0; i < entities.length; i++) {
      const result = await this.save(entities[i])
      results.push(result)
    }
    return results
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
    const startTime = Date.now()
    const totalCount = entities.length

    // 空数组直接返回成功
    if (totalCount === 0) {
      return BatchInsertResult.createSuccess(0, 0)
    }

    let store: relationalStore.RdbStore
    try {
      store = this.getStore()
    } catch (e) {
      const errorMessage = e instanceof Error ? e.message : String(e)
      this.logger.logError(`批量插入获取数据库连接失败: ${errorMessage}`)
      return BatchInsertResult.createFailure(`获取数据库连接失败: ${errorMessage}`)
    }

    // 执行 beforeSave 钩子（如果启用）
    // Requirements: 4.5, 4.6
    if (options.executeValidation) {
      for (let i = 0; i < entities.length; i++) {
        try {
          EntityValidator.validateOrThrow(this.entityName, entities[i])
        } catch (error) {
          if (error instanceof ValidationError) {
            const errorMessage = error.message
            this.logger.logError(`批量插入验证失败 (索引 ${i}): ${errorMessage}`)
            return BatchInsertResult.createFailure(`验证失败 (索引 ${i}): ${errorMessage}`, [i])
          }
          const errorMessage = error instanceof Error ? error.message : String(error)
          this.logger.logError(`批量插入验证失败 (索引 ${i}): ${errorMessage}`)
          return BatchInsertResult.createFailure(`验证失败 (索引 ${i}): ${errorMessage}`, [i])
        }
      }
    }

    if (options.executeHooks) {
      for (let i = 0; i < entities.length; i++) {
        try {
          await this.hooksProcessor.executeBeforeSave(this.entityName, entities[i])
        } catch (error) {
          const errorMessage = error instanceof Error ? error.message : String(error)
          this.logger.logError(`批量插入钩子执行失败 (索引 ${i}): ${errorMessage}`)
          // 如果任一 beforeSave 钩子失败，中止并返回错误
          return BatchInsertResult.createFailure(`beforeSave 钩子执行失败 (索引 ${i}): ${errorMessage}`, [i])
        }
      }
    }

    // 将所有 EntityData 转换为 ValuesBucket 数组
    // Requirements: 4.2
    const valueBuckets: Array<relationalStore.ValuesBucket> = []
    for (let i = 0; i < entities.length; i++) {
      try {
        const valuesBucket = this.dataMapper.toValuesBucket(entities[i], false)
        // 转换为 relationalStore.ValuesBucket
        const rdbValuesBucket: relationalStore.ValuesBucket = {}
        const keys = valuesBucket.keys()
        for (let j = 0; j < keys.length; j++) {
          const key = keys[j]
          const value = valuesBucket.get(key)
          rdbValuesBucket[key] = value
        }
        valueBuckets.push(rdbValuesBucket)
      } catch (error) {
        const errorMessage = error instanceof Error ? error.message : String(error)
        this.logger.logError(`批量插入数据转换失败 (索引 ${i}): ${errorMessage}`)
        return BatchInsertResult.createFailure(`数据转换失败 (索引 ${i}): ${errorMessage}`, [i])
      }
    }

    // 执行批量插入
    // Requirements: 4.1, 4.7, 4.8
    try {
      let insertedCount: number = 0

      if (options.useTransaction) {
        // 在事务中执行批量插入
        // Requirements: 4.7, 4.8
        store.beginTransaction()
        this.logger.logTransaction('BEGIN (batchInsert)')

        try {
          insertedCount = await store.batchInsert(this.entityMetadata.tableName, valueBuckets)
          store.commit()
          this.logger.logTransaction('COMMIT (batchInsert)')
        } catch (insertError) {
          // 失败时回滚
          store.rollBack()
          this.logger.logTransaction('ROLLBACK (batchInsert)')
          // ArkTS 要求 throw 必须抛出 Error 类型
          if (insertError instanceof Error) {
            throw insertError
          }
          throw new Error(`批量插入失败: ${String(insertError)}`)
        }
      } else {
        // 不使用事务，直接执行批量插入
        insertedCount = await store.batchInsert(this.entityMetadata.tableName, valueBuckets)
      }

      // 记录批量插入日志
      const duration = Date.now() - startTime
      this.logger.logQuery(`BATCH INSERT INTO ${this.entityMetadata.tableName} (${insertedCount}/${totalCount} 条)`, duration)

      if (insertedCount > 0) {
        this.queryCache.invalidateEntity(this.entityName)
      }

      // 检查是否全部成功
      if (insertedCount === totalCount) {
        return BatchInsertResult.createSuccess(insertedCount, totalCount)
      } else {
        // 部分成功
        // Requirements: 4.4
        const failedCount = totalCount - insertedCount
        // 注意：RdbStore.batchInsert 不返回具体失败的索引，只返回成功数量
        // 这里无法确定具体哪些失败了，所以 failedIndexes 为空
        return BatchInsertResult.createPartialSuccess(
          insertedCount,
          totalCount,
          [],
          `部分插入失败: ${failedCount} 条记录未能插入`
        )
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      this.logger.logError(`批量插入执行失败: ${errorMessage}`)
      return BatchInsertResult.createFailure(`批量插入执行失败: ${errorMessage}`)
    }
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
  async attach(sourceId: number, targetId: number, relationName: string): Promise<SaveResult> {
    const startTime = Date.now()
    try {
      // 获取多对多关联元数据
      const relation = MetadataStorage.getInstance().getManyToManyRelation(this.entityName, relationName)
      if (relation === null) {
        throw new RelationNotFoundError(this.entityName, relationName)
      }

      const store = this.getStore()

      // 检查关联是否已存在
      const checkPredicates = new relationalStore.RdbPredicates(relation.joinTable)
      checkPredicates.equalTo(relation.joinSourceKey, sourceId)
      checkPredicates.and()
      checkPredicates.equalTo(relation.joinTargetKey, targetId)

      const checkResult = await store.query(checkPredicates)
      const exists = checkResult.rowCount > 0
      checkResult.close()

      if (exists) {
        // 关联已存在，直接返回成功
        return SaveResult.createSuccess(0)
      }

      // 插入关联记录
      const rdbValuesBucket: relationalStore.ValuesBucket = {}
      rdbValuesBucket[relation.joinSourceKey] = sourceId
      rdbValuesBucket[relation.joinTargetKey] = targetId

      const rowId = await store.insert(relation.joinTable, rdbValuesBucket)

      // 记录日志
      const duration = Date.now() - startTime
      this.logger.logQuery(`INSERT INTO ${relation.joinTable} (${relation.joinSourceKey}=${sourceId}, ${relation.joinTargetKey}=${targetId})`, duration)

      return SaveResult.createSuccess(1, rowId)
    } catch (error) {
      if (error instanceof RelationNotFoundError) {
        throw error
      }
      const errorMessage = error instanceof Error ? error.message : String(error)
      this.logger.logError(`ATTACH 失败: ${errorMessage}`)
      return SaveResult.createFailure(errorMessage)
    }
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
  async detach(sourceId: number, targetId: number, relationName: string): Promise<DeleteResult> {
    const startTime = Date.now()
    try {
      // 获取多对多关联元数据
      const relation = MetadataStorage.getInstance().getManyToManyRelation(this.entityName, relationName)
      if (relation === null) {
        throw new RelationNotFoundError(this.entityName, relationName)
      }

      const store = this.getStore()

      // 删除关联记录
      const predicates = new relationalStore.RdbPredicates(relation.joinTable)
      predicates.equalTo(relation.joinSourceKey, sourceId)
      predicates.and()
      predicates.equalTo(relation.joinTargetKey, targetId)

      const affectedRows = await store.delete(predicates)

      // 记录日志
      const duration = Date.now() - startTime
      this.logger.logQuery(`DELETE FROM ${relation.joinTable} WHERE ${relation.joinSourceKey}=${sourceId} AND ${relation.joinTargetKey}=${targetId}`, duration)

      return DeleteResult.createSuccess(affectedRows)
    } catch (error) {
      if (error instanceof RelationNotFoundError) {
        throw error
      }
      const errorMessage = error instanceof Error ? error.message : String(error)
      this.logger.logError(`DETACH 失败: ${errorMessage}`)
      return DeleteResult.createFailure(errorMessage)
    }
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
    const startTime = Date.now()
    try {
      // 获取多对多关联元数据
      const relation = MetadataStorage.getInstance().getManyToManyRelation(this.entityName, relationName)
      if (relation === null) {
        throw new RelationNotFoundError(this.entityName, relationName)
      }

      const store = this.getStore()

      // 在事务中执行同步操作
      store.beginTransaction()
      this.logger.logTransaction('BEGIN (sync)')

      try {
        // 1. 删除源实体的所有现有关联
        const deletePredicates = new relationalStore.RdbPredicates(relation.joinTable)
        deletePredicates.equalTo(relation.joinSourceKey, this.toRdbValue(sourceId))
        const deletedCount = await store.delete(deletePredicates)

        // 2. 插入新的关联记录
        let insertedCount = 0
        for (let i = 0; i < targetIds.length; i++) {
          const targetId = targetIds[i]
          const rdbValuesBucket: relationalStore.ValuesBucket = {}
          rdbValuesBucket[relation.joinSourceKey] = this.toRdbValue(sourceId)
          rdbValuesBucket[relation.joinTargetKey] = this.toRdbValue(targetId)

          await store.insert(relation.joinTable, rdbValuesBucket)
          insertedCount++
        }

        // 提交事务
        store.commit()
        this.logger.logTransaction('COMMIT (sync)')

        // 记录日志
        const duration = Date.now() - startTime
        this.logger.logQuery(`SYNC ${relation.joinTable}: 删除 ${deletedCount} 条, 插入 ${insertedCount} 条`, duration)

        return SaveResult.createSuccess(insertedCount)
      } catch (syncError) {
        // 回滚事务
        store.rollBack()
        this.logger.logTransaction('ROLLBACK (sync)')
        if (syncError instanceof Error) {
          throw syncError
        }
        throw new Error(String(syncError))
      }
    } catch (error) {
      if (error instanceof RelationNotFoundError) {
        throw error
      }
      const errorMessage = error instanceof Error ? error.message : String(error)
      this.logger.logError(`SYNC 失败: ${errorMessage}`)
      return SaveResult.createFailure(errorMessage)
    }
  }
}

/**
 * 事务回调函数类型
 */
export type TransactionCallback = (repo: Repository) => Promise<void>

/**
 * 事务执行结果类
 */
export class TransactionResult {
  /** 是否成功 */
  success: boolean = false
  /** 错误信息 */
  errorMessage: string = ''

  static createSuccess(): TransactionResult {
    const result = new TransactionResult()
    result.success = true
    return result
  }

  static createFailure(errorMessage: string): TransactionResult {
    const result = new TransactionResult()
    result.success = false
    result.errorMessage = errorMessage
    return result
  }
}
