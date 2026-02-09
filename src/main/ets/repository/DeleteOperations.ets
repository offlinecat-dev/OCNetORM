import { relationalStore } from '@kit.ArkData'
import { EntityMetadata } from '../core/EntityMetadata'
import { HooksProcessor } from '../core/HooksProcessor'
import { DataMapper } from '../mapping/DataMapper'
import { EntityData } from '../mapping/EntityData'
import { Logger } from '../logging/Logger'
import { ValueType } from '../types/ValueTypes'
import { PrimaryKeyNotDefinedError } from '../errors/MetadataError'
import { ExecutionError } from '../errors/DatabaseError'
import { SoftDeleteNotEnabledError } from '../errors/SoftDeleteError'
import { HookExecutionError } from '../errors/HookError'
import { QueryCache } from '../query/QueryCache'
import { CascadeHandler, CascadeRepository, CascadeRepositoryFactory } from './CascadeHandler'
import { SaveResult } from './SaveResult'
import { DeleteResult } from './DeleteResult'
type StoreProvider = () => relationalStore.RdbStore; type ValueConverter = (value: ValueType) => relationalStore.ValueType; type SourceRepoProvider = () => CascadeRepository
export class DeleteOperations {
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
    try {
      const pkValue = this.dataMapper.getPrimaryKeyValue(entityData)
      if (pkValue === null) {
        return DeleteResult.createFailure('实体没有主键值')
      }
      await this.hooksProcessor.executeBeforeDelete(this.entityName, entityData)
      await this.cascadeHandler.handleBeforeRemove(
        this.entityName,
        entityData,
        this.getSourceRepository(),
        this.repositoryFactory
      )
      return await this.removeById(pkValue)
    } catch (error) {
      if (error instanceof HookExecutionError) {
        throw error
      }
      const errorMessage = error instanceof Error ? error.message : String(error)
      return DeleteResult.createFailure(errorMessage)
    }
  }
  async removeById(id: ValueType): Promise<DeleteResult> {
    try {
      if (this.entityMetadata.isSoftDeleteEnabled()) {
        return await this.softDelete(id)
      }
      return await this.hardDelete(id)
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
      return await this.hardDelete(id)
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
      const deletedAtColumn = this.entityMetadata.getDeletedAtColumn()
      const tableName = this.escapeIdentifier(this.entityMetadata.tableName)
      const deletedAtColumnName = this.escapeIdentifier(deletedAtColumn)
      const pkColumnName = this.escapeIdentifier(pkColumn.columnName)
      const updateSql = `UPDATE ${tableName} SET ${deletedAtColumnName} = NULL WHERE ${pkColumnName} = ?`
      store.executeSync(updateSql, [this.toRdbValue(id)])
      this.logger.logQuery(`UPDATE ${this.entityMetadata.tableName} SET ${deletedAtColumn} = NULL WHERE ${pkColumn.columnName} = ${String(id)}`, Date.now() - startTime)
      return SaveResult.createSuccess(1)
    } catch (error) {
      if (error instanceof SoftDeleteNotEnabledError) {
        throw error
      }
      const errorMessage = error instanceof Error ? error.message : String(error)
      this.logger.logError(`RESTORE 失败: ${errorMessage}`)
      return SaveResult.createFailure(errorMessage)
    }
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
      const tableName = this.escapeIdentifier(this.entityMetadata.tableName)
      const deletedAtColumnName = this.escapeIdentifier(deletedAtColumn)
      const pkColumnName = this.escapeIdentifier(pkColumn.columnName)
      const updateSql = `UPDATE ${tableName} SET ${deletedAtColumnName} = ? WHERE ${pkColumnName} = ?`
      store.executeSync(updateSql, [currentTimestamp, this.toRdbValue(id)])
      this.logger.logQuery(`UPDATE ${this.entityMetadata.tableName} SET ${deletedAtColumn} = ${currentTimestamp} WHERE ${pkColumn.columnName} = ${String(id)}`, Date.now() - startTime)
      this.queryCache.invalidate(this.entityName, id)
      return DeleteResult.createSuccess(1)
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      this.logger.logError(`SOFT_DELETE 失败: ${errorMessage}`)
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
      const tableName = this.escapeIdentifier(this.entityMetadata.tableName)
      const pkColumnName = this.escapeIdentifier(pkColumn.columnName)
      const deleteSql = `DELETE FROM ${tableName} WHERE ${pkColumnName} = ?`
      store.executeSync(deleteSql, [this.toRdbValue(id)])
      this.logger.logQuery(`DELETE FROM ${this.entityMetadata.tableName} WHERE ${pkColumn.columnName} = ${String(id)}`, Date.now() - startTime)
      this.queryCache.invalidate(this.entityName, id)
      return DeleteResult.createSuccess(1)
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      this.logger.logError(`DELETE 失败: ${errorMessage}`)
      throw new ExecutionError('DELETE', errorMessage)
    }
  }

  private escapeIdentifier(identifier: string): string {
    const escaped = identifier.replace(/"/g, '""')
    return `"${escaped}"`
  }
}
