import { DatabaseManager } from '../DatabaseManager'
import { StoreLease } from '../pool/StoreLease'

/**
 * 数据库会话抽象
 */
export interface DatabaseSession {
  readonly sessionId: string
  getReadStore(): Promise<StoreLease>
  getWriteStore(): Promise<StoreLease>
  bindTransactionStore(lease: StoreLease): void
  getTransactionStore(): StoreLease | null
}

/**
 * 默认会话实现
 * 事务期间固定使用同一连接，非事务路径按需申请连接
 */
export class DefaultDatabaseSession implements DatabaseSession {
  private static sequence: number = 0
  readonly sessionId: string
  private manager: DatabaseManager
  private transactionStore: StoreLease | null = null

  constructor(manager: DatabaseManager = DatabaseManager.getInstance(), sessionId?: string) {
    this.manager = manager
    this.sessionId = sessionId !== undefined ? sessionId : this.nextSessionId()
  }

  async getReadStore(): Promise<StoreLease> {
    if (this.transactionStore !== null) {
      return this.transactionStore
    }
    return await this.manager.acquireStoreLease()
  }

  async getWriteStore(): Promise<StoreLease> {
    if (this.transactionStore !== null) {
      return this.transactionStore
    }
    return await this.manager.acquireStoreLease()
  }

  bindTransactionStore(lease: StoreLease): void {
    this.transactionStore = lease
  }

  getTransactionStore(): StoreLease | null {
    return this.transactionStore
  }

  private nextSessionId(): string {
    DefaultDatabaseSession.sequence += 1
    return `session-${Date.now()}-${DefaultDatabaseSession.sequence}`
  }
}
