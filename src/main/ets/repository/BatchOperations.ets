import { relationalStore } from '@kit.ArkData'
import { HooksProcessor } from '../core/HooksProcessor'
import { DataMapper } from '../mapping/DataMapper'
import { EntityData } from '../mapping/EntityData'
import { Logger } from '../logging/Logger'
import { QueryCache } from '../query/QueryCache'
import { EntityValidator } from '../validation/EntityValidator'
import { ValidationError, UniqueValidationError } from '../errors/ValidationError'
import { ValidationMetadataStorage, ValidationRule } from '../validation/ValidationMetadataStorage'
import { ValueType } from '../types/ValueTypes'
import { BatchInsertResult } from './BatchInsertResult'
import { BatchInsertOptions } from './BatchInsertOptions'
import { SaveResult } from './SaveResult'
type StoreProvider = () => relationalStore.RdbStore
type SaveAction = (entityData: EntityData) => Promise<SaveResult>
export class BatchOperations {
  private entityName: string
  private tableName: string
  private dataMapper: DataMapper
  private hooksProcessor: HooksProcessor
  private logger: Logger
  private queryCache: QueryCache
  private getStore: StoreProvider
  private saveOne: SaveAction
  constructor(
    entityName: string,
    tableName: string,
    dataMapper: DataMapper,
    hooksProcessor: HooksProcessor,
    logger: Logger,
    queryCache: QueryCache,
    getStore: StoreProvider,
    saveOne: SaveAction
  ) {
    this.entityName = entityName
    this.tableName = tableName
    this.dataMapper = dataMapper
    this.hooksProcessor = hooksProcessor
    this.logger = logger
    this.queryCache = queryCache
    this.getStore = getStore
    this.saveOne = saveOne
  }
  async saveAll(entities: Array<EntityData>): Promise<Array<SaveResult>> {
    const results: Array<SaveResult> = []
    for (let i = 0; i < entities.length; i++) {
      const result = await this.saveOne(entities[i])
      results.push(result)
    }
    return results
  }
  async batchInsert(entities: Array<EntityData>, options: BatchInsertOptions = BatchInsertOptions.createDefault()): Promise<BatchInsertResult> {
    const startTime = Date.now()
    const totalCount = entities.length
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
    if (options.executeValidation) {
      const batchUniqueKeys: Set<string> = new Set()
      for (let i = 0; i < entities.length; i++) {
        try {
          EntityValidator.validateOrThrow(this.entityName, entities[i])
          await this.validateUniqueConstraints(entities[i], batchUniqueKeys)
        } catch (error) {
          if (error instanceof ValidationError) {
            this.logger.logWarn(`[W_BATCH_VALIDATION] 批量插入验证失败 (索引 ${i}): ${error.message}`)
            return BatchInsertResult.createFailure(`验证失败 (索引 ${i}): ${error.message}`, [i])
          }
          const errorMessage = error instanceof Error ? error.message : String(error)
          this.logger.logWarn(`[W_BATCH_VALIDATION] 批量插入验证失败 (索引 ${i}): ${errorMessage}`)
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
          return BatchInsertResult.createFailure(`beforeSave 钩子执行失败 (索引 ${i}): ${errorMessage}`, [i])
        }
      }
    }
    const valueBuckets: Array<relationalStore.ValuesBucket> = []
    for (let i = 0; i < entities.length; i++) {
      try {
        const valuesBucket = this.dataMapper.toValuesBucket(entities[i], false)
        const rdbValuesBucket: relationalStore.ValuesBucket = {}
        const keys = valuesBucket.keys()
        for (let j = 0; j < keys.length; j++) {
          const key = keys[j]
          rdbValuesBucket[key] = valuesBucket.get(key)
        }
        valueBuckets.push(rdbValuesBucket)
      } catch (error) {
        const errorMessage = error instanceof Error ? error.message : String(error)
        this.logger.logError(`批量插入数据转换失败 (索引 ${i}): ${errorMessage}`)
        return BatchInsertResult.createFailure(`数据转换失败 (索引 ${i}): ${errorMessage}`, [i])
      }
    }
    try {
      let insertedCount = 0
      if (options.useTransaction) {
        store.beginTransaction()
        this.logger.logTransaction('BEGIN (batchInsert)')
        try {
          insertedCount = await store.batchInsert(this.tableName, valueBuckets)
          store.commit()
          this.logger.logTransaction('COMMIT (batchInsert)')
        } catch (insertError) {
          store.rollBack()
          this.logger.logTransaction('ROLLBACK (batchInsert)')
          if (insertError instanceof Error) {
            throw insertError
          }
          throw new Error(`批量插入失败: ${String(insertError)}`)
        }
      } else {
        insertedCount = await store.batchInsert(this.tableName, valueBuckets)
      }
      const duration = Date.now() - startTime
      this.logger.logQuery(`BATCH INSERT INTO ${this.tableName} (${insertedCount}/${totalCount} 条)`, duration)
      if (insertedCount > 0) {
        this.queryCache.invalidateEntity(this.entityName)
      }
      if (insertedCount === totalCount) {
        return BatchInsertResult.createSuccess(insertedCount, totalCount)
      }
      return BatchInsertResult.createPartialSuccess(
        insertedCount,
        totalCount,
        [],
        `部分插入失败: ${totalCount - insertedCount} 条记录未能插入`
      )
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      if (this.isExpectedReadOnlyWriteDenied(errorMessage)) {
        this.logger.logWarn(`[W_TX_READONLY_WRITE_DENIED] 批量插入执行失败: ${errorMessage}`)
      } else {
        this.logger.logError(`批量插入执行失败: ${errorMessage}`)
      }
      return BatchInsertResult.createFailure(`批量插入执行失败: ${errorMessage}`)
    }
  }

