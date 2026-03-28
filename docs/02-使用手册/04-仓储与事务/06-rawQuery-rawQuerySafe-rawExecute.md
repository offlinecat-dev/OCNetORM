# rawQuery / rawQuerySafe / rawExecute

> 源码对齐：`Repository.ets`、`rawsql/RawSqlGuards.ets`

## 1. API 行为契约

### `rawQuery(sql, args = [])`

| 项 | 契约 |
|---|---|
| 参数 | `sql` 必须是只读 SQL（`SELECT/WITH/EXPLAIN`）；必须至少一个 `?`；占位符数量必须等于 `args.length` |
| 返回 | `Promise<Array<EntityData>>` |
| 异常 | 失败抛 `ExecutionError('RAW_QUERY', ...)` |
| 上下文限制 | 只做行映射（`ResultSetRow -> DataMapper`），不会执行 `afterLoad` 钩子 |

### `rawQuerySafe(sql, args = [])`

| 项 | 契约 |
|---|---|
| 参数 | 与 `rawQuery` 一致，但先在入口做严格占位符检查 |
| 返回 | 同 `rawQuery` |
| 异常 | 同 `rawQuery` |
| 上下文限制 | 本质是 guard + 委托 `rawQuery` |

### `rawExecute(sql, args = [])`

| 项 | 契约 |
|---|---|
| 参数 | 仅允许 `INSERT/UPDATE/DELETE/REPLACE`；禁止多语句、注释片段、危险关键字；必须参数化且占位符匹配 |
| 返回 | `Promise<void>` |
| 异常 | 失败抛 `ExecutionError('RAW_EXECUTE', ...)`；若命中事务写入守卫则抛 `TransactionRollbackError` |
| 上下文限制 | 成功后执行 `queryCache.clear()`（全量清空） |

## 2. 可运行示例（成功路径）

```arkts
import { Context } from '@kit.AbilityKit'
import {
  ColumnType,
  DatabaseConfig,
  OCORMInit,
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
    config: new DatabaseConfig('raw_sql_contract.db'),
    autoCreateTables: true
  })
}

export async function runRawSqlHappyPath(context: Context): Promise<void> {
  await bootstrap(context)
  const repo = new Repository('User')

  await repo.rawExecute(
    'INSERT INTO users(id, user_name, age) VALUES (?, ?, ?)',
    [1, 'Alice', 20]
  )

  await repo.rawExecute(
    'UPDATE users SET user_name = ? WHERE id = ?',
    ['Alice-Updated', 1]
  )

  const rows = await repo.rawQuerySafe(
    'SELECT id, user_name, age FROM users WHERE age >= ?',
    [18]
  )

  console.info(rows.length) // 1
}
```

## 3. 失败案例 A：`rawQuery` 非参数化

```arkts
import { Context } from '@kit.AbilityKit'
import { Repository } from 'ocorm'

export async function failRawQueryWithoutPlaceholder(context: Context): Promise<void> {
  await bootstrap(context)
  const repo = new Repository('User')
  try {
    await repo.rawQuery('SELECT * FROM users WHERE id = 1')
  } catch (e) {
    // ExecutionError('RAW_QUERY', 'RAW_QUERY 仅允许参数化 SQL...')
    console.error('expected:', e)
  }
}
```

## 4. 失败案例 B：`rawExecute` 多语句

```arkts
import { Context } from '@kit.AbilityKit'
import { Repository } from 'ocorm'

export async function failRawExecuteMultiStatement(context: Context): Promise<void> {
  await bootstrap(context)
  const repo = new Repository('User')
  try {
    await repo.rawExecute(
      'UPDATE users SET user_name = ? WHERE id = ?; DELETE FROM users WHERE id = ?',
      ['A', 1, 1]
    )
  } catch (e) {
    // ExecutionError('RAW_EXECUTE', 'RAW_EXECUTE 不允许执行多条 SQL')
    console.error('expected:', e)
  }
}
```

## 5. 补充说明
- `rawQuerySafe` 建议用于接口层；`rawQuery` 适合内部受控场景。
- 需要“受影响行数”时，不应依赖 `rawExecute`（返回固定 `void`）。
- 若外层存在活动事务且你使用了未绑定仓储，`rawExecute` 会先被事务守卫拦截。


