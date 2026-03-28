# 查询并发槽 QuerySlotGate

## 目标
基于 `QuerySlotGate` 真实实现解释限流与排队机制，并给出可复现的超时脚本。

## 核心语义
- `configure(config)` 从 `DatabaseConfig` 读取：`queryTimeoutMs`、`maxConcurrentQueries`
- `acquire()`：
  - `maxConcurrentQueries <= 0` 时直接放行
  - 达上限后进入等待队列
  - 等待超时抛出 `等待查询槽位超时 (xxxms)`
- `release()`：释放一个活动槽位，并尝试唤醒等待者
- `reset()`：清空配置、活动槽位与等待队列

## 配置样例：开启限流
```ts
import { DatabaseConfig } from '../../src/main/ets/database/DatabaseConfig'

const config = new DatabaseConfig('gate.db')
  .setMaxConcurrentQueries(2)
  .setQueryTimeout(300)
```

## 并发控制示例：由 DatabaseManager 代理 QuerySlotGate
```ts
import { DatabaseManager } from '../../src/main/ets/database/DatabaseManager'

async function runSlotGuardedTask(taskName: string, costMs: number): Promise<void> {
  const manager = DatabaseManager.getInstance()
  await manager.acquireQuerySlot()

  try {
    console.info(`[${taskName}] enter slots=${manager.getActiveQuerySlots()}`)
    await new Promise<void>((resolve) => setTimeout(resolve, costMs))
  } finally {
    manager.releaseQuerySlot()
    console.info(`[${taskName}] leave slots=${manager.getActiveQuerySlots()}`)
  }
}
```

## 故障复现脚本：槽位超时
```ts
import { DatabaseConfig } from '../../src/main/ets/database/DatabaseConfig'
import { DatabaseManagerTestHooks } from '../../src/main/ets/database/testing/DatabaseManagerTestHooks'
import { DatabaseManager } from '../../src/main/ets/database/DatabaseManager'

async function reproduceSlotTimeout(): Promise<void> {
  const manager = DatabaseManager.getInstance()

  // 测试环境中热注入限流配置
  DatabaseManagerTestHooks.applyRuntimeConfig(
    manager,
    new DatabaseConfig('slot_timeout.db')
      .setMaxConcurrentQueries(1)
      .setQueryTimeout(100)
  )

  await manager.acquireQuerySlot()
  try {
    await manager.acquireQuerySlot() // 预期抛等待超时
  } catch (e) {
    console.error(`预期超时: ${e instanceof Error ? e.message : String(e)}`)
  } finally {
    manager.releaseQuerySlot()
  }
}
```

## 排障清单
- 若 `getActiveQuerySlots()` 持续不降，说明业务路径存在漏释放。
- 配置改小后立即生效，压测脚本需同步更新预期阈值。
- 当 `maxConcurrentQueries` 设置为 `0`，所有等待者会被放行，不再限流。

## 关键源码路径
- `src/main/ets/database/manager/QuerySlotGate.ets`
- `src/main/ets/database/DatabaseManager.ets`
- `src/main/ets/database/DatabaseConfig.ets`
