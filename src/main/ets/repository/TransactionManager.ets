import { relationalStore } from '@kit.ArkData'
import { Logger } from '../logging/Logger'
import { TransactionRollbackError } from '../errors/TransactionError'
import { IsolationLevel, TransactionOptions } from './TransactionOptions'
import { TransactionResult } from './TransactionResult'
import { StoreLease } from '../database/pool/StoreLease'

class TimeoutState {
  timedOut: boolean = false
  commitStarted: boolean = false
  finished: boolean = false
}

class TransactionTimeoutPendingError extends Error {
  pendingCleanup: Promise<void>
  maxCleanupWaitMs: number

  constructor(message: string, pendingCleanup: Promise<void>, maxCleanupWaitMs: number) {
    super(message)
    this.name = 'TransactionTimeoutPendingError'
    this.pendingCleanup = pendingCleanup
    this.maxCleanupWaitMs = maxCleanupWaitMs
  }
}

class ConnectionTransactionLock {
  tail: Promise<void> = Promise.resolve()
}

class PragmaCapabilityState {
  readUncommittedSupported: boolean | null = null
  queryOnlySupported: boolean | null = null
}

type StoreProvider = () => relationalStore.RdbStore
type StoreLeaseProvider = () => Promise<StoreLease>
type TransactionAction = (store: relationalStore.RdbStore) => Promise<void>
export class TransactionManager {
  private static connectionLocks: WeakMap<relationalStore.RdbStore, ConnectionTransactionLock> = new WeakMap()
  private static pragmaCapabilities: WeakMap<relationalStore.RdbStore, PragmaCapabilityState> = new WeakMap()
  private static activeTransactions: WeakMap<relationalStore.RdbStore, number> = new WeakMap()
  private static activeTransactionCount: number = 0
  private static pendingCleanupCount: number = 0
  private static beginObserverForTest: (() => void) | null = null
  private static transactionPhaseObserverForTest: ((phase: string) => void) | null = null
  private static readOnlyModeObserverForTest: ((readOnly: boolean) => void) | null = null
  private static forcedIsolationLevelErrorForTest: string = ''
  private static forcedReadOnlyModeErrorForTest: string = ''
  private logger: Logger
  private getStore: StoreProvider
  private acquireStoreLease: StoreLeaseProvider | null

  constructor(logger: Logger, getStore: StoreProvider, acquireStoreLease?: StoreLeaseProvider) {
    this.logger = logger
    this.getStore = getStore
    this.acquireStoreLease = acquireStoreLease !== undefined ? acquireStoreLease : null
  }

  static setBeginObserverForTest(observer: (() => void) | null): void {
    TransactionManager.beginObserverForTest = observer
  }

  static setTransactionPhaseObserverForTest(observer: ((phase: string) => void) | null): void {
    TransactionManager.transactionPhaseObserverForTest = observer
  }

  static setReadOnlyModeObserverForTest(observer: ((readOnly: boolean) => void) | null): void {
    TransactionManager.readOnlyModeObserverForTest = observer
  }

  static setForcedIsolationLevelErrorForTest(message: string | null): void {
    TransactionManager.forcedIsolationLevelErrorForTest = message !== null ? message : ''
  }

  static setForcedReadOnlyModeErrorForTest(message: string | null): void {
    TransactionManager.forcedReadOnlyModeErrorForTest = message !== null ? message : ''
  }

  static resetTestHooks(): void {
    TransactionManager.beginObserverForTest = null
    TransactionManager.transactionPhaseObserverForTest = null
    TransactionManager.readOnlyModeObserverForTest = null
    TransactionManager.forcedIsolationLevelErrorForTest = ''
    TransactionManager.forcedReadOnlyModeErrorForTest = ''
    TransactionManager.connectionLocks = new WeakMap()
    TransactionManager.pragmaCapabilities = new WeakMap()
    TransactionManager.activeTransactions = new WeakMap()
    TransactionManager.activeTransactionCount = 0
    TransactionManager.pendingCleanupCount = 0
  }

