import { relationalStore } from '@kit.ArkData'
import { EntityMetadata } from '../core/EntityMetadata'
import { MetadataStorage } from '../core/MetadataStorage'
import { CascadeSetting } from '../core/RelationMetadata'
import { HooksProcessor } from '../core/HooksProcessor'
import { OrmContext, OrmEvent } from '../core/OrmContext'
import { DataMapper } from '../mapping/DataMapper'
import { EntityData } from '../mapping/EntityData'
import { Logger } from '../logging/Logger'
import { ValueType } from '../types/ValueTypes'
import { RelationType } from '../types/RelationType'
import { PrimaryKeyNotDefinedError } from '../errors/MetadataError'
import { ExecutionError } from '../errors/DatabaseError'
import { SoftDeleteNotEnabledError } from '../errors/SoftDeleteError'
import { HookExecutionError } from '../errors/HookError'
import { QueryCache } from '../query/QueryCache'
import { CascadeHandler, CascadeRepository, CascadeRepositoryFactory } from './CascadeHandler'
import { SaveResult } from './SaveResult'
import { DeleteResult } from './DeleteResult'
type StoreProvider = () => relationalStore.RdbStore; type ValueConverter = (value: ValueType) => relationalStore.ValueType; type SourceRepoProvider = () => CascadeRepository

interface SavepointExecutor {
  executeSql(sql: string): Promise<void>
}

class SavepointState {
  name: string
  started: boolean

  constructor(name: string, started: boolean) {
    this.name = name
    this.started = started
  }
}

export class DeleteOperations {
  private static savepointCounter: number = 0
  private entityName: string
  private entityMetadata: EntityMetadata
  private dataMapper: DataMapper
  private hooksProcessor: HooksProcessor
  private logger: Logger
  private queryCache: QueryCache
  private cascadeHandler: CascadeHandler
  private getStore: StoreProvider
  private toRdbValue: ValueConverter
  private getSourceRepository: SourceRepoProvider
  private repositoryFactory: CascadeRepositoryFactory

