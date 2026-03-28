# 03-查询

## 文档目标
本目录只描述 `src/main/ets/query/**` 与 `src/main/ets/database/manager/QuerySlotGate.ets` 的真实行为契约：
- 参数约束（调用前置条件）
- 返回语义（成功路径）
- 异常语义（失败路径）
- 上下文限制（并发、模式边界、超时）

## 核心行为契约

| 主题 | 入口 API | 参数契约 | 返回契约 | 异常契约 | 上下文限制 |
|---|---|---|---|---|---|
| 实体模式查询 | `QueryExecutor.get/getOne/count/getPaginated/getAsync` | `QueryBuilder` 不允许携带 `selectRaw/groupBy/having` | `EntityData[] / EntityData\|null / number / PaginatedResult` | 统一抛 `ExecutionError`（`SELECT/COUNT/...`） | 进入执行前会 `DatabaseManager.acquireQuerySlot()` |
| 原生模式查询 | `QueryExecutor.getRaw` | 允许 `selectRaw/groupBy/having` | `ResultSetRow[]` | 失败抛 `ExecutionError('RAW_SELECT', ...)` | `whereExists` 触发内存过滤时，`getRaw` 直接失败 |
| 构造守卫 | `QueryBuilder.orderBy/having/selectRaw` | 方向仅 `ASC/DESC`；`having` 必须参数化且占位符匹配；`selectRaw` 仅白名单表达式 | 返回 `QueryBuilder`（链式） | 抛 `InvalidConditionError` | 用于在构造期提前拒绝高风险 SQL 片段 |
| 并发保护 | `QuerySlotGate + QueryExecutor.withStoreLease` | 同实例禁止并发复用；并发槽位由 `DatabaseConfig.maxConcurrentQueries` 控制 | 正常排队执行或直接执行 | 并发复用抛 `ExecutionError('QUERY_EXECUTOR', ...)`；槽位等待超时最终转为 `ExecutionError('SELECT'/'COUNT', '等待查询槽位超时...')` | `maxConcurrentQueries <= 0` 表示不限制 |

## 可运行示例（查询成功路径）

```arkts
import { Context } from '@kit.AbilityKit'
import {
  ColumnType,
  ConditionOperator,
  DatabaseConfig,
  OCORMInit,
  QueryBuilder,
  QueryExecutor,
  Repository,
  defineEntity
} from 'ocorm'

async function bootstrap(context: Context): Promise<void> {
  defineEntity('User', {
    tableName: 'users',
    columns: [
      { property: 'id', name: 'id', type: ColumnType.INTEGER, primaryKey: true, autoIncrement: false },
      { property: 'name', name: 'user_name', type: ColumnType.TEXT },
      { property: 'age', name: 'age', type: ColumnType.INTEGER }
    ]
  })

  await OCORMInit(context, {
    config: new DatabaseConfig('query_contract.db')
      .setQueryTimeout(800)
      .setMaxConcurrentQueries(2),
    autoCreateTables: true
  })
}

export async function runQueryDemo(context: Context): Promise<void> {
  await bootstrap(context)

  const repo = new Repository('User')
  await repo.rawExecute('INSERT INTO users(id, user_name, age) VALUES (?, ?, ?)', [1, 'Alice', 20])
  await repo.rawExecute('INSERT INTO users(id, user_name, age) VALUES (?, ?, ?)', [2, 'Bob', 25])

  const qb = new QueryBuilder('User')
    .where('age', ConditionOperator.GREATER_EQUAL, 21)
    .orderBy('id', 'ASC')

  const rows = await new QueryExecutor(qb).get()
  console.info('query rows:', rows.length) // 1
}
```

## 失败案例（模式边界违规）

```arkts
import { Context } from '@kit.AbilityKit'
import { QueryBuilder, QueryExecutor } from 'ocorm'

export async function failEntityModeWithSelectRaw(context: Context): Promise<void> {
  await bootstrap(context)
  const qb = new QueryBuilder('User')
    .selectRaw(['COUNT(*) AS total'])
    .groupBy('id')

  try {
    await new QueryExecutor(qb).get()
  } catch (e) {
    // 源码语义：ExecutionError('SELECT', '实体查询不支持 selectRaw/groupBy/having...')
    console.error('expected:', e)
  }
}
```

## 推荐阅读顺序
1. `00-查询体系总览.md`
2. `05-QueryExecutor实体模式.md`
3. `06-QueryExecutor原生模式-getRaw.md`
4. `11-查询安全守卫-QueryBuilderGuards.md`
5. `12-常见误用与失败语义.md`