  private static notifyBeginObserverForTest(): void {
    const observer = TransactionManager.beginObserverForTest
    if (observer !== null) {
      observer()
    }
  }

  private static notifyTransactionPhaseObserverForTest(phase: string): void {
    const observer = TransactionManager.transactionPhaseObserverForTest
    if (observer !== null) {
      observer(phase)
    }
  }

  private static notifyReadOnlyModeObserverForTest(readOnly: boolean): void {
    const observer = TransactionManager.readOnlyModeObserverForTest
    if (observer !== null) {
      observer(readOnly)
    }
  }

  private getPragmaCapabilityState(store: relationalStore.RdbStore): PragmaCapabilityState {
    const existing = TransactionManager.pragmaCapabilities.get(store)
    if (existing !== undefined) {
      return existing
    }
    const created = new PragmaCapabilityState()
    TransactionManager.pragmaCapabilities.set(store, created)
    return created
  }

  private async acquireTransactionLock(store: relationalStore.RdbStore): Promise<() => void> {
    const lockState = this.getConnectionLockState(store)
    let release: (() => void) | null = null
    const waitTurn = lockState.tail
    const currentTurn = new Promise<void>((resolve) => {
      release = resolve
    })
    lockState.tail = currentTurn
    await waitTurn
    return (): void => {
      if (release !== null) {
        release()
        release = null
      }
      if (lockState.tail === currentTurn) {
        lockState.tail = Promise.resolve()
      }
    }
  }

  private async acquireTransactionLeaseOrThrow(): Promise<StoreLease> {
    if (this.acquireStoreLease !== null) {
      try {
        return await this.acquireStoreLease()
      } catch (e) {
        const errorMessage = e instanceof Error ? e.message : String(e)
        this.logger.logError(`获取数据库连接失败: ${errorMessage}`)
        throw new TransactionRollbackError(`获取数据库连接失败: ${errorMessage}`)
      }
    }
    let store: relationalStore.RdbStore
    try {
      store = this.getStore()
    } catch (e) {
      const errorMessage = e instanceof Error ? e.message : String(e)
      this.logger.logError(`获取数据库连接失败: ${errorMessage}`)
      throw new TransactionRollbackError(`获取数据库连接失败: ${errorMessage}`)
    }
    return new StoreLease('tx-singleton-store', store, null)
  }

  async transaction(action: TransactionAction): Promise<TransactionResult> {
    const lease = await this.acquireTransactionLeaseOrThrow()
    let releaseLock: (() => void) | null = null
    try {
      releaseLock = await this.acquireTransactionLock(lease.store)
      return await this.transactionInternal(lease.store, action)
    } finally {
      if (releaseLock !== null) {
        releaseLock()
      }
      lease.release()
    }
  }

  private async transactionInternal(
    store: relationalStore.RdbStore,
    action: TransactionAction
  ): Promise<TransactionResult> {
    let committed = false
    let transactionStarted = false
    let managedTransactionMarked = false
    try {
      store.beginTransaction()
      transactionStarted = true
      TransactionManager.notifyBeginObserverForTest()
      TransactionManager.markManagedTransactionBegin(store)
      managedTransactionMarked = true
      TransactionManager.notifyTransactionPhaseObserverForTest('BEGIN')
      this.logger.logTransaction('BEGIN')
      await action(store)
      store.commit()
      committed = true
      TransactionManager.notifyTransactionPhaseObserverForTest('COMMIT')
      this.logger.logTransaction('COMMIT')
      return TransactionResult.createSuccess()
    } catch (error) {
      if (!committed && transactionStarted) {
        try {
          store.rollBack()
          TransactionManager.notifyTransactionPhaseObserverForTest('ROLLBACK')
          this.logger.logTransaction('ROLLBACK')
        } catch (rollbackError) {
          const rollbackMsg = rollbackError instanceof Error ? rollbackError.message : String(rollbackError)
          const originalMsg = error instanceof Error ? error.message : String(error)
          this.logger.logError(`事务回滚失败: ${rollbackMsg}`)
          throw new TransactionRollbackError(`原始错误: ${originalMsg}, 回滚错误: ${rollbackMsg}`)
        }
      }
      const errorMessage = error instanceof Error ? error.message : String(error)
      this.logTransactionFailure(errorMessage)
      if (error instanceof TransactionRollbackError) {
        throw error
      }
      throw new TransactionRollbackError(errorMessage)
    } finally {
      if (managedTransactionMarked) {
        TransactionManager.markManagedTransactionEnd(store)
      }
    }
  }

