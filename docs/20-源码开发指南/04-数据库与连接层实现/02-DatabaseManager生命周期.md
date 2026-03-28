# DatabaseManager生命周期

## 目标
精确描述 `DatabaseManager` 的初始化、复用、关闭与健康检查边界，避免状态错用导致连锁故障。

## 生命周期调用序列
```text
initialize(context, config)
  -> handleQueryCacheForConfigChange(previous, config)
  -> [同连接+同池配置] 仅 applyRuntimeConfig(config)
  -> [否则] close() 清理旧连接/旧池
  -> getRdbStore(...) 创建主连接
  -> setupPool(...) 可选创建连接池
  -> initialized=true, healthy=true
  -> applyRuntimeConfig(config)

业务期
  -> getStore()/acquireStoreLease()/withStoreLease(...)
  -> acquireQuerySlot()/releaseQuerySlot()
  -> ping()/isHealthy()

close()
  -> stopHealthCheck()
  -> pool.close()
  -> store.close()
  -> querySlotGate.reset()
  -> initialized=false, healthy=false
```

## 配置样例 + 初始化/关闭
```ts
import { Context } from '@kit.AbilityKit'
import { DatabaseConfig } from '../../src/main/ets/database/DatabaseConfig'
import { DatabaseManager } from '../../src/main/ets/database/DatabaseManager'

export async function bootDatabase(context: Context): Promise<void> {
  const manager = DatabaseManager.getInstance()
  const config = new DatabaseConfig('lifecycle.db')
    .setHealthCheckInterval(10000)
    .setQueryCache(true, 256, 90000)
    .setQueryTimeout(1200)
    .setMaxConcurrentQueries(24)
    .setConnectionPool({ enabled: true, minSize: 2, maxSize: 8, acquireTimeoutMs: 1000 })

  await manager.initialize(context, config)

  if (!manager.isInitialized()) {
    throw new Error('DatabaseManager 初始化失败')
  }
}

export async function shutdownDatabase(): Promise<void> {
  const manager = DatabaseManager.getInstance()
  await manager.close()
}
```

## 并发控制示例：用 `withStoreLease` 降低泄漏概率
```ts
import { DatabaseManager } from '../../src/main/ets/database/DatabaseManager'

async function runWriteSafely(sql: string, args: Array<number | string>): Promise<void> {
  const manager = DatabaseManager.getInstance()

  await manager.withStoreLease(async (lease) => {
    await manager.acquireQuerySlot()
    try {
      await lease.store.executeSql(sql, args)
    } finally {
      manager.releaseQuerySlot()
    }
  }, 1000)
}
```

## 故障复现脚本：未初始化直接取连接
```ts
import { DatabaseManager } from '../../src/main/ets/database/DatabaseManager'

function reproduceNotInitialized(): void {
  const manager = DatabaseManager.getInstance()
  // 未调用 initialize 时，getStore() 将抛 DatabaseNotInitializedError
  const store = manager.getStore()
  console.info(store)
}
```

## 排障建议
- 初始化失败先看 `ConnectionError` 的原始 message，再核对 `name/securityLevel/encrypt`。
- 若频繁出现“可用但不健康”波动，优先检查 `healthCheckIntervalMs` 与 SQL 执行峰值是否冲突。
- 连接池开启后尽量统一使用 `withStoreLease`；手动 `acquireStoreLease` 必须保证 `lease.release()`。

## 关键源码路径
- `src/main/ets/database/DatabaseManager.ets`
- `src/main/ets/database/manager/StorePoolFactory.ets`
- `src/main/ets/database/manager/QuerySlotGate.ets`