  constructor(
    entityName: string,
    entityMetadata: EntityMetadata,
    dataMapper: DataMapper,
    hooksProcessor: HooksProcessor,
    logger: Logger,
    queryCache: QueryCache,
    cascadeHandler: CascadeHandler,
    getStore: StoreProvider,
    toRdbValue: ValueConverter,
    getSourceRepository: SourceRepoProvider,
    repositoryFactory: CascadeRepositoryFactory
  ) {
    this.entityName = entityName
    this.entityMetadata = entityMetadata
    this.dataMapper = dataMapper
    this.hooksProcessor = hooksProcessor
    this.logger = logger
    this.queryCache = queryCache
    this.cascadeHandler = cascadeHandler
    this.getStore = getStore
    this.toRdbValue = toRdbValue
    this.getSourceRepository = getSourceRepository
    this.repositoryFactory = repositoryFactory
  }
  async remove(entityData: EntityData): Promise<DeleteResult> {
    let store: relationalStore.RdbStore | null = null
    let savepointName: string = ''
    let savepointStarted = false
    try {
      store = this.getStore()
      const pkValue = this.dataMapper.getPrimaryKeyValue(entityData)
      if (pkValue === null) {
        return DeleteResult.createFailure('实体没有主键值')
      }
      if (this.shouldUseSavepointForRemove(entityData, pkValue)) {
        const savepoint = await this.beginSavepointOrThrow(store, 'remove')
        savepointName = savepoint.name
        savepointStarted = true
      }
      await this.hooksProcessor.executeBeforeDelete(this.entityName, entityData)
      await this.cascadeHandler.handleBeforeRemove(
        this.entityName,
        entityData,
        this.getSourceRepository(),
        this.repositoryFactory
      )
      const result = await this.removeById(pkValue)
      if (!result.success) {
        const message = result.errorMessage.length > 0 ? result.errorMessage : '删除失败'
        throw new ExecutionError('REMOVE', message)
      }
      if (result.success) {
        await this.hooksProcessor.executeAfterDelete(this.entityName, entityData)
      }
      if (store !== null && savepointStarted) {
        await this.releaseSavepoint(store, savepointName)
      }
      return result
    } catch (error) {
      if (store !== null && savepointStarted) {
        try {
          await this.rollbackToSavepointSafely(store, savepointName)
        } catch (rollbackError) {
          const rollbackMessage = rollbackError instanceof Error ? rollbackError.message : String(rollbackError)
          throw new ExecutionError('SAVEPOINT', `级联删除回滚失败: ${rollbackMessage}`)
        }
      }
      if (error instanceof HookExecutionError) {
        throw error
      }
      const errorMessage = error instanceof Error ? error.message : String(error)
      return DeleteResult.createFailure(errorMessage)
    }
  }
  async removeById(id: ValueType): Promise<DeleteResult> {
    try {
      let result: DeleteResult
      if (this.entityMetadata.isSoftDeleteEnabled()) {
        result = await this.softDelete(id)
      } else {
        result = await this.hardDelete(id)
      }
      if (result.success) {
        const event = new OrmEvent('entity:deleted')
        event.entityName = this.entityName
        event.idText = String(id)
        event.affectedRows = result.affectedRows
        event.softDelete = this.entityMetadata.isSoftDeleteEnabled()
        event.force = false
        await OrmContext.emit('entity:deleted', event)
      }
      return result
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      return DeleteResult.createFailure(errorMessage)
    }
  }
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
  async forceRemoveById(id: ValueType): Promise<DeleteResult> {
    try {
      const result = await this.hardDelete(id)
      if (result.success) {
        const event = new OrmEvent('entity:deleted')
        event.entityName = this.entityName
        event.idText = String(id)
        event.affectedRows = result.affectedRows
        event.softDelete = false
        event.force = true
        await OrmContext.emit('entity:deleted', event)
      }
      return result
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      return DeleteResult.createFailure(errorMessage)
    }
  }
  async restore(id: ValueType): Promise<SaveResult> {
    const startTime = Date.now()
    try {
      if (!this.entityMetadata.isSoftDeleteEnabled()) {
        throw new SoftDeleteNotEnabledError(this.entityName)
      }
      const store = this.getStore()
      const pkColumn = this.entityMetadata.getPrimaryKeyColumn()
      if (pkColumn === null) {
        throw new PrimaryKeyNotDefinedError(this.entityName)
      }
      const hookData = this.createHookEntityData(pkColumn.propertyName, id)
      await this.hooksProcessor.executeBeforeRestore(this.entityName, hookData)
      const deletedAtColumn = this.entityMetadata.getDeletedAtColumn()
      const predicates = new relationalStore.RdbPredicates(this.entityMetadata.tableName)
      predicates.equalTo(pkColumn.columnName, this.toRdbValue(id))
      const updateValues: relationalStore.ValuesBucket = {}
      updateValues[deletedAtColumn] = null
      const affectedRows = await store.update(updateValues, predicates)
      const restoreSql = `UPDATE ${this.entityMetadata.tableName} SET ${deletedAtColumn} = NULL WHERE ${pkColumn.columnName} = ${String(id)}`
      const restoreDuration = Date.now() - startTime
      this.logger.logQuery(restoreSql, restoreDuration)
      await OrmContext.emitSlowQuery('RESTORE', restoreSql, restoreDuration, this.entityName)
      if (affectedRows > 0) {
        await this.hooksProcessor.executeAfterRestore(this.entityName, hookData)
        const event = new OrmEvent('entity:restored')
        event.entityName = this.entityName
        event.idText = String(id)
        event.affectedRows = affectedRows
        await OrmContext.emit('entity:restored', event)
      }
      return SaveResult.createSuccess(affectedRows)
    } catch (error) {
      if (error instanceof SoftDeleteNotEnabledError) {
        throw error
      }
      if (error instanceof HookExecutionError) {
        throw error
      }
      const errorMessage = error instanceof Error ? error.message : String(error)
      this.logWriteFailure('RESTORE', errorMessage)
      return SaveResult.createFailure(errorMessage)
    }
  }

  private createHookEntityData(primaryKeyProperty: string, id: ValueType): EntityData {
    const data = new EntityData(this.entityName)
    data.addProperty(primaryKeyProperty, id, typeof id)
    return data
  }

  private async softDelete(id: ValueType): Promise<DeleteResult> {
    const startTime = Date.now()
    try {
      const store = this.getStore()
      const pkColumn = this.entityMetadata.getPrimaryKeyColumn()
      if (pkColumn === null) {
        throw new PrimaryKeyNotDefinedError(this.entityName)
      }
      const deletedAtColumn = this.entityMetadata.getDeletedAtColumn()
      const currentTimestamp = Date.now()
      const predicates = new relationalStore.RdbPredicates(this.entityMetadata.tableName)
      predicates.equalTo(pkColumn.columnName, this.toRdbValue(id))
      const updateValues: relationalStore.ValuesBucket = {}
      updateValues[deletedAtColumn] = currentTimestamp
      const affectedRows = await store.update(updateValues, predicates)
      const softDeleteSql = `UPDATE ${this.entityMetadata.tableName} SET ${deletedAtColumn} = ${currentTimestamp} WHERE ${pkColumn.columnName} = ${String(id)}`
      const softDeleteDuration = Date.now() - startTime
      this.logger.logQuery(softDeleteSql, softDeleteDuration)
      await OrmContext.emitSlowQuery('SOFT_DELETE', softDeleteSql, softDeleteDuration, this.entityName)
      this.queryCache.invalidate(this.entityName, id)
      return DeleteResult.createSuccess(affectedRows)
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      this.logWriteFailure('SOFT_DELETE', errorMessage)
      throw new ExecutionError('SOFT_DELETE', errorMessage)
    }
  }
  private async hardDelete(id: ValueType): Promise<DeleteResult> {
    const startTime = Date.now()
    try {
      const store = this.getStore()
      const pkColumn = this.entityMetadata.getPrimaryKeyColumn()
      if (pkColumn === null) {
        throw new PrimaryKeyNotDefinedError(this.entityName)
      }
      const predicates = new relationalStore.RdbPredicates(this.entityMetadata.tableName)
      predicates.equalTo(pkColumn.columnName, this.toRdbValue(id))
      const affectedRows = await store.delete(predicates)
      const deleteSql = `DELETE FROM ${this.entityMetadata.tableName} WHERE ${pkColumn.columnName} = ${String(id)}`
      const deleteDuration = Date.now() - startTime
      this.logger.logQuery(deleteSql, deleteDuration)
      await OrmContext.emitSlowQuery('DELETE', deleteSql, deleteDuration, this.entityName)
      this.queryCache.invalidate(this.entityName, id)
      return DeleteResult.createSuccess(affectedRows)
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      this.logWriteFailure('DELETE', errorMessage)
      throw new ExecutionError('DELETE', errorMessage)
    }
  }

