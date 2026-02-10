import { relationalStore } from '@kit.ArkData'
import { Logger } from '../logging/Logger'
import { TransactionRollbackError } from '../errors/TransactionError'
import { IsolationLevel, TransactionOptions } from './TransactionOptions'
import { TransactionResult } from './TransactionResult'

class TimeoutState {
  timedOut: boolean = false
  commitStarted: boolean = false
  finished: boolean = false
}

type StoreProvider = () => relationalStore.RdbStore
type TransactionAction = () => Promise<void>

export class TransactionManager {
  private logger: Logger
  private getStore: StoreProvider

  constructor(logger: Logger, getStore: StoreProvider) {
    this.logger = logger
    this.getStore = getStore
  }

  async transaction(action: TransactionAction): Promise<TransactionResult> {
    let store: relationalStore.RdbStore
    let committed = false
    let transactionStarted = false
    try {
      store = this.getStore()
    } catch (e) {
      const errorMessage = e instanceof Error ? e.message : String(e)
      this.logger.logError(`获取数据库连接失败: ${errorMessage}`)
      throw new TransactionRollbackError(`获取数据库连接失败: ${errorMessage}`)
    }
    try {
      store.beginTransaction()
      transactionStarted = true
      this.logger.logTransaction('BEGIN')
      await action()
      store.commit()
      committed = true
      this.logger.logTransaction('COMMIT')
      return TransactionResult.createSuccess()
    } catch (error) {
      if (!committed && transactionStarted) {
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
    }
  }

  async transactionWithOptions(action: TransactionAction, options: TransactionOptions): Promise<TransactionResult> {
    let lastError: Error | null = null
    const maxAttempts = options.retries + 1
    for (let attempts = 1; attempts <= maxAttempts; attempts++) {
      let timeoutId: number = 0
      let isTimedOut = false
      const timeoutState = new TimeoutState()
      try {
        return await new Promise<TransactionResult>((resolve, reject) => {
          timeoutId = setTimeout(() => {
            if (timeoutState.finished || timeoutState.commitStarted) {
              return
            }
            isTimedOut = true
            timeoutState.timedOut = true
            reject(new Error(`事务超时 (${options.timeout}ms)`))
          }, options.timeout)
          this.executeTransactionWithOptions(action, options, timeoutState)
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
        })
      } catch (error) {
        if (timeoutId !== 0) {
          clearTimeout(timeoutId)
        }
        lastError = error instanceof Error ? error : new Error(String(error))
        if (isTimedOut) {
          this.logger.logError(`事务超时，停止重试: ${lastError.message}`)
          break
        }
        if (attempts < maxAttempts) {
          this.logger.logInfo(`事务执行失败，${options.retryDelay}ms 后重试 (${attempts}/${maxAttempts})`)
          await this.delay(options.retryDelay)
        }
      }
    }
    const errorMessage = lastError ? lastError.message : '事务执行失败'
    this.logger.logError(`事务执行失败，已重试 ${options.retries} 次: ${errorMessage}`)
    throw new TransactionRollbackError(errorMessage)
  }

  private async executeTransactionWithOptions(
    action: TransactionAction,
    options: TransactionOptions,
    timeoutState?: TimeoutState
  ): Promise<TransactionResult> {
    let store: relationalStore.RdbStore
    let committed = false
    let transactionStarted = false
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
      isolationApplied = await this.applyIsolationLevel(store, options.isolation)
      store.beginTransaction()
      transactionStarted = true
      this.logger.logTransaction(options.readOnly ? 'BEGIN (READ ONLY)' : 'BEGIN')
      if (options.readOnly) {
        readOnlyApplied = await this.applyReadOnlyMode(store, true)
      }
      if (timeoutState?.timedOut) {
        throw new TransactionRollbackError(`事务超时 (${options.timeout}ms)`)
      }
      await action()
      if (timeoutState?.timedOut) {
        throw new TransactionRollbackError(`事务超时 (${options.timeout}ms)`)
      }
      if (timeoutState) {
        timeoutState.commitStarted = true
      }
      store.commit()
      committed = true
      this.logger.logTransaction('COMMIT')
      return TransactionResult.createSuccess()
    } catch (error) {
      if (!committed && transactionStarted) {
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
      await this.resetTransactionOptions(store, isolationApplied, readOnlyApplied)
    }
  }

  private async applyIsolationLevel(store: relationalStore.RdbStore, isolation: IsolationLevel): Promise<boolean> {
    try {
      await store.executeSql(isolation === IsolationLevel.READ_UNCOMMITTED ? 'PRAGMA read_uncommitted = 1' : 'PRAGMA read_uncommitted = 0')
      return true
    } catch (e) {
      const errorMessage = e instanceof Error ? e.message : String(e)
      this.logger.logError(`设置事务隔离级别失败，已降级为兼容模式: ${errorMessage}`)
      return false
    }
  }

  private async applyReadOnlyMode(store: relationalStore.RdbStore, readOnly: boolean): Promise<boolean> {
    try {
      await store.executeSql(readOnly ? 'PRAGMA query_only = 1' : 'PRAGMA query_only = 0')
      return true
    } catch (e) {
      const errorMessage = e instanceof Error ? e.message : String(e)
      this.logger.logError(`设置事务只读模式失败，已降级为兼容模式: ${errorMessage}`)
      return false
    }
  }

  private async resetTransactionOptions(
    store: relationalStore.RdbStore,
    isolationApplied: boolean,
    readOnlyApplied: boolean
  ): Promise<void> {
    if (readOnlyApplied) {
      const restored = await this.applyReadOnlyMode(store, false)
      if (!restored) {
        this.logger.logError('恢复事务只读模式失败')
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

  private delay(ms: number): Promise<void> {
    return new Promise<void>((resolve) => setTimeout(() => resolve(), ms))
  }
}