  private async validateUniqueConstraints(entityData: EntityData, batchKeys: Set<string>): Promise<void> {
    const rules = ValidationMetadataStorage.getInstance().getRules(this.entityName)
    const propertyNames = this.collectUniquePropertyNames(rules)
    if (propertyNames.length === 0) {
      return
    }
    for (let i = 0; i < propertyNames.length; i++) {
      const propertyName = propertyNames[i]
      await this.ensureUniqueValue(entityData, propertyName, batchKeys)
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
    const metadata = this.dataMapper.getMetadata()
    for (let i = 0; i < metadata.columns.length; i++) {
      const column = metadata.columns[i]
      if (column.isUnique && !names.includes(column.propertyName)) {
        names.push(column.propertyName)
      }
    }
    return names
  }

  private async ensureUniqueValue(entityData: EntityData, propertyName: string, batchKeys: Set<string>): Promise<void> {
    const value = entityData.getPropertyValue(propertyName)
    if (value === null || value === undefined) {
      return
    }
    const metadata = this.dataMapper.getMetadata()
    const column = metadata.getColumnByProperty(propertyName)
    if (column === null) {
      return
    }
    const localBatchKey = `${column.columnName}\x00${String(value)}`
    if (batchKeys.has(localBatchKey)) {
      throw new UniqueValidationError(this.entityName, column.columnName)
    }
    batchKeys.add(localBatchKey)

    const store = this.getStore()
    const predicates = new relationalStore.RdbPredicates(this.tableName)
    predicates.equalTo(column.columnName, this.toRdbValue(value))
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

  private toRdbValue(value: ValueType): relationalStore.ValueType {
    if (value === null || value === undefined) {
      return null
    }
    if (typeof value === 'boolean') {
      return value ? 1 : 0
    }
    if (value instanceof Date) {
      return value.getTime()
    }
    if (typeof value === 'string' || typeof value === 'number' || value instanceof Uint8Array) {
      return value
    }
    return null
  }

  private isExpectedReadOnlyWriteDenied(errorMessage: string): boolean {
    const normalized = errorMessage.toLowerCase()
    return normalized.includes('readonly database') ||
      normalized.includes('read-only') ||
      normalized.includes('attempt to write a readonly database') ||
      normalized.includes('query_only') ||
      errorMessage.includes('只读')
  }
}
