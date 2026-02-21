import { relationalStore } from '@kit.ArkData'
import { MetadataStorage } from '../core/MetadataStorage'
import { Logger } from '../logging/Logger'
import { ValueType } from '../types/ValueTypes'
import { RelationNotFoundError } from '../errors/RelationError'
import { SaveResult } from './SaveResult'
import { DeleteResult } from './DeleteResult'

type StoreProvider = () => relationalStore.RdbStore
type ValueConverter = (value: ValueType) => relationalStore.ValueType
type ResultSetCloser = (resultSet: relationalStore.ResultSet | null) => void

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

export class RelationManager {
  private static savepointCounter: number = 0
  private entityName: string
  private logger: Logger
  private getStore: StoreProvider
  private toRdbValue: ValueConverter
  private closeResultSet: ResultSetCloser

  constructor(
    entityName: string,
    logger: Logger,
    getStore: StoreProvider,
    toRdbValue: ValueConverter,
    closeResultSet: ResultSetCloser
  ) {
    this.entityName = entityName
    this.logger = logger
    this.getStore = getStore
    this.toRdbValue = toRdbValue
    this.closeResultSet = closeResultSet
  }

  async attach(sourceId: ValueType, targetId: ValueType, relationName: string): Promise<SaveResult> {
    const startTime = Date.now()
    try {
      const relation = MetadataStorage.getInstance().getManyToManyRelation(this.entityName, relationName)
      if (relation === null) {
        throw new RelationNotFoundError(this.entityName, relationName)
      }
      const store = this.getStore()
      let committed = false
      store.beginTransaction()
      this.logger.logTransaction('BEGIN (attach)')
      try {
        const sourceRdbValue = this.toRdbValue(sourceId)
        const targetRdbValue = this.toRdbValue(targetId)
        const checkPredicates = new relationalStore.RdbPredicates(relation.joinTable)
        checkPredicates.equalTo(relation.joinSourceKey, sourceRdbValue)
        checkPredicates.and()
        checkPredicates.equalTo(relation.joinTargetKey, targetRdbValue)
        let checkResult: relationalStore.ResultSet | null = null
        try {
          checkResult = await store.query(checkPredicates)
          if (checkResult.rowCount > 0) {
            store.commit()
            committed = true
            this.logger.logTransaction('COMMIT (attach)')
            return SaveResult.createSuccess(0)
          }
        } finally {
          this.closeResultSet(checkResult)
        }
        const rdbValuesBucket: relationalStore.ValuesBucket = {}
        rdbValuesBucket[relation.joinSourceKey] = sourceRdbValue
        rdbValuesBucket[relation.joinTargetKey] = targetRdbValue
        const rowId = await store.insert(relation.joinTable, rdbValuesBucket)
        store.commit()
        committed = true
        this.logger.logTransaction('COMMIT (attach)')
        const duration = Date.now() - startTime
        this.logger.logQuery(
          `INSERT INTO ${relation.joinTable} (${relation.joinSourceKey}=${sourceRdbValue}, ${relation.joinTargetKey}=${targetRdbValue})`,
          duration
        )
        return SaveResult.createSuccess(1, rowId)
      } catch (attachError) {
        const attachErrorMessage = attachError instanceof Error ? attachError.message : String(attachError)
        if (!committed) {
          store.rollBack()
          this.logger.logTransaction('ROLLBACK (attach)')
        }
        if (this.isUniqueConstraintError(attachErrorMessage)) {
          return SaveResult.createSuccess(0)
        }
        throw new Error(attachErrorMessage)
      }
    } catch (error) {
      if (error instanceof RelationNotFoundError) {
        throw error
      }
      const errorMessage = error instanceof Error ? error.message : String(error)
      this.logWriteFailure('ATTACH', errorMessage)
      return SaveResult.createFailure(errorMessage)
    }
  }

  async detach(sourceId: ValueType, targetId: ValueType, relationName: string): Promise<DeleteResult> {
    const startTime = Date.now()
    try {
      const relation = MetadataStorage.getInstance().getManyToManyRelation(this.entityName, relationName)
      if (relation === null) {
        throw new RelationNotFoundError(this.entityName, relationName)
      }
      const store = this.getStore()
      const sourceRdbValue = this.toRdbValue(sourceId)
      const targetRdbValue = this.toRdbValue(targetId)
      const predicates = new relationalStore.RdbPredicates(relation.joinTable)
      predicates.equalTo(relation.joinSourceKey, sourceRdbValue)
      predicates.and()
      predicates.equalTo(relation.joinTargetKey, targetRdbValue)
      const affectedRows = await store.delete(predicates)
      const duration = Date.now() - startTime
      this.logger.logQuery(
        `DELETE FROM ${relation.joinTable} WHERE ${relation.joinSourceKey}=${sourceRdbValue} AND ${relation.joinTargetKey}=${targetRdbValue}`,
        duration
      )
      return DeleteResult.createSuccess(affectedRows)
    } catch (error) {
      if (error instanceof RelationNotFoundError) {
        throw error
      }
      const errorMessage = error instanceof Error ? error.message : String(error)
      this.logWriteFailure('DETACH', errorMessage)
      return DeleteResult.createFailure(errorMessage)
    }
  }

