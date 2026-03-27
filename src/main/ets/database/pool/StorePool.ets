import { PoolMetrics } from './PoolMetrics'
import { StoreLease } from './StoreLease'

/**
 * 连接池抽象接口
 */
export interface StorePool {
  acquire(timeoutMs?: number): Promise<StoreLease>
  release(lease: StoreLease): void
  withLease<T>(fn: (lease: StoreLease) => Promise<T>, timeoutMs?: number): Promise<T>
  metrics(): PoolMetrics
  close(): Promise<void>
}

