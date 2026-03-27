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
import { ResultSetUtils } from '../mapping/ResultSetUtils'
import { BatchInsertResult } from './BatchInsertResult'
import { BatchInsertOptions } from './BatchInsertOptions'
import { SaveResult } from './SaveResult'
import { TransactionManager } from './TransactionManager'
type StoreProvider = () => relationalStore.RdbStore
type SaveAction = (entityData: EntityData) => Promise<SaveResult>
type UniqueQueryObserver = (propertyName: string, batchSize: number) => void
type BatchTransactionObserver = () => void

interface UniqueValidationContext {
  entities: Array<EntityData>
  store: relationalStore.RdbStore
  propertyNames: Array<string>
  existingValues: Map<string, Set<string>>
  loadedProperties: Set<string>
}
export class BatchOperations {
  private static readonly IN_CLAUSE_LIMIT: number = 500
  private static uniqueQueryObserverForTest: UniqueQueryObserver | null = null
  private static localTransactionObserverForTest: BatchTransactionObserver | null = null
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

  static setUniqueQueryObserverForTest(observer: UniqueQueryObserver | null): void {
    BatchOperations.uniqueQueryObserverForTest = observer
  }

  static resetTestHooks(): void {
    BatchOperations.uniqueQueryObserverForTest = null
    BatchOperations.localTransactionObserverForTest = null
  }

  private static notifyUniqueQueryObserverForTest(propertyName: string, batchSize: number): void {
    const observer = BatchOperations.uniqueQueryObserverForTest
    if (observer !== null) {
      observer(propertyName, batchSize)
    }
  }

  static setLocalTransactionObserverForTest(observer: (() => void) | null): void {
    BatchOperations.localTransactionObserverForTest = observer
  }