  async transactionWithOptions(action: TransactionAction, options: TransactionOptions): Promise<TransactionResult> {
    const lease = await this.acquireTransactionLeaseOrThrow()
    let releaseLock: (() => void) | null = null
    let releaseHandledByBackgroundCleanup = false
    try {
      releaseLock = await this.acquireTransactionLock(lease.store)
      return await this.transactionWithOptionsInternal(lease.store, action, options)
    } catch (error) {
      if (error instanceof TransactionTimeoutPendingError) {
        releaseHandledByBackgroundCleanup = true
        if (releaseLock !== null) {
          this.releaseResourcesWhenCleanupSettles(
            releaseLock,
            () => lease.release(),
            error.pendingCleanup,
            error.maxCleanupWaitMs
          )
        } else {
          lease.release()
        }
        throw new TransactionRollbackError(error.message)
      }
      if (error instanceof TransactionRollbackError) {
        throw error
      }
      const errorMessage = error instanceof Error ? error.message : String(error)
      throw new TransactionRollbackError(errorMessage)
    } finally {
      if (!releaseHandledByBackgroundCleanup) {
        if (releaseLock !== null) {
          releaseLock()
        }
        lease.release()
      }
    }
  }

  private async transactionWithOptionsInternal(
    store: relationalStore.RdbStore,
    action: TransactionAction,
    options: TransactionOptions
  ): Promise<TransactionResult> {
    let lastError: Error | null = null
    const maxAttempts = options.retries + 1
    for (let attempts = 1; attempts <= maxAttempts; attempts++) {
      let timeoutId: number = 0
      let isTimedOut = false
      const timeoutState = new TimeoutState()
      const executionPromise = this.executeTransactionWithOptions(store, action, options, timeoutState)
      try {
        const timeoutPromise = new Promise<TransactionResult>((_resolve, reject) => {
          timeoutId = setTimeout(() => {
            if (timeoutState.finished || timeoutState.commitStarted) {
              return
            }
            isTimedOut = true
            timeoutState.timedOut = true
            reject(new Error(`事务超时 (${options.timeout}ms)`))
          }, options.timeout)
        })
        const result = await Promise.race([executionPromise, timeoutPromise])
        if (timeoutId !== 0) {
          clearTimeout(timeoutId)
        }
        return result
      } catch (error) {
        if (timeoutId !== 0) {
          clearTimeout(timeoutId)
        }
        if (isTimedOut) {
          this.logger.logError(`事务超时，转入后台清理: ${options.timeout}ms`)
          const cleanupPromise = executionPromise.then(
            () => {
            },
            (cleanupError: Error | object | string | number | boolean | null | undefined) => {
              const cleanupMessage = cleanupError instanceof Error ? cleanupError.message : String(cleanupError)
              this.logger.logWarn(`事务超时后后台清理出现错误: ${cleanupMessage}`)
            }
          )
          TransactionManager.markCleanupPendingBegin()
          cleanupPromise.finally(() => {
            TransactionManager.markCleanupPendingEnd()
          })
          throw new TransactionTimeoutPendingError(
            `事务超时 (${options.timeout}ms)`,
            cleanupPromise,
            this.resolveCleanupWaitMs(options.timeout)
          )
        }
        lastError = error instanceof Error ? error : new Error(String(error))
        if (this.isNonRetryableConfigurationError(lastError.message)) {
          this.logger.logError(`事务配置不被支持，停止重试: ${lastError.message}`)
          break
        }
        if (attempts < maxAttempts) {
          this.logger.logInfo(`事务执行失败，${options.retryDelay}ms 后重试 (${attempts}/${maxAttempts})`)
          await this.delay(options.retryDelay)
        }
      }
    }
    const errorMessage = lastError ? lastError.message : '事务执行失败'
    this.logTransactionFailure(`已重试 ${options.retries} 次: ${errorMessage}`)
    if (lastError instanceof TransactionRollbackError) {
      throw lastError
    }
    throw new TransactionRollbackError(errorMessage)
  }

