import { relationalStore } from '@kit.ArkData'
import { MetadataStorage } from '../core/MetadataStorage'
import { Logger } from '../logging/Logger'
import { ValueType } from '../types/ValueTypes'
import { RelationNotFoundError } from '../errors/RelationError'
import { SaveResult } from './SaveResult'
import { DeleteResult } from './DeleteResult'
import { TransactionManager } from './TransactionManager'

type StoreProvider = () => relationalStore.RdbStore
type ValueConverter = (value: ValueType) => relationalStore.ValueType
type ResultSetCloser = (resultSet: relationalStore.ResultSet | null) => void

class WriteScopeState {
  savepointName: string
  useSavepoint: boolean
  useTransaction: boolean

  constructor(savepointName: string, useSavepoint: boolean, useTransaction: boolean) {
    this.savepointName = savepointName
    this.useSavepoint = useSavepoint
    this.useTransaction = useTransaction
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
      const scope = await this.beginWriteScope(store, 'attach')
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
            await this.completeWriteScope(store, scope, 'attach')
            return SaveResult.createSuccess(0)
          }
        } finally {
          this.closeResultSet(checkResult)
        }
        const rdbValuesBucket: relationalStore.ValuesBucket = {}
        rdbValuesBucket[relation.joinSourceKey] = sourceRdbValue
        rdbValuesBucket[relation.joinTargetKey] = targetRdbValue
        const rowId = await store.insert(relation.joinTable, rdbValuesBucket)
        await this.completeWriteScope(store, scope, 'attach')
        const duration = Date.now() - startTime
        this.logger.logQuery(
          `INSERT INTO ${relation.joinTable} (${relation.joinSourceKey}, ${relation.joinTargetKey}) VALUES (?, ?)`,
          duration
        )
        return SaveResult.createSuccess(1, rowId)
      } catch (attachError) {
        await this.rollbackWriteScope(store, scope, 'attach')
        const attachErrorMessage = attachError instanceof Error ? attachError.message : String(attachError)
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
        `DELETE FROM ${relation.joinTable} WHERE ${relation.joinSourceKey} = ? AND ${relation.joinTargetKey} = ?`,
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
      const scope = await this.beginWriteScope(store, 'sync')
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
        await this.completeWriteScope(store, scope, 'sync')
        const duration = Date.now() - startTime
        this.logger.logQuery(`SYNC ${relation.joinTable}: 删除 ${deletedCount} 条, 插入 ${insertedCount} 条`, duration)
        return SaveResult.createSuccess(insertedCount)
      } catch (syncError) {
        await this.rollbackWriteScope(store, scope, 'sync')
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

  private async beginWriteScope(store: relationalStore.RdbStore, prefix: string): Promise<WriteScopeState> {
    const savepointName = this.nextSavepointName(prefix)
    try {
      await store.executeSql(`SAVEPOINT ${savepointName}`)
      return new WriteScopeState(savepointName, true, false)
    } catch (e) {
      const message = e instanceof Error ? e.message : String(e)
      return this.beginFallbackTransactionOrThrow(store, prefix, savepointName, `创建 SAVEPOINT 失败: ${message}`)
    }
  }

  private beginFallbackTransactionOrThrow(
    store: relationalStore.RdbStore,
    prefix: string,
    savepointName: string,
    reason: string
  ): WriteScopeState {
    if (TransactionManager.isConnectionTransactionActive(store)) {
      throw new Error(`${reason}，且当前已在事务中，无法回退 beginTransaction`)
    }
    try {
      store.beginTransaction()
    } catch (e) {
      if (e instanceof Error) {
        throw e
      }
      throw new Error(String(e))
    }
    TransactionManager.markExternalTransactionBegin(store)
    this.logger.logTransaction(`BEGIN (${prefix})`)
    return new WriteScopeState(savepointName, false, true)
  }

  private async completeWriteScope(
    store: relationalStore.RdbStore,
    scope: WriteScopeState,
    prefix: string
  ): Promise<void> {
    if (scope.useSavepoint) {
      await this.releaseSavepoint(store, scope.savepointName)
      return
    }
    if (!scope.useTransaction) {
      return
    }
    try {
      store.commit()
      this.logger.logTransaction(`COMMIT (${prefix})`)
    } catch (e) {
      if (e instanceof Error) {
        throw e
      }
      throw new Error(String(e))
    } finally {
      TransactionManager.markExternalTransactionEnd(store)
    }
  }

  private async rollbackWriteScope(
    store: relationalStore.RdbStore,
    scope: WriteScopeState,
    prefix: string
  ): Promise<void> {
    if (scope.useSavepoint) {
      await this.rollbackToSavepoint(store, scope.savepointName)
      return
    }
    if (!scope.useTransaction) {
      return
    }
    try {
      store.rollBack()
      this.logger.logTransaction(`ROLLBACK (${prefix})`)
    } catch (e) {
      if (e instanceof Error) {
        throw e
      }
      throw new Error(String(e))
    } finally {
      TransactionManager.markExternalTransactionEnd(store)
    }
  }

  private async releaseSavepoint(store: relationalStore.RdbStore, savepointName: string): Promise<void> {
    await store.executeSql(`RELEASE SAVEPOINT ${savepointName}`)
  }

  private async rollbackToSavepoint(store: relationalStore.RdbStore, savepointName: string): Promise<void> {
    await store.executeSql(`ROLLBACK TO SAVEPOINT ${savepointName}`)
    await store.executeSql(`RELEASE SAVEPOINT ${savepointName}`)
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
