# 查询安全守卫（QueryBuilderGuards）

> 源码对齐：`src/main/ets/query/QueryBuilderGuards.ets`、`src/main/ets/query/QueryBuilder.ets`

## 行为契约

### 1) `orderBy(column, direction)`

| 项 | 契约 |
|---|---|
| 参数 | `direction` 仅允许 `ASC` 或 `DESC`（忽略首尾空白，统一大写） |
| 返回 | 当前 `QueryBuilder`，可链式 |
| 异常 | 非法方向抛 `InvalidConditionError('ORDER BY', '非法排序方向: ...')` |
| 上下文限制 | `column` 必须能解析为实体已注册列（列名或属性名） |

### 2) `having(clause, args = [])`

| 项 | 契约 |
|---|---|
| 参数 | `clause` 不能为空；`args` 不能为空；`?` 数量必须等于 `args.length` |
| 返回 | 当前 `QueryBuilder` |
| 异常 | 统一抛 `InvalidConditionError('HAVING', ...)` |
| 上下文限制 | 拒绝 `; -- /* */ ' \" \`` 等危险片段；拒绝 `UNION/SELECT/FROM/JOIN/INSERT/UPDATE/DELETE/...` 关键字；仅允许安全字符集 |

### 3) `selectRaw(expressions)`

| 项 | 契约 |
|---|---|
| 参数 | 数组不能为空，元素不能为空字符串 |
| 返回 | 当前 `QueryBuilder` |
| 异常 | 非白名单表达式抛 `InvalidConditionError('selectRaw', ...)` |
| 上下文限制 | 仅允许两类：标识符（如 `user_name`）或聚合函数（`COUNT/SUM/AVG/MIN/MAX`，可带 `AS alias`） |

## 可运行示例（安全通过）

```arkts
import { Context } from '@kit.AbilityKit'
import {
  ColumnType,
  ConditionOperator,
  DatabaseConfig,
  OCORMInit,
  QueryBuilder,
  QueryExecutor,
  defineEntity
} from 'ocorm'

async function bootstrap(context: Context): Promise<void> {
  defineEntity('Order', {
    tableName: 'orders',
    columns: [
      { property: 'id', name: 'id', type: ColumnType.INTEGER, primaryKey: true, autoIncrement: false },
      { property: 'status', name: 'status', type: ColumnType.TEXT },
      { property: 'amount', name: 'amount', type: ColumnType.REAL }
    ]
  })
  await OCORMInit(context, {
    config: new DatabaseConfig('query_guard.db'),
    autoCreateTables: true
  })
}

export async function runGuardPass(context: Context): Promise<void> {
  await bootstrap(context)

  const qb = new QueryBuilder('Order')
    .where('status', ConditionOperator.EQUAL, 'PAID')
    .selectRaw(['status', 'COUNT(*) AS total'])
    .groupBy('status')
    .having('COUNT(*) >= ?', [1])
    .orderBy('status', 'ASC')

  const rows = await new QueryExecutor(qb).getRaw()
  console.info('raw rows:', rows.length)
}
```

## 失败案例（构造期直接拒绝）

```arkts
import { Context } from '@kit.AbilityKit'
import { QueryBuilder } from 'ocorm'

export async function failHavingAndOrderBy(context: Context): Promise<void> {
  await bootstrap(context)
  const qb = new QueryBuilder('Order')

  try {
    // 失败点 1：having 没有参数化
    qb.having('COUNT(*) > 0', [])
  } catch (e) {
    console.error('expected having guard error:', e)
  }

  try {
    // 失败点 2：非法排序方向
    qb.orderBy('status', 'DOWN' as any)
  } catch (e) {
    console.error('expected orderBy guard error:', e)
  }
}
```

## 关联限制提醒
- `get/getOne/count/getPaginated/getAsync` 属于实体模式，不允许使用 `selectRaw/groupBy/having`。
- 使用 `selectRaw/groupBy/having` 时应走 `getRaw()` 或 `aggregate()`。