  async sync(sourceId: ValueType, targetIds: Array<ValueType>, relationName: string): Promise<SaveResult> {
    const startTime = Date.now()
    try {
      const relation = MetadataStorage.getInstance().getManyToManyRelation(this.entityName, relationName)
      if (relation === null) {
        throw new RelationNotFoundError(this.entityName, relationName)
      }
      const store = this.getStore()
      const savepoint = await this.beginSavepointIfPossible(store, 'sync')
      let transactionStarted = false
      if (!savepoint.started) {
        store.beginTransaction()
        transactionStarted = true
        this.logger.logTransaction('BEGIN (sync)')
      }
      try {
        const deletePredicates = new relationalStore.RdbPredicates(relation.joinTable)
        deletePredicates.equalTo(relation.joinSourceKey, this.toRdbValue(sourceId))
        const deletedCount = await store.delete(deletePredicates)
        let insertedCount = 0
        for (let i = 0; i < targetIds.length; i++) {
          const targetId = targetIds[i]
          const rdbValuesBucket: relationalStore.ValuesBucket = {}
          rdbValuesBucket[relation.joinSourceKey] = this.toRdbValue(sourceId)
          rdbValuesBucket[relation.joinTargetKey] = this.toRdbValue(targetId)
          await store.insert(relation.joinTable, rdbValuesBucket)
          insertedCount++
        }
        if (savepoint.started) {
          await this.releaseSavepoint(store, savepoint.name)
        } else {
          store.commit()
          this.logger.logTransaction('COMMIT (sync)')
        }
        const duration = Date.now() - startTime
        this.logger.logQuery(`SYNC ${relation.joinTable}: 删除 ${deletedCount} 条, 插入 ${insertedCount} 条`, duration)
        return SaveResult.createSuccess(insertedCount)
      } catch (syncError) {
        if (savepoint.started) {
          await this.rollbackToSavepoint(store, savepoint.name)
        } else if (transactionStarted) {
          store.rollBack()
          this.logger.logTransaction('ROLLBACK (sync)')
        }
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
      this.logWriteFailure('SYNC', errorMessage)
      return SaveResult.createFailure(errorMessage)
    }
  }

  private nextSavepointName(prefix: string): string {
    RelationManager.savepointCounter += 1
    return `ocorm_${prefix}_${RelationManager.savepointCounter}`
  }

  private async beginSavepointIfPossible(store: relationalStore.RdbStore, prefix: string): Promise<SavepointState> {
    const executor = this.getSavepointExecutor(store)
    const savepointName = this.nextSavepointName(prefix)
    if (executor === null) {
      return new SavepointState(savepointName, false)
    }
    try {
      await executor.executeSql(`SAVEPOINT ${savepointName}`)
      return new SavepointState(savepointName, true)
    } catch (e) {
      const message = e instanceof Error ? e.message : String(e)
      this.logger.logWarn(`SYNC 无法使用 SAVEPOINT，回退事务模式: ${message}`)
      return new SavepointState(savepointName, false)
    }
  }

  private getSavepointExecutor(store: relationalStore.RdbStore): SavepointExecutor | null {
    const executor = store as SavepointExecutor
    if (typeof executor.executeSql !== 'function') {
      return null
    }
    return executor
  }

  private async releaseSavepoint(store: relationalStore.RdbStore, savepointName: string): Promise<void> {
    const executor = this.getSavepointExecutor(store)
    if (executor === null) {
      throw new Error('当前数据库不支持 SAVEPOINT，无法释放保存点')
    }
    await executor.executeSql(`RELEASE SAVEPOINT ${savepointName}`)
  }

  private async rollbackToSavepoint(store: relationalStore.RdbStore, savepointName: string): Promise<void> {
    const executor = this.getSavepointExecutor(store)
    if (executor === null) {
      throw new Error('当前数据库不支持 SAVEPOINT，无法回滚保存点')
    }
    await executor.executeSql(`ROLLBACK TO SAVEPOINT ${savepointName}`)
    await executor.executeSql(`RELEASE SAVEPOINT ${savepointName}`)
  }

  private isUniqueConstraintError(message: string): boolean {
    const upper = message.toUpperCase()
    return upper.includes('UNIQUE') || upper.includes('PRIMARY KEY')
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
