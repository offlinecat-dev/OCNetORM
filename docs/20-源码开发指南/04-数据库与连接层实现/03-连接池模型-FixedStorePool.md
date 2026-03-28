# 连接池模型 FixedStorePool

## 目标
围绕 `FixedStorePool` 的真实行为说明池扩容、排队超时、lease 归还与关闭阶段的可预期语义。

## 核心行为摘要
- `acquire(timeoutMs?)`：先拿 `idleStores`，否则在 `currentSize < maxSize` 时新建连接。
- 达上限后进入 `pendingAcquires`，超时报错 `获取连接超时`。
- `release(lease)`：优先把连接移交给等待队列，否则回到 `idleStores`。
- `close()`：拒绝全部 pending 请求，并关闭 idle + active 中全部连接。

## 连接池配置样例（通过 DatabaseConfig）
```ts
import { DatabaseConfig } from '../../src/main/ets/database/DatabaseConfig'

const config = new DatabaseConfig('pool.db').setConnectionPool({
  enabled: true,
  minSize: 2,
  maxSize: 4,
  acquireTimeoutMs: 800,
  idleTimeoutMs: 30000,
  healthCheckIntervalMs: 0
})
```

## 并发控制示例：观察池指标
```ts
import { DatabaseManager } from '../../src/main/ets/database/DatabaseManager'

async function observePoolPressure(): Promise<void> {
  const manager = DatabaseManager.getInstance()

  const jobs: Array<Promise<void>> = []
  for (let i = 0; i < 12; i++) {
    jobs.push(
      manager.withStoreLease(async (lease) => {
        await lease.store.executeSql('SELECT 1')
      }, 500)
    )
  }

  await Promise.allSettled(jobs)

  const metrics = manager.getPoolMetrics()
  if (metrics !== null) {
    console.info(
      `active=${metrics.activeLeases}, idle=${metrics.idleStores}, pending=${metrics.pendingRequests}, timeouts=${metrics.timeoutCount}`
    )
  }
}
```

## 故障复现脚本：故意泄漏 lease 导致池耗尽
```ts
import { DatabaseManager } from '../../src/main/ets/database/DatabaseManager'

async function reproduceLeaseLeak(): Promise<void> {
  const manager = DatabaseManager.getInstance()

  // 故意不 release，制造 activeLeases 占满
  const leaked1 = await manager.acquireStoreLease(200)
  const leaked2 = await manager.acquireStoreLease(200)

  try {
    await manager.acquireStoreLease(200)
  } catch (e) {
    console.error(`预期失败: ${e instanceof Error ? e.message : String(e)}`)
  }

  leaked1.release()
  leaked2.release()
}
```

## 排障清单
- `pendingRequests` 持续增长：优先排查是否存在遗漏 `lease.release()`。
- `timeoutCount` 突增：提升 `maxSize` 前先确认慢 SQL 与事务持锁时长。
- 连接池关闭后任何待获取请求都会失败，测试里不要复用已关闭实例。

## 关键源码路径
- `src/main/ets/database/pool/FixedStorePool.ets`
- `src/main/ets/database/pool/PoolConfig.ets`
- `src/main/ets/database/pool/StoreLease.ets`
- `src/main/ets/database/DatabaseManager.ets`