  private static notifyLocalTransactionObserverForTest(): void {
    const observer = BatchOperations.localTransactionObserverForTest
    if (observer !== null) {
      observer()
    }
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
      const uniqueContext = this.createUniqueValidationContext(entities, store)
      const batchUniqueKeys: Set<string> = new Set()
      for (let i = 0; i < entities.length; i++) {
        try {
          EntityValidator.validateOrThrow(this.entityName, entities[i])
          await this.validateUniqueConstraints(entities[i], batchUniqueKeys, uniqueContext)
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
      const useLocalTransaction = options.useTransaction && !TransactionManager.isConnectionTransactionActive(store)
      if (useLocalTransaction) {
        BatchOperations.notifyLocalTransactionObserverForTest()
        store.beginTransaction()
        this.logger.logTransaction('BEGIN (batchInsert)')
        try {
          insertedCount = await store.batchInsert(this.tableName, valueBuckets)
          insertedCount = this.normalizeBatchInsertCount(insertedCount, totalCount)
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
        insertedCount = this.normalizeBatchInsertCount(insertedCount, totalCount)
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

  private normalizeBatchInsertCount(insertedCount: number, totalCount: number): number {
    if (insertedCount < 0) {
      this.logger.logWarn(
        `[W_BATCH_INSERT_COUNT_NEGATIVE] batchInsert 返回负数(${insertedCount})，按全部成功(${totalCount})处理`
      )
      return totalCount
    }
    if (insertedCount > totalCount) {
      this.logger.logWarn(
        `[W_BATCH_INSERT_COUNT_OVERFLOW] batchInsert 返回值(${insertedCount})超过请求数量(${totalCount})，按请求数量处理`
      )
      return totalCount
    }
    return insertedCount
  }

  private async validateUniqueConstraints(
    entityData: EntityData,
    batchKeys: Set<string>,
    context: UniqueValidationContext | null
  ): Promise<void> {
    if (context === null) {
      return
    }
    for (let i = 0; i < context.propertyNames.length; i++) {
      const propertyName = context.propertyNames[i]
      await this.ensureUniqueValue(entityData, propertyName, batchKeys, context)
    }
  }

  private createUniqueValidationContext(
    entities: Array<EntityData>,
    store: relationalStore.RdbStore
  ): UniqueValidationContext | null {
    const rules = ValidationMetadataStorage.getInstance().getRules(this.entityName)
    const propertyNames = this.collectUniquePropertyNames(rules)
    if (propertyNames.length === 0) {
      return null
    }
    return {
      entities,
      store,
      propertyNames,
      existingValues: new Map(),
      loadedProperties: new Set()
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

  private async ensureUniqueValue(
    entityData: EntityData,
    propertyName: string,
    batchKeys: Set<string>,
    context: UniqueValidationContext | null = null
  ): Promise<void> {
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

    if (context !== null) {
      const existingValues = await this.ensureExistingValuesLoaded(propertyName, context)
      const rdbValue = this.toRdbValue(value)
      const rdbKey = this.toRdbKey(rdbValue)
      if (rdbKey !== null && existingValues.has(rdbKey)) {
        throw new UniqueValidationError(this.entityName, column.columnName)
      }
      return
    }

    const store = this.getStore()
    const predicates = new relationalStore.RdbPredicates(this.tableName)
    predicates.equalTo(column.columnName, this.toRdbValue(value))
    let resultSet: relationalStore.ResultSet | null = null
    try {
      resultSet = await store.query(predicates)
      if (resultSet.rowCount > 0) {
        throw new UniqueValidationError(this.entityName, column.columnName)
      }
    } catch (e) {
      if (e instanceof Error) {
        throw e
      }
      throw new Error(String(e))
    } finally {
      this.closeResultSet(resultSet)
    }
  }

  private async ensureExistingValuesLoaded(
    propertyName: string,
    context: UniqueValidationContext
  ): Promise<Set<string>> {
    if (context.loadedProperties.has(propertyName)) {
      return context.existingValues.get(propertyName) ?? new Set<string>()
    }
    const existingValues = await this.loadExistingUniqueValues(propertyName, context)
    context.existingValues.set(propertyName, existingValues)
    context.loadedProperties.add(propertyName)
    return existingValues
  }

  private async loadExistingUniqueValues(
    propertyName: string,
    context: UniqueValidationContext
  ): Promise<Set<string>> {
    const metadata = this.dataMapper.getMetadata()
    const column = metadata.getColumnByProperty(propertyName)
    if (column === null) {
      return new Set<string>()
    }

    const valueMap: Map<string, relationalStore.ValueType> = new Map()
    for (let i = 0; i < context.entities.length; i++) {
      const value = context.entities[i].getPropertyValue(propertyName)
      if (value === null || value === undefined) {
        continue
      }
      const rdbValue = this.toRdbValue(value)
      const key = this.toRdbKey(rdbValue)
      if (key === null) {
        continue
      }
      if (!valueMap.has(key)) {
        valueMap.set(key, rdbValue)
      }
    }
    if (valueMap.size === 0) {
      return new Set<string>()
    }

    const existingValues: Set<string> = new Set()
    const allValues = Array.from(valueMap.values())
    const batches = this.splitIntoBatches(allValues, this.resolveInClauseLimit())
    for (let batchIndex = 0; batchIndex < batches.length; batchIndex++) {
      const batch = batches[batchIndex]
      const predicates = new relationalStore.RdbPredicates(this.tableName)
      try {
        predicates.in(column.columnName, batch)
      } catch (e) {
        if (e instanceof Error) {
          throw e
        }
        throw new Error(String(e))
      }

      let resultSet: relationalStore.ResultSet | null = null
      try {
        BatchOperations.notifyUniqueQueryObserverForTest(propertyName, batch.length)
        resultSet = await context.store.query(predicates)
        const columnIndex = resultSet.getColumnIndex(column.columnName)
        while (resultSet.goToNextRow()) {
          if (resultSet.isColumnNull(columnIndex)) {
            continue
          }
          const rawValue = ResultSetUtils.getValueByRuntimeType(resultSet, columnIndex)
          const key = this.toRdbKey(rawValue as relationalStore.ValueType)
          if (key !== null) {
            existingValues.add(key)
          }
        }
      } catch (e) {
        if (e instanceof Error) {
          throw e
        }
        throw new Error(String(e))
      } finally {
        this.closeResultSet(resultSet)
      }
    }

    return existingValues
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

  private toRdbKey(value: relationalStore.ValueType | null): string | null {
    if (value === null || value === undefined) {
      return null
    }
    if (value instanceof Uint8Array) {
      const parts: Array<string> = []
      for (let i = 0; i < value.length; i++) {
        parts.push(value[i].toString(16).padStart(2, '0'))
      }
      return `u8:${parts.join('')}`
    }
    return `${typeof value}:${String(value)}`
  }

  private resolveInClauseLimit(): number {
    return BatchOperations.IN_CLAUSE_LIMIT
  }

  private splitIntoBatches<T>(values: Array<T>, batchSize: number): Array<Array<T>> {
    const batches: Array<Array<T>> = []
    const effectiveSize = batchSize > 0 ? Math.floor(batchSize) : 1
    for (let i = 0; i < values.length; i += effectiveSize) {
      const batch: Array<T> = []
      for (let j = i; j < Math.min(i + effectiveSize, values.length); j++) {
        batch.push(values[j])
      }
      batches.push(batch)
    }
    return batches
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
