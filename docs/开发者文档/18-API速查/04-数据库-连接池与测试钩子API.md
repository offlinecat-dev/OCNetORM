# 04-数据库-连接池与测试钩子API

> 状态：已完成
> 适用版本：ocorm 3.0.2
> 最后更新：2026-03-28
> 对照源码：`src/main/ets/database/DatabaseConfig.ets`、`DatabaseManager.ets`、`testing/DatabaseManagerTestHooks.ets`、`session/DatabaseSession.ets`

## 1. 覆盖范围

这一页覆盖连接层入口：

- `DatabaseConfig`
- `DatabaseManager`
- `StoreLease`、`FixedStorePool`、`PoolMetrics`
- `DefaultDatabaseSession`、`SessionStoreResolver`
- `DatabaseManagerTestHooks`

深入文档看：

- [`../04-数据库与连接层/01-DatabaseConfig参数详解.md`](../04-数据库与连接层/01-DatabaseConfig参数详解.md)
- [`../04-数据库与连接层/03-连接池模型-FixedStorePool.md`](../04-数据库与连接层/03-连接池模型-FixedStorePool.md)
- [`../04-数据库与连接层/06-测试钩子与测试环境隔离.md`](../04-数据库与连接层/06-测试钩子与测试环境隔离.md)

## 2. API 快表

| 类/能力 | 代表方法 | 说明 |
| --- | --- | --- |
| `DatabaseConfig` | `setHealthCheckInterval()`、`setQueryCache()`、`setQueryTimeout()` | 基础运行时参数 |
| `DatabaseConfig` | `setMaxConcurrentQueries()`、`setRelationInClauseLimit()`、`setRelationLoadConcurrency()` | 查询与关系加载并发控制 |
| `DatabaseConfig` | `setConnectionPool()`、`setPooledWriteGuardMode()` | 连接池与池化写保护 |
| `DatabaseManager` | `initialize()`、`getStore()`、`isInitialized()`、`isHealthy()` | 生命周期与单例主连接 |
| `DatabaseManager` | `acquireStoreLease()`、`withStoreLease()`、`releaseStoreLease()` | 连接租约 |
| `DatabaseManager` | `getPoolMetrics()`、`isPoolEnabled()`、`getActiveQuerySlots()` | 运行时观测 |
| `DatabaseManager` | `getQueryCache()`、`getConfig()`、`getTestingState()`、`setTestingState()` | 配置与测试辅助 |
| `DatabaseManagerTestHooks` | `getState()`、`setState()`、`applyRuntimeConfig()`、`resetInstance()` | 测试专用可见面 |
| `DefaultDatabaseSession` | `getReadStore()`、`getWriteStore()`、`bindTransactionStore()` | 会话与事务绑定 |
| `SessionStoreResolver` | `resolveReadStore()`、`resolveWriteStore()`、`resolveTransactionStore()` | 会话连接解析 |

## 3. 初始化与配置

```ts
import { DatabaseConfig, DatabaseManager } from 'ocorm'

const config = new DatabaseConfig('app.db')
  .setHealthCheckInterval(30_000)
  .setQueryCache(true, 200, 10_000)
  .setQueryTimeout(1200)
  .setMaxConcurrentQueries(4)
  .setRelationInClauseLimit(500)
  .setRelationLoadConcurrency(4)
  .setConnectionPool({
    enabled: true,
    minSize: 2,
    maxSize: 4,
    acquireTimeoutMs: 1500
  })
  .setPooledWriteGuardMode('global')

await DatabaseManager.getInstance().initialize(context, config)
```

配置选择不要凭感觉，直接对照：

- [`../13-性能与调优/01-连接池与并发槽调优.md`](../13-性能与调优/01-连接池与并发槽调优.md)
- [`../13-性能与调优/02-关系加载并发与IN子句限制.md`](../13-性能与调优/02-关系加载并发与IN子句限制.md)

## 4. 连接租约与连接池

`getStore()` 返回主连接，兼容旧路径；真正需要池化语义时，优先 `acquireStoreLease()` 或 `withStoreLease()`。

