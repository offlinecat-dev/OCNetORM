import { relationalStore } from '@kit.ArkData'
import { EntityMetadata } from '../core/EntityMetadata'
import { HooksProcessor } from '../core/HooksProcessor'
import { DataMapper } from '../mapping/DataMapper'
import { EntityData } from '../mapping/EntityData'
import { Logger } from '../logging/Logger'
import { ValueType } from '../types/ValueTypes'
import { PrimaryKeyNotDefinedError } from '../errors/MetadataError'
import { ExecutionError } from '../errors/DatabaseError'
import { HookExecutionError } from '../errors/HookError'
import { QueryCache } from '../query/QueryCache'
import { CascadeHandler, CascadeOperation, CascadeRepository, CascadeRepositoryFactory } from './CascadeHandler'
import { EntityValidator } from '../validation/EntityValidator'
import { ValidationError, UniqueValidationError } from '../errors/ValidationError'
import { ValidationMetadataStorage, ValidationRule } from '../validation/ValidationMetadataStorage'
import { SaveResult } from './SaveResult'
type StoreProvider = () => relationalStore.RdbStore
type UpdatedAtResolver = () => string | null; type ValueConverter = (value: ValueType) => relationalStore.ValueType
type SourceRepoProvider = () => CascadeRepository
export class CrudOperations {
  private entityName: string
  private entityMetadata: EntityMetadata
  private dataMapper: DataMapper
  private hooksProcessor: HooksProcessor
  private logger: Logger
  private queryCache: QueryCache
  private cascadeHandler: CascadeHandler
  private getStore: StoreProvider
  private getUpdatedAtColumnName: UpdatedAtResolver
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
    getUpdatedAtColumnName: UpdatedAtResolver,
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
    this.getUpdatedAtColumnName = getUpdatedAtColumnName
    this.toRdbValue = toRdbValue
    this.getSourceRepository = getSourceRepository
    this.repositoryFactory = repositoryFactory
  }
  async save(entityData: EntityData): Promise<SaveResult> {
    try {
      EntityValidator.validateOrThrow(this.entityName, entityData)
      await this.validateUniqueConstraints(entityData)
      await this.hooksProcessor.executeBeforeSave(this.entityName, entityData)
      const isNew = this.dataMapper.isNewRecord(entityData)
      const operation: CascadeOperation = isNew ? 'insert' : 'update'
      await this.cascadeHandler.handleBeforeSave(this.entityName, entityData, operation, this.repositoryFactory)
      const result = isNew ? await this.insert(entityData) : await this.update(entityData)
      await this.cascadeHandler.handleAfterSave(
        this.entityName,
        entityData,
        operation,
        this.getSourceRepository(),
        this.repositoryFactory
      )
      return result
    } catch (error) {
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
  private async insert(entityData: EntityData): Promise<SaveResult> {
    const startTime = Date.now()
    try {
      const store = this.getStore()
      const pkColumn = this.entityMetadata.getPrimaryKeyColumn()
      if (pkColumn === null) {
        throw new PrimaryKeyNotDefinedError(this.entityName)
      }
      const valuesBucket = this.dataMapper.toValuesBucket(entityData, false)
      const rdbValuesBucket: relationalStore.ValuesBucket = {}
      const keys = valuesBucket.keys()
      for (let i = 0; i < keys.length; i++) {
        const key = keys[i]
        if (key === pkColumn.columnName && pkColumn.isAutoIncrement) {
          continue
        }
        rdbValuesBucket[key] = valuesBucket.get(key)
      }
      const updatedAtColumn = this.getUpdatedAtColumnName()
      if (updatedAtColumn !== null) {
        rdbValuesBucket[updatedAtColumn] = Date.now()
      }
      if (this.entityMetadata.isSoftDeleteEnabled()) {
        const deletedAtColumn = this.entityMetadata.getDeletedAtColumn()
        if (rdbValuesBucket[deletedAtColumn] === undefined) {
          rdbValuesBucket[deletedAtColumn] = null
        }
      }
      const rowId = store.insertSync(this.entityMetadata.tableName, rdbValuesBucket)
      this.logger.logQuery(`INSERT INTO ${this.entityMetadata.tableName}`, Date.now() - startTime)
      if (pkColumn.isAutoIncrement) {
        this.dataMapper.setPrimaryKeyValue(entityData, rowId)
      }
      this.queryCache.invalidateEntity(this.entityName)
      return SaveResult.createSuccess(1, rowId)
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      this.logger.logError(`INSERT 失败: ${errorMessage}`)
      throw new ExecutionError('INSERT', errorMessage)
    }
  }
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
      const valuesBucket = this.dataMapper.toValuesBucket(entityData, false)
      const rdbValuesBucket: relationalStore.ValuesBucket = {}
      const keys = valuesBucket.keys()
      for (let i = 0; i < keys.length; i++) {
        const key = keys[i]
        if (key === pkColumn.columnName) {
          continue
        }
        rdbValuesBucket[key] = valuesBucket.get(key)
      }
      const updatedAtColumn = this.getUpdatedAtColumnName()
      if (updatedAtColumn !== null) {
        rdbValuesBucket[updatedAtColumn] = Date.now()
      }
      const setClauses: string[] = []
      const values: relationalStore.ValueType[] = []
      const bucketKeys = Object.keys(rdbValuesBucket)
      for (let i = 0; i < bucketKeys.length; i++) {
        const key = bucketKeys[i]
        setClauses.push(`${this.escapeIdentifier(key)} = ?`)
        values.push(rdbValuesBucket[key])
      }
      values.push(this.toRdbValue(pkValue))
      const tableName = this.escapeIdentifier(this.entityMetadata.tableName)
      const pkColumnName = this.escapeIdentifier(pkColumn.columnName)
      const updateSql = `UPDATE ${tableName} SET ${setClauses.join(', ')} WHERE ${pkColumnName} = ?`
      store.executeSync(updateSql, values)
      this.logger.logQuery(`UPDATE ${this.entityMetadata.tableName} WHERE ${pkColumn.columnName} = ${String(pkValue)}`, Date.now() - startTime)
      this.queryCache.invalidate(this.entityName, pkValue)
      return SaveResult.createSuccess(1)
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      this.logger.logError(`UPDATE 失败: ${errorMessage}`)
      throw new ExecutionError('UPDATE', errorMessage)
    }
  }

  private async validateUniqueConstraints(entityData: EntityData): Promise<void> {
    const rules = ValidationMetadataStorage.getInstance().getRules(this.entityName)
    const propertyNames = this.collectUniquePropertyNames(rules)
    if (propertyNames.length === 0) {
      return
    }
    const pkColumn = this.entityMetadata.getPrimaryKeyColumn()
    const currentPkValue = pkColumn !== null ? this.dataMapper.getPrimaryKeyValue(entityData) : null
    for (let i = 0; i < propertyNames.length; i++) {
      const propertyName = propertyNames[i]
      await this.ensureUniqueValue(entityData, propertyName, currentPkValue)
    }
  }

  private hasUniqueRule(propertyRules: Array<ValidationRule>): boolean {
    for (let i = 0; i < propertyRules.length; i++) {
      if (propertyRules[i].type === 'unique') {
        return true
      }
    }
    return false
  }

  private collectUniquePropertyNames(rules: Map<string, Array<ValidationRule>>): Array<string> {
    const names: Array<string> = []
    rules.forEach((propertyRules, propertyName) => {
      if (this.hasUniqueRule(propertyRules) && !names.includes(propertyName)) {
        names.push(propertyName)
      }
    })
    for (let i = 0; i < this.entityMetadata.columns.length; i++) {
      const column = this.entityMetadata.columns[i]
      if (column.isUnique && !names.includes(column.propertyName)) {
        names.push(column.propertyName)
      }
    }
    return names
  }

  private async ensureUniqueValue(
    entityData: EntityData,
    propertyName: string,
    currentPkValue: ValueType
  ): Promise<void> {
    const value = entityData.getPropertyValue(propertyName)
    if (value === null || value === undefined) {
      return
    }
    const column = this.entityMetadata.getColumnByProperty(propertyName)
    if (column === null) {
      return
    }
    const store = this.getStore()
    const predicates = new relationalStore.RdbPredicates(this.entityMetadata.tableName)
    predicates.equalTo(column.columnName, this.toRdbValue(value))
    const pkColumn = this.entityMetadata.getPrimaryKeyColumn()
    if (pkColumn !== null && currentPkValue !== null) {
      predicates.and()
      predicates.notEqualTo(pkColumn.columnName, this.toRdbValue(currentPkValue))
    }
    let resultSet: relationalStore.ResultSet | null = null
    try {
      resultSet = await store.query(predicates)
      if (resultSet.rowCount > 0) {
        throw new UniqueValidationError(this.entityName, column.columnName)
      }
    } finally {
      this.closeResultSet(resultSet)
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

  private escapeIdentifier(identifier: string): string {
    const escaped = identifier.replace(/"/g, '""')
    return `"${escaped}"`
  }
}