  private async executeTransactionWithOptions(
    store: relationalStore.RdbStore,
    action: TransactionAction,
    options: TransactionOptions,
    timeoutState?: TimeoutState
  ): Promise<TransactionResult> {
    let committed = false
    let transactionStarted = false
    let isolationApplied = false
    let readOnlyApplied = false
    let managedTransactionMarked = false
    try {
      isolationApplied = await this.applyIsolationLevel(store, options.isolation)
      store.beginTransaction()
      transactionStarted = true
      TransactionManager.notifyBeginObserverForTest()
      TransactionManager.markManagedTransactionBegin(store)
      managedTransactionMarked = true
      TransactionManager.notifyTransactionPhaseObserverForTest(options.readOnly ? 'BEGIN (READ ONLY)' : 'BEGIN')
      this.logger.logTransaction(options.readOnly ? 'BEGIN (READ ONLY)' : 'BEGIN')
      if (options.readOnly) {
        readOnlyApplied = await this.applyReadOnlyMode(store, true)
      }
      if (timeoutState?.timedOut) {
        throw new TransactionRollbackError(`事务超时 (${options.timeout}ms)`)
      }
      await action(store)
      if (timeoutState?.timedOut) {
        throw new TransactionRollbackError(`事务超时 (${options.timeout}ms)`)
      }
      if (timeoutState) {
        timeoutState.commitStarted = true
      }
      store.commit()
      committed = true
      TransactionManager.notifyTransactionPhaseObserverForTest('COMMIT')
      this.logger.logTransaction('COMMIT')
      return TransactionResult.createSuccess()
    } catch (error) {
      if (!committed && transactionStarted) {
        try {
          store.rollBack()
          TransactionManager.notifyTransactionPhaseObserverForTest('ROLLBACK')
          this.logger.logTransaction('ROLLBACK')
        } catch (rollbackError) {
          const rollbackMsg = rollbackError instanceof Error ? rollbackError.message : String(rollbackError)
          const originalMsg = error instanceof Error ? error.message : String(error)
          this.logger.logError(`事务回滚失败: ${rollbackMsg}`)
          throw new TransactionRollbackError(`原始错误: ${originalMsg}, 回滚错误: ${rollbackMsg}`)
        }
      }
      const errorMessage = error instanceof Error ? error.message : String(error)
      this.logTransactionFailure(errorMessage)
      if (error instanceof TransactionRollbackError) {
        throw error
      }
      throw new TransactionRollbackError(errorMessage)
    } finally {
      if (timeoutState) {
        timeoutState.finished = true
      }
      if (managedTransactionMarked) {
        TransactionManager.markManagedTransactionEnd(store)
      }
      await this.resetTransactionOptions(store, isolationApplied, readOnlyApplied)
    }
  }

