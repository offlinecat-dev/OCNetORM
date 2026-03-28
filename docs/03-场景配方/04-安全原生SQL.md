# 04-安全原生SQL

> 状态：已完成
> 适用版本：ocorm 3.x（当前仓库实现）
> 最后更新：2026-03-27

## 1. 目标
- 说明 `Repository.rawQuery`、`rawQuerySafe`、`rawExecute` 的真实使用边界。
- 说明参数化约束、只读/写入约束、结果映射与缓存副作用。
- 明确什么场景应该用原生 SQL，什么场景应回到 `QueryBuilder`。

## 2. 背景与适用范围
原生 SQL 能力由 `Repository.ets` 暴露，但它不是裸奔：
- 读 SQL 要先过 `validateRawQuerySql`
- 写 SQL 要先过 `validateRawExecuteSql`
- 参数个数必须和 `?` 占位符严格匹配
- `rawExecute` 走写入守卫，并在成功后清空查询缓存

## 3. 核心 API 速记
- `rawQuery(sql, args = []): Promise<Array<EntityData>>`
- `rawQuerySafe(sql, args = []): Promise<Array<EntityData>>`
- `rawExecute(sql, args = []): Promise<void>`

## 4. 正确示例
只读查询必须使用参数化 SQL，并且只能是 `SELECT/WITH/EXPLAIN`。

```arkts
import { Repository } from 'ocorm'

const userRepo = new Repository('User')

const rows = await userRepo.rawQuery(
  'SELECT id, name FROM user WHERE age > ?',
  [18]
)

console.info(rows.length)
```

`rawQuerySafe` 比 `rawQuery` 更适合面向接口层暴露，因为它先在入口处做更严格的参数校验。

```arkts
import { Repository } from 'ocorm'

const repo = new Repository('User')

const rows = await repo.rawQuerySafe(
  'WITH active_users AS (SELECT id, name FROM user WHERE deleted_at IS NULL AND age >= ?) SELECT * FROM active_users',
  [18]
)

console.info(rows)
```

写 SQL 应走 `rawExecute`，并明确知道它会清空查询缓存。

```arkts
import { Repository } from 'ocorm'

const repo = new Repository('User')

await repo.rawExecute(
  'UPDATE user SET name = ? WHERE id = ?',
  ['Alice', 1]
)
```

## 5. 误用示例
读 SQL 里不带 `?` 占位符会被拒绝。

```arkts
import { Repository } from 'ocorm'

const repo = new Repository('User')

// 误用：未参数化
await repo.rawQuery('SELECT * FROM user WHERE id = 1')
```

把写操作塞进 `rawQuery` 也会被拒绝。

```arkts
import { Repository } from 'ocorm'

const repo = new Repository('User')

// 误用：rawQuery 禁止写 SQL
await repo.rawQuery('DELETE FROM user WHERE id = ?', [1])
```

`rawExecute` 也不是万能入口，非参数化 SQL、注释片段、多语句、危险关键字都会被拒绝。

```arkts
import { Repository } from 'ocorm'

const repo = new Repository('User')

// 误用：多语句 + 注释
await repo.rawExecute('UPDATE user SET name = ? WHERE id = ?; DELETE FROM user WHERE id = ? -- bad', ['A', 1, 2])
```

## 6. 失败语义与抛错说明
三者失败都会抛 `ExecutionError`：
- `rawQuery` / `rawQuerySafe` 抛 `ExecutionError('RAW_QUERY', message)`
- `rawExecute` 抛 `ExecutionError('RAW_EXECUTE', message)`

```arkts
import { Repository } from 'ocorm'

const repo = new Repository('User')

try {
  await repo.rawQuerySafe('SELECT * FROM user WHERE id = ?', [])
} catch (error) {
  console.error('参数数量与占位符不一致:', error)
}
```

`rawExecute` 受事务守卫影响。如果当前存在未绑定事务上下文写入，它会在真正执行 SQL 前被 `ensureWritePathAllowed('RAW_EXECUTE')` 拦截。

```arkts
import { EntityData, EntityDataInput, Repository } from 'ocorm'

function makeUser(id: number, name: string): EntityData {
  const input = EntityDataInput.create()
  input.set('id', id)
  input.set('name', name)
  return EntityData.from('User', input)
}

const repo = new Repository('User')

try {
  await repo.transaction(async (txRepo) => {
    await txRepo.save(makeUser(1, 'inside'))
    await repo.rawExecute('UPDATE user SET name = ? WHERE id = ?', ['outside', 1])
  })
} catch (error) {
  console.error('未绑定写入被拦截:', error)
}
```

## 7. 结果与副作用
`rawQuery` / `rawQuerySafe` 返回的是 `Array<EntityData>`，不是裸 `ResultSet`。内部会把每行转换成 `ResultSetRow`，再走 `DataMapper.fromResultSetRow(...)`。
这条路径只做结果映射，不会执行 `afterLoad` / `afterLoadBatch`。

`rawExecute` 没有返回行数；它成功即返回 `void`，并执行：

```text
repo.queryCache.clear()
```

如果你的目标是“拿受影响行数”，当前 `rawExecute` 不是最佳入口。

## 8. 实战规则
- 只读 SQL 优先 `rawQuerySafe`，除非你明确需要更灵活的包装。
- 写 SQL 只能用 `rawExecute`，并接受它的缓存清空副作用。
- 参数化是硬性要求，不要试图拼接值到 SQL 字符串里。
- 只要能用 `QueryBuilder`，优先用 `QueryBuilder`；原生 SQL 保留给复杂 CTE、Explain 或 ORM 暂未覆盖的表达式。

## 9. 参考源码

## 10. 变更记录
- 2026-03-27：补全 rawQuery/rawQuerySafe/rawExecute 的边界、参数化规则与失败语义