  private shouldUseSavepointForRemove(entityData: EntityData, sourcePk: ValueType): boolean {
    const relations = MetadataStorage.getInstance().getRelations(this.entityName)
    for (let i = 0; i < relations.length; i++) {
      const relation = relations[i]
      if (!this.isCascadeEnabledForRemove(relation.cascade)) {
        continue
      }
      if (relation.type === RelationType.MANY_TO_MANY && sourcePk !== null) {
        return true
      }
      if (entityData.hasRelated(relation.propertyName)) {
        return true
      }
    }
    return false
  }

  private isCascadeEnabledForRemove(cascade: CascadeSetting | null): boolean {
    if (cascade === null || cascade === undefined) {
      return false
    }
    if (cascade === true) {
      return true
    }
    if (typeof cascade !== 'object') {
      return false
    }
    return cascade.remove === true
  }

  private nextSavepointName(prefix: string): string {
    DeleteOperations.savepointCounter += 1
    return `ocorm_${prefix}_${DeleteOperations.savepointCounter}`
  }

  private async beginSavepointOrThrow(
    store: relationalStore.RdbStore,
    prefix: string
  ): Promise<SavepointState> {
    const executor = this.getSavepointExecutor(store)
    const savepointName = this.nextSavepointName(prefix)
    if (executor === null) {
      throw new ExecutionError('SAVEPOINT', '当前数据库不支持 SAVEPOINT，无法保证级联删除原子性')
    }
    try {
      await executor.executeSql(`SAVEPOINT ${savepointName}`)
      return new SavepointState(savepointName, true)
    } catch (e) {
      const message = e instanceof Error ? e.message : String(e)
      throw new ExecutionError('SAVEPOINT', `创建保存点失败: ${message}`)
    }
  }

  private async releaseSavepoint(store: relationalStore.RdbStore, savepointName: string): Promise<void> {
    const executor = this.getSavepointExecutor(store)
    if (executor === null) {
      throw new ExecutionError('SAVEPOINT', '当前数据库不支持 SAVEPOINT，无法释放保存点')
    }
    try {
      await executor.executeSql(`RELEASE SAVEPOINT ${savepointName}`)
    } catch (e) {
      const message = e instanceof Error ? e.message : String(e)
      throw new ExecutionError('SAVEPOINT', `释放保存点失败: ${message}`)
    }
  }

  private async rollbackToSavepointSafely(store: relationalStore.RdbStore, savepointName: string): Promise<void> {
    const executor = this.getSavepointExecutor(store)
    if (executor === null) {
      throw new ExecutionError('SAVEPOINT', '当前数据库不支持 SAVEPOINT，无法回滚保存点')
    }
    try {
      await executor.executeSql(`ROLLBACK TO SAVEPOINT ${savepointName}`)
      await executor.executeSql(`RELEASE SAVEPOINT ${savepointName}`)
    } catch (e) {
      const message = e instanceof Error ? e.message : String(e)
      throw new ExecutionError('SAVEPOINT', `回滚保存点失败: ${message}`)
    }
  }

  private getSavepointExecutor(store: relationalStore.RdbStore): SavepointExecutor | null {
    const executor = store as SavepointExecutor
    if (typeof executor.executeSql !== 'function') {
      return null
    }
    return executor
  }

  private logWriteFailure(operation: string, errorMessage: string): void {
    const normalized = errorMessage.toLowerCase()
    if (normalized.includes('readonly database') ||
      normalized.includes('read-only') ||
      normalized.includes('attempt to write a readonly database') ||
      normalized.includes('query_only') ||
      errorMessage.includes('只读')) {
      this.logger.logWarn(`[W_TX_READONLY_WRITE_DENIED] ${operation} 失败: ${errorMessage}`)
      return
    }
    this.logger.logError(`${operation} 失败: ${errorMessage}`)
  }

}
