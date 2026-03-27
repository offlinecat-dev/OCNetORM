import { Context } from '@kit.AbilityKit'
import { relationalStore } from '@kit.ArkData'
import { DatabaseConfig } from '../DatabaseConfig'
import { FixedStorePool } from '../pool/FixedStorePool'
import { StoreFactory } from '../pool/StoreFactory'
import { StorePool } from '../pool/StorePool'

/**
 * 连接池工厂与配置比较器
 */
export class StorePoolFactory {
  static isSamePoolConfig(current: DatabaseConfig, next: DatabaseConfig): boolean {
    const currentPool = current.connectionPool
    const nextPool = next.connectionPool
    return currentPool.enabled === nextPool.enabled &&
      currentPool.minSize === nextPool.minSize &&
      currentPool.maxSize === nextPool.maxSize &&
      currentPool.acquireTimeoutMs === nextPool.acquireTimeoutMs &&
      currentPool.idleTimeoutMs === nextPool.idleTimeoutMs &&
      currentPool.healthCheckIntervalMs === nextPool.healthCheckIntervalMs
  }

  static async createPool(
    context: Context,
    config: DatabaseConfig,
    storeConfig: relationalStore.StoreConfig
  ): Promise<StorePool | null> {
    const poolConfig = config.connectionPool.clone().normalize()
    if (!poolConfig.enabled) {
      return null
    }
    const factory = new StoreFactory(context, storeConfig)
    const pool = new FixedStorePool(
      poolConfig,
      async () => await factory.create(),
      async (store: relationalStore.RdbStore) => await factory.close(store)
    )
    await pool.warmUp()
    return pool
  }
}
