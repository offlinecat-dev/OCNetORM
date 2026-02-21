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

export class CrudOperations {
  private static savepointCounter: number = 0
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
    let store: relationalStore.RdbStore | null = null
    let savepointName: string = ''
    let savepointStarted = false
    try {
      store = this.getStore()
      EntityValidator.validateOrThrow(this.entityName, entityData)
      await this.validateUniqueConstraints(entityData)
      const isNew = this.dataMapper.isNewRecord(entityData)
      const operation: CascadeOperation = isNew ? 'insert' : 'update'
      if (this.shouldUseSavepointForSave(entityData, operation)) {
        const savepoint = await this.beginSavepointOrThrow(store, 'save')
        savepointName = savepoint.name
        savepointStarted = true
      }
      await this.hooksProcessor.executeBeforeSave(this.entityName, entityData)
      if (isNew) {
        await this.hooksProcessor.executeBeforeInsert(this.entityName, entityData)
      } else {
        await this.hooksProcessor.executeBeforeUpdate(this.entityName, entityData)
      }
      await this.cascadeHandler.handleBeforeSave(this.entityName, entityData, operation, this.repositoryFactory)
      const result = isNew ? await this.insert(entityData) : await this.update(entityData)
      await this.cascadeHandler.handleAfterSave(
        this.entityName,
        entityData,
        operation,
        this.getSourceRepository(),
        this.repositoryFactory
      )
      if (isNew) {
        await this.hooksProcessor.executeAfterInsert(this.entityName, entityData)
      } else {
        await this.hooksProcessor.executeAfterUpdate(this.entityName, entityData)
      }
      await this.hooksProcessor.executeAfterSave(this.entityName, entityData)
      const event = new OrmEvent('entity:saved')
      event.entityName = this.entityName
      event.idText = String(this.dataMapper.getPrimaryKeyValue(entityData))
      event.isNew = isNew
      event.affectedRows = result.affectedRows
      await OrmContext.emit('entity:saved', event)
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
          throw new ExecutionError('SAVEPOINT', `级联保存回滚失败: ${rollbackMessage}`)
        }
      }
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
      const insertDuration = Date.now() - startTime
      this.logger.logQuery(`INSERT INTO ${this.entityMetadata.tableName}`, insertDuration)
      await OrmContext.emitSlowQuery('INSERT', `INSERT INTO ${this.entityMetadata.tableName}`, insertDuration, this.entityName)
      if (pkColumn.isAutoIncrement) {
        this.dataMapper.setPrimaryKeyValue(entityData, rowId)
      }
      this.queryCache.invalidateEntity(this.entityName)
      return SaveResult.createSuccess(1, rowId)
    } catch (error) {
      const uniqueError = this.tryBuildUniqueValidationError(error)
      if (uniqueError !== null) {
        throw uniqueError
      }
      const errorMessage = error instanceof Error ? error.message : String(error)
      this.logWriteFailure('INSERT', errorMessage)
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
      const predicates = new relationalStore.RdbPredicates(this.entityMetadata.tableName)
      predicates.equalTo(pkColumn.columnName, this.toRdbValue(pkValue))
      const affectedRows = await store.update(rdbValuesBucket, predicates)
      const updatedColumns = Object.keys(rdbValuesBucket)
      const setClause = updatedColumns.length > 0
        ? updatedColumns.map((column) => `${column} = ?`).join(', ')
        : '(no columns)'
      const updateSql = `UPDATE ${this.entityMetadata.tableName} SET ${setClause} WHERE ${pkColumn.columnName} = ${String(pkValue)}`
      const updateDuration = Date.now() - startTime
      this.logger.logQuery(updateSql, updateDuration)
      await OrmContext.emitSlowQuery('UPDATE', updateSql, updateDuration, this.entityName)
      this.queryCache.invalidate(this.entityName, pkValue)
      return SaveResult.createSuccess(affectedRows)
    } catch (error) {
      const uniqueError = this.tryBuildUniqueValidationError(error)
      if (uniqueError !== null) {
        throw uniqueError
      }
      const errorMessage = error instanceof Error ? error.message : String(error)
      this.logWriteFailure('UPDATE', errorMessage)
      throw new ExecutionError('UPDATE', errorMessage)
    }
  }

  private logWriteFailure(operation: string, errorMessage: string): void {
    const normalized = errorMessage.toLowerCase()
    if (normalized.includes('readonly database') ||
      normalized.includes('read-only') ||
      normalized.includes('query_only') ||
      errorMessage.includes('只读')) {
      this.logger.logWarn(`[W_TX_READONLY_WRITE_DENIED] ${operation} 失败: ${errorMessage}`)
      return
    }
    this.logger.logError(`${operation} 失败: ${errorMessage}`)
  }

  private tryBuildUniqueValidationError(error: Error | string | number | boolean | object | null | undefined): UniqueValidationError | null {
    const errorMessage = error instanceof Error ? error.message : String(error)
    if (!this.isUniqueConstraintViolation(errorMessage)) {
      return null
    }
    const conflictColumn = this.extractUniqueConflictColumn(errorMessage)
    if (conflictColumn.length > 0) {
      return new UniqueValidationError(this.entityName, conflictColumn)
    }
    const rules = ValidationMetadataStorage.getInstance().getRules(this.entityName)
    const uniqueProperties = this.collectUniquePropertyNames(rules)
    if (uniqueProperties.length > 0) {
      const column = this.entityMetadata.getColumnByProperty(uniqueProperties[0])
      if (column !== null) {
        return new UniqueValidationError(this.entityName, column.columnName)
      }
    }
    return new UniqueValidationError(this.entityName, 'unique')
  }

  private isUniqueConstraintViolation(errorMessage: string): boolean {
    const normalized = errorMessage.toLowerCase()
    return normalized.includes('unique constraint failed') ||
      (normalized.includes('constraint failed') && normalized.includes('unique')) ||
      normalized.includes('duplicate key') ||
      normalized.includes('duplicate entry') ||
      errorMessage.includes('唯一')
  }

  private extractUniqueConflictColumn(errorMessage: string): string {
    const matched = errorMessage.match(/unique\s+constraint\s+failed\s*:\s*([^\n]+)/i)
    if (!matched || matched.length < 2) {
      return ''
    }
    const segment = matched[1].split(',')[0].trim()
    if (segment.length === 0) {
      return ''
    }
    const rawColumn = segment.includes('.') ? segment.split('.').pop() : segment
    if (!rawColumn) {
      return ''
    }
    const columnName = rawColumn.replace(/["'`]/g, '').trim()
    if (columnName.length === 0) {
      return ''
    }
    const column = this.entityMetadata.getColumnByName(columnName)
    if (column !== null) {
      return column.columnName
    }
    return columnName
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

  private shouldUseSavepointForSave(entityData: EntityData, operation: CascadeOperation): boolean {
    const relations = MetadataStorage.getInstance().getRelations(this.entityName)
    for (let i = 0; i < relations.length; i++) {
      const relation = relations[i]
      if (!this.isCascadeEnabledForOperation(relation.cascade, operation)) {
        continue
      }
      const isSourceOneToOne = relation.type === RelationType.ONE_TO_ONE && relation.foreignKeySide === 'source'
      const isTargetOneToOne = relation.type === RelationType.ONE_TO_ONE && relation.foreignKeySide === 'target'
      const canCascade = relation.type === RelationType.MANY_TO_ONE ||
        relation.type === RelationType.ONE_TO_MANY ||
        relation.type === RelationType.MANY_TO_MANY ||
        isSourceOneToOne ||
        isTargetOneToOne
      if (!canCascade) {
        continue
      }
      if (entityData.hasRelated(relation.propertyName)) {
        return true
      }
    }
    return false
  }

  private isCascadeEnabledForOperation(cascade: CascadeSetting | null, operation: CascadeOperation): boolean {
    if (cascade === null || cascade === undefined) {
      return false
    }
    if (cascade === true) {
      return true
    }
    if (typeof cascade !== 'object') {
      return false
    }
    if (operation === 'insert') {
      return cascade.insert === true
    }
    return cascade.update === true
  }

  private nextSavepointName(prefix: string): string {
    CrudOperations.savepointCounter += 1
    return `ocorm_${prefix}_${CrudOperations.savepointCounter}`
  }

  private async beginSavepointOrThrow(
    store: relationalStore.RdbStore,
    prefix: string
  ): Promise<SavepointState> {
    const executor = this.getSavepointExecutor(store)
    const savepointName = this.nextSavepointName(prefix)
    if (executor === null) {
      throw new ExecutionError('SAVEPOINT', '当前数据库不支持 SAVEPOINT，无法保证级联保存原子性')
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

}
