import { relationalStore } from '@kit.ArkData'
import { TransactionRollbackError } from '../errors/TransactionError'
import { TransactionManager } from './TransactionManager'

type InStrictTransaction = () => boolean
type ShouldBlockWriteUnderPooledActiveTransaction = () => boolean
type GetStore = () => relationalStore.RdbStore

export class RepositoryTransactionGuardSupport {
  private inStrictTransaction: InStrictTransaction
  private shouldBlockWriteUnderPooledActiveTransaction: ShouldBlockWriteUnderPooledActiveTransaction
  private getStore: GetStore

  constructor(
    inStrictTransaction: InStrictTransaction,
    shouldBlockWriteUnderPooledActiveTransaction: ShouldBlockWriteUnderPooledActiveTransaction,
    getStore: GetStore
  ) {
    this.inStrictTransaction = inStrictTransaction
    this.shouldBlockWriteUnderPooledActiveTransaction = shouldBlockWriteUnderPooledActiveTransaction
    this.getStore = getStore
  }

  ensureWritePathAllowed(operation: string): void {
    if (this.inStrictTransaction()) {
      return
    }
    if (this.shouldBlockWriteUnderPooledActiveTransaction()) {
      throw new TransactionRollbackError(
        `检测到连接池模式下存在活动事务，禁止在未绑定事务上下文的 Repository 执行 ${operation} 写入，请复用事务回调提供的 Repository 实例`
      )
    }
    const store = this.getStore()
    if (!TransactionManager.isConnectionTransactionActive(store)) {
      return
    }
    throw new TransactionRollbackError(
      `检测到连接级事务已激活，禁止在事务边界外执行 ${operation} 写入，请复用外层事务上下文`
    )
  }

  ensureNoNestedTransaction(entryName: string): void {
    if (this.inStrictTransaction()) {
      throw new TransactionRollbackError(
        `不支持同一 Repository 嵌套调用 ${entryName}，请复用外层事务或改为 SAVEPOINT 语义`
      )
    }
    if (this.shouldBlockWriteUnderPooledActiveTransaction()) {
      throw new TransactionRollbackError(
        `检测到连接池模式下存在活动事务，禁止在未绑定事务上下文的 Repository 启动 ${entryName}，请复用外层事务回调传入的 Repository`
      )
    }
    const store = this.getStore()
    if (!TransactionManager.isConnectionTransactionActive(store)) {
      return
    }
    throw new TransactionRollbackError(
      `不支持跨 Repository 嵌套调用 ${entryName}，请复用外层事务上下文`
    )
  }
}
