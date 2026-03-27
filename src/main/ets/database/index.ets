/**
 * 数据库模块统一导出
 */

// 数据库配置
export { DatabaseConfig } from './DatabaseConfig'
export type { ConnectionPoolOptions, PooledWriteGuardMode } from './DatabaseConfig'

// 数据库管理器
export { DatabaseManager } from './DatabaseManager'
export type { DatabaseManagerAdapter } from './DatabaseManager'
export { DatabaseManagerTestHooks } from './testing/DatabaseManagerTestHooks'
export type { DatabaseManagerTestState } from './testing/DatabaseManagerTestHooks'

// 连接池
export { PoolConfig } from './pool/PoolConfig'
export { PoolMetrics } from './pool/PoolMetrics'
export { StoreFactory } from './pool/StoreFactory'
export { StoreLease } from './pool/StoreLease'
export type { StorePool } from './pool/StorePool'
export { FixedStorePool } from './pool/FixedStorePool'

// 会话
export type { DatabaseSession } from './session/DatabaseSession'
export { DefaultDatabaseSession } from './session/DatabaseSession'
export { SessionStoreResolver } from './session/SessionStoreResolver'