```ts
import { DatabaseManager } from 'ocorm'

const manager = DatabaseManager.getInstance()
const lease = await manager.acquireStoreLease()

try {
  await lease.store.executeSql(
    'UPDATE users SET user_name = ? WHERE id = ?',
    ['neo', 1]
  )
} finally {
  lease.release()
}

console.info(JSON.stringify(manager.getPoolMetrics()))
```

更安全的写法是包裹式调用：

```ts
import { DatabaseManager } from 'ocorm'

await DatabaseManager.getInstance().withStoreLease(async (lease) => {
  await lease.store.executeSql(
    'INSERT INTO users (id, user_name) VALUES (?, ?)',
    [7, 'pooled-user']
  )
})
```

## 5. Session 与事务绑定

`DefaultDatabaseSession` 在事务期间固定使用同一个 `StoreLease`；非事务路径按需申请连接。仓储和事务管理器内部会利用这层抽象，手写扩展时才需要直接使用。

```ts
import {
  DatabaseManager,
  DefaultDatabaseSession,
  SessionStoreResolver
} from 'ocorm'

const manager = DatabaseManager.getInstance()
const session = new DefaultDatabaseSession(manager)
const resolver = new SessionStoreResolver()

const readLease = await resolver.resolveReadStore(session)
readLease.release()

const txLease = await manager.acquireStoreLease()
session.bindTransactionStore(txLease)
const bound = resolver.resolveTransactionStore(session)
console.info(bound === null ? 'no-tx-store' : bound.sessionId)
```

## 6. 测试钩子

测试不要直接去碰 `DatabaseManager` 私有实现，统一走 `DatabaseManagerTestHooks`。

```ts
import {
  DatabaseConfig,
  DatabaseManager,
  DatabaseManagerTestHooks
} from 'ocorm'

const manager = DatabaseManager.getInstance()
const snapshot = DatabaseManagerTestHooks.getState(manager)

DatabaseManagerTestHooks.applyRuntimeConfig(
  manager,
  new DatabaseConfig('test.db').setQueryTimeout(50)
)

DatabaseManagerTestHooks.setState(manager, snapshot)
DatabaseManagerTestHooks.resetInstance()
```

对应测试层文档：

- [`../14-测试与验收/01-测试分层与目录映射.md`](../14-测试与验收/01-测试分层与目录映射.md)
- [`../04-数据库与连接层/06-测试钩子与测试环境隔离.md`](../04-数据库与连接层/06-测试钩子与测试环境隔离.md)

## 7. 观测与排障入口

出现“数据库已关闭”“连接池超时”“查询槽超时”这类问题，先看这几个方法：

- `isInitialized()`
- `isHealthy()`
- `getPoolMetrics()`
- `getActiveQuerySlots()`
- `getTestingState()`

```ts
import { DatabaseManager } from 'ocorm'

const manager = DatabaseManager.getInstance()
console.info(`initialized=${manager.isInitialized()}`)
console.info(`healthy=${manager.isHealthy()}`)
console.info(`activeQuerySlots=${manager.getActiveQuerySlots()}`)
console.info(JSON.stringify(manager.getPoolMetrics()))
```

排障专题直接看：

- [`../16-排障与FAQ/02-数据库关闭类问题排查.md`](../16-排障与FAQ/02-数据库关闭类问题排查.md)
- [`../16-排障与FAQ/03-事务超时与清理排查.md`](../16-排障与FAQ/03-事务超时与清理排查.md)

## 8. 继续下钻

- Schema / 迁移：[`05-Schema-迁移与工具链API.md`](./05-Schema-迁移与工具链API.md)
- 深度章节：[`../04-数据库与连接层/02-DatabaseManager生命周期.md`](../04-数据库与连接层/02-DatabaseManager生命周期.md)、[`../04-数据库与连接层/05-查询并发槽-QuerySlotGate.md`](../04-数据库与连接层/05-查询并发槽-QuerySlotGate.md)

## 9. 变更记录

- 2026-03-28：补齐数据库配置、连接池、Session 和测试钩子 API 速查。
