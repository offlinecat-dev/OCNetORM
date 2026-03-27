import { StoreLease } from '../pool/StoreLease'
import { DatabaseSession } from './DatabaseSession'

/**
 * 会话连接解析器
 * 统一读写路径的连接解析入口
 */
export class SessionStoreResolver {
  async resolveReadStore(session: DatabaseSession): Promise<StoreLease> {
    return await session.getReadStore()
  }

  async resolveWriteStore(session: DatabaseSession): Promise<StoreLease> {
    return await session.getWriteStore()
  }

  resolveTransactionStore(session: DatabaseSession): StoreLease | null {
    return session.getTransactionStore()
  }
}
