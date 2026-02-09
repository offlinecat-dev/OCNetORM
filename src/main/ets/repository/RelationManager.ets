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

export class RelationManager {
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

  async attach(sourceId: number, targetId: number, relationName: string): Promise<SaveResult> {
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
        const checkPredicates = new relationalStore.RdbPredicates(relation.joinTable)
        checkPredicates.equalTo(relation.joinSourceKey, sourceId)
        checkPredicates.and()
        checkPredicates.equalTo(relation.joinTargetKey, targetId)
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
        rdbValuesBucket[relation.joinSourceKey] = sourceId
        rdbValuesBucket[relation.joinTargetKey] = targetId
        const rowId = await store.insert(relation.joinTable, rdbValuesBucket)
        store.commit()
        committed = true
        this.logger.logTransaction('COMMIT (attach)')
        const duration = Date.now() - startTime
        this.logger.logQuery(`INSERT INTO ${relation.joinTable} (${relation.joinSourceKey}=${sourceId}, ${relation.joinTargetKey}=${targetId})`, duration)
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
      this.logger.logError(`ATTACH 失败: ${errorMessage}`)
      return SaveResult.createFailure(errorMessage)
    }
  }

  async detach(sourceId: number, targetId: number, relationName: string): Promise<DeleteResult> {
    const startTime = Date.now()
    try {
      const relation = MetadataStorage.getInstance().getManyToManyRelation(this.entityName, relationName)
      if (relation === null) {
        throw new RelationNotFoundError(this.entityName, relationName)
      }
      const store = this.getStore()
      const predicates = new relationalStore.RdbPredicates(relation.joinTable)
      predicates.equalTo(relation.joinSourceKey, sourceId)
      predicates.and()
      predicates.equalTo(relation.joinTargetKey, targetId)
      const affectedRows = await store.delete(predicates)
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

  async sync(sourceId: ValueType, targetIds: Array<ValueType>, relationName: string): Promise<SaveResult> {
    const startTime = Date.now()
    try {
      const relation = MetadataStorage.getInstance().getManyToManyRelation(this.entityName, relationName)
      if (relation === null) {
        throw new RelationNotFoundError(this.entityName, relationName)
      }
      const store = this.getStore()
      store.beginTransaction()
      this.logger.logTransaction('BEGIN (sync)')
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
        store.commit()
        this.logger.logTransaction('COMMIT (sync)')
        const duration = Date.now() - startTime
        this.logger.logQuery(`SYNC ${relation.joinTable}: 删除 ${deletedCount} 条, 插入 ${insertedCount} 条`, duration)
        return SaveResult.createSuccess(insertedCount)
      } catch (syncError) {
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

  private isUniqueConstraintError(message: string): boolean {
    const upper = message.toUpperCase()
    return upper.includes('UNIQUE') || upper.includes('PRIMARY KEY')
  }
}