  private async applyIsolationLevel(store: relationalStore.RdbStore, isolation: IsolationLevel): Promise<boolean> {
    const capability = this.getPragmaCapabilityState(store)
    let pragmaSql = ''
    if (isolation === IsolationLevel.READ_UNCOMMITTED) {
      if (capability.readUncommittedSupported === false) {
        throw new TransactionRollbackError('当前平台不支持 READ_UNCOMMITTED 隔离级别')
      }
      pragmaSql = 'PRAGMA read_uncommitted = 1'
    } else if (isolation === IsolationLevel.READ_COMMITTED) {
      if (capability.readUncommittedSupported === false) {
        this.logger.logWarn('当前平台不支持 PRAGMA read_uncommitted，按默认 READ_COMMITTED 语义继续执行')
        return false
      }
      pragmaSql = 'PRAGMA read_uncommitted = 0'
    } else {
      throw new TransactionRollbackError(`不支持的事务隔离级别: ${isolation}，当前仅支持 READ_UNCOMMITTED / READ_COMMITTED`)
    }
    try {
      if (TransactionManager.forcedIsolationLevelErrorForTest.length > 0) {
        throw new Error(TransactionManager.forcedIsolationLevelErrorForTest)
      }
      await store.executeSql(pragmaSql)
      capability.readUncommittedSupported = true
      return true
    } catch (e) {
      const errorMessage = e instanceof Error ? e.message : String(e)
      if (this.isUnsupportedPragmaError(errorMessage)) {
        capability.readUncommittedSupported = false
        if (isolation === IsolationLevel.READ_COMMITTED) {
          this.logger.logWarn(`当前平台不支持 PRAGMA read_uncommitted，按默认 READ_COMMITTED 语义继续执行: ${errorMessage}`)
          return false
        }
        throw new TransactionRollbackError(`当前平台不支持 READ_UNCOMMITTED 隔离级别: ${errorMessage}`)
      }
      throw new TransactionRollbackError(`设置事务隔离级别失败: ${errorMessage}`)
    }
  }

  private async applyReadOnlyMode(store: relationalStore.RdbStore, readOnly: boolean): Promise<boolean> {
    const capability = this.getPragmaCapabilityState(store)
    if (capability.queryOnlySupported === false) {
      if (!readOnly) {
        return false
      }
      throw new TransactionRollbackError('当前平台不支持只读事务（PRAGMA query_only）')
    }
    try {
      if (TransactionManager.forcedReadOnlyModeErrorForTest.length > 0) {
        throw new Error(TransactionManager.forcedReadOnlyModeErrorForTest)
      }
      await store.executeSql(readOnly ? 'PRAGMA query_only = 1' : 'PRAGMA query_only = 0')
      capability.queryOnlySupported = true
      TransactionManager.notifyReadOnlyModeObserverForTest(readOnly)
      return true
    } catch (e) {
      const errorMessage = e instanceof Error ? e.message : String(e)
      if (this.isUnsupportedPragmaError(errorMessage)) {
        capability.queryOnlySupported = false
        if (!readOnly) {
          return false
        }
        throw new TransactionRollbackError(`当前平台不支持只读事务（PRAGMA query_only）: ${errorMessage}`)
      }
      throw new TransactionRollbackError(`设置事务只读模式失败: ${errorMessage}`)
    }
  }

