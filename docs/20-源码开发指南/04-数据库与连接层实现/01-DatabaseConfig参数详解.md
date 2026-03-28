# DatabaseConfig参数详解

## 目标
围绕 `DatabaseConfig` 的真实字段与链式方法，给出可直接落地的配置模板、动态重配策略与故障复现步骤。

## 字段与链式 API（与源码一致）
- 字段：`name`、`securityLevel`、`encrypt`、`enableLogger`、`loggerLevel`
- 查询相关：`enableQueryCache`、`queryCacheMaxSize`、`queryCacheTtlMs`、`queryTimeoutMs`、`maxConcurrentQueries`
- 关联加载：`relationInClauseLimit`、`relationLoadConcurrency`
- 连接池：`connectionPool`（`PoolConfig`）
- 保护开关：`pooledWriteGuardMode`（`'global' | 'off'`）
- 方法：`setHealthCheckInterval`、`setQueryCache`、`setQueryTimeout`、`setMaxConcurrentQueries`、`setRelationInClauseLimit`、`setRelationLoadConcurrency`、`setConnectionPool`、`setPooledWriteGuardMode`

## 配置样例：开发与生产
```ts
import { relationalStore } from '@kit.ArkData'
import { LogLevel } from '../../src/main/ets/logging/LogLevel'
import { DatabaseConfig } from '../../src/main/ets/database/DatabaseConfig'

// 开发：强调可观测性
const devConfig = new DatabaseConfig(
  'ocorm_dev.db',
  relationalStore.SecurityLevel.S1,
  true,
  true,
  LogLevel.DEBUG
)
  .setHealthCheckInterval(0)
  .setQueryCache(false)
  .setQueryTimeout(0)
  .setMaxConcurrentQueries(0)
  .setRelationInClauseLimit(500)
  .setRelationLoadConcurrency(1)
  .setConnectionPool({ enabled: false })
  .setPooledWriteGuardMode('off')

// 生产：强调稳定与资源控制
const prodConfig = new DatabaseConfig('ocorm_prod.db')
  .setHealthCheckInterval(15000)
  .setQueryCache(true, 300, 120000)
  .setQueryTimeout(2000)
  .setMaxConcurrentQueries(32)
  .setRelationInClauseLimit(400)
  .setRelationLoadConcurrency(4)
  .setConnectionPool({
    enabled: true,
    minSize: 2,
    maxSize: 16,
    acquireTimeoutMs: 1200,
    idleTimeoutMs: 60000,
    healthCheckIntervalMs: 0
  })
  .setPooledWriteGuardMode('global')
```

## 生命周期调用序列：热重配（同连接参数）
`DatabaseManager.initialize(context, config)` 在“连接参数不变且池配置不变”时会复用连接，仅刷新运行时配置（日志、缓存、并发槽、健康检查）。

```ts
import { Context } from '@kit.AbilityKit'
import { DatabaseManager } from '../../src/main/ets/database/DatabaseManager'
import { DatabaseConfig } from '../../src/main/ets/database/DatabaseConfig'

async function reconfigureAtRuntime(context: Context): Promise<void> {
  const manager = DatabaseManager.getInstance()

  const configV1 = new DatabaseConfig('runtime.db')
    .setQueryCache(false)
    .setMaxConcurrentQueries(8)

  await manager.initialize(context, configV1)

  // 连接参数（name/security/encrypt）不变，仅调整运行时策略
  const configV2 = new DatabaseConfig('runtime.db')
    .setQueryCache(true, 200, 60000)
    .setMaxConcurrentQueries(16)
    .setQueryTimeout(1500)

  await manager.initialize(context, configV2)
}
```

## 故障复现脚本：错误配置归一化验证
`setConnectionPool` 会走 `PoolConfig.normalize()`，下面脚本用于确认“负值/非法值”被修正，不会直接把系统带崩。

```ts
import { DatabaseConfig } from '../../src/main/ets/database/DatabaseConfig'

function reproducePoolNormalization(): void {
  const config = new DatabaseConfig('normalize.db').setConnectionPool({
    enabled: true,
    minSize: -5,
    maxSize: -1,
    acquireTimeoutMs: -300,
    idleTimeoutMs: -10,
    healthCheckIntervalMs: -20
  })

  const pool = config.connectionPool
  console.info(
    `enabled=${pool.enabled}, min=${pool.minSize}, max=${pool.maxSize}, acquire=${pool.acquireTimeoutMs}`
  )
  // 预期：min/max >= 1，acquire/idle/healthCheck >= 0
}
```

## 排障清单
- `queryTimeoutMs` 太小 + `maxConcurrentQueries` 太低：会放大 `等待查询槽位超时`。
- `name` 变更会触发缓存命名空间变化与清理，切库前先评估缓存命中波动。
- 连接池 `maxSize` 与业务并发不匹配时，优先看池超时与排队指标，而不是盲目提升 SQL 超时。

## 关键源码路径
- `src/main/ets/database/DatabaseConfig.ets`
- `src/main/ets/database/pool/PoolConfig.ets`
- `src/main/ets/database/DatabaseManager.ets`
- `src/main/ets/database/manager/QuerySlotGate.ets`