  private async resetTransactionOptions(
    store: relationalStore.RdbStore,
    isolationApplied: boolean,
    readOnlyApplied: boolean
  ): Promise<void> {
    if (readOnlyApplied) {
      try {
        await this.applyReadOnlyMode(store, false)
      } catch (e) {
        const errorMessage = e instanceof Error ? e.message : String(e)
        this.logger.logError(`恢复事务只读模式失败: ${errorMessage}`)
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

  private isExpectedReadOnlyWriteDenied(errorMessage: string): boolean {
    if (errorMessage.includes('当前平台不支持只读事务')) {
      return false
    }
    const normalized = errorMessage.toLowerCase()
    return normalized.includes('readonly database') ||
      normalized.includes('read-only') ||
      normalized.includes('attempt to write a readonly database') ||
      normalized.includes('query_only') ||
      errorMessage.includes('只读')
  }

  private isNonRetryableConfigurationError(errorMessage: string): boolean {
    return errorMessage.includes('不支持的事务隔离级别') ||
      errorMessage.includes('当前平台不支持 READ_UNCOMMITTED 隔离级别') ||
      errorMessage.includes('当前平台不支持只读事务') ||
      errorMessage.includes('设置事务隔离级别失败') ||
      errorMessage.includes('设置事务只读模式失败')
  }

  private isUnsupportedPragmaError(errorMessage: string): boolean {
    const normalized = errorMessage.toLowerCase()
    return normalized.includes('capability not supported') ||
      normalized.includes('pragma unsupported') ||
      normalized.includes('error code: 801') ||
      normalized.includes('801')
  }

  private logTransactionFailure(errorMessage: string): void {
    if (this.isExpectedReadOnlyWriteDenied(errorMessage)) {
      this.logger.logWarn(`[W_TX_READONLY_WRITE_DENIED] 事务执行失败: ${errorMessage}`)
      return
    }
    this.logger.logError(`事务执行失败: ${errorMessage}`)
  }

  private delay(ms: number): Promise<void> {
    return new Promise<void>((resolve) => setTimeout(() => resolve(), ms))
  }

  private getConnectionLockState(store: relationalStore.RdbStore): ConnectionTransactionLock {
    const existing = TransactionManager.connectionLocks.get(store)
    if (existing !== undefined) {
      return existing
    }
    const created = new ConnectionTransactionLock()
    TransactionManager.connectionLocks.set(store, created)
    return created
  }

  private resolveCleanupWaitMs(timeoutMs: number): number {
    const normalizedTimeout = timeoutMs > 0 ? timeoutMs : 30000
    const calculated = normalizedTimeout * 2
    if (calculated < 1000) {
      return 1000
    }
    if (calculated > 60000) {
      return 60000
    }
    return calculated
  }

  private releaseResourcesWhenCleanupSettles(
    releaseLock: () => void,
    releaseLease: () => void,
    pendingCleanup: Promise<void>,
    maxCleanupWaitMs: number
  ): void {
    let released = false
    const releaseSafely = (): void => {
      if (released) {
        return
      }
      released = true
      releaseLock()
      releaseLease()
    }
    let timeoutId: number = 0
    timeoutId = setTimeout(() => {
      this.logger.logError(`事务超时后清理超过 ${maxCleanupWaitMs}ms，保持事务锁定直到后台清理完成`)
    }, maxCleanupWaitMs)
    pendingCleanup.finally(() => {
      if (timeoutId !== 0) {
        clearTimeout(timeoutId)
        timeoutId = 0
      }
      this.logger.logInfo('事务超时后后台清理已完成')
      releaseSafely()
    })
  }

  static isConnectionTransactionActive(store: relationalStore.RdbStore): boolean {
    const current = TransactionManager.activeTransactions.get(store)
    return current !== undefined && current > 0
  }

  static hasAnyActiveTransaction(): boolean {
    return TransactionManager.activeTransactionCount > 0 || TransactionManager.pendingCleanupCount > 0
  }

  static markExternalTransactionBegin(store: relationalStore.RdbStore): void {
    TransactionManager.markManagedTransactionBegin(store)
  }

  static markExternalTransactionEnd(store: relationalStore.RdbStore): void {
    TransactionManager.markManagedTransactionEnd(store)
  }

  private static markManagedTransactionBegin(store: relationalStore.RdbStore): void {
    TransactionManager.activeTransactionCount += 1
    const current = TransactionManager.activeTransactions.get(store)
    if (current === undefined) {
      TransactionManager.activeTransactions.set(store, 1)
      return
    }
    TransactionManager.activeTransactions.set(store, current + 1)
  }

  private static markManagedTransactionEnd(store: relationalStore.RdbStore): void {
    if (TransactionManager.activeTransactionCount > 0) {
      TransactionManager.activeTransactionCount -= 1
    } else {
      TransactionManager.activeTransactionCount = 0
    }
    const current = TransactionManager.activeTransactions.get(store)
    if (current === undefined || current <= 1) {
      TransactionManager.activeTransactions.delete(store)
      return
    }
    TransactionManager.activeTransactions.set(store, current - 1)
  }

  private static markCleanupPendingBegin(): void {
    TransactionManager.pendingCleanupCount += 1
  }

  private static markCleanupPendingEnd(): void {
    if (TransactionManager.pendingCleanupCount > 0) {
      TransactionManager.pendingCleanupCount -= 1
    } else {
      TransactionManager.pendingCleanupCount = 0
    }
  }
}
