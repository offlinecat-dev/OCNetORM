# 07-原生SQL安全守卫-RawSqlGuards

> 状态：已完成  
> 适用版本：ocorm 3.x  
> 最后更新：2026-03-28

## 1. 这页讲什么
这页讲的是 `rawQuery/rawQuerySafe/rawExecute` 在仓储层的安全语义，以及业务侧该如何正确使用。  
注意：`RawSqlGuards` 是内部实现，不是面向库使用者的公共 API。

## 2. 对外可用入口（公共 API）
- `Repository.rawQuery(sql, args)`：只读 SQL（`SELECT/WITH/EXPLAIN`）
- `Repository.rawQuerySafe(sql, args)`：在入口先做严格校验，再执行只读 SQL
- `Repository.rawExecute(sql, args)`：写 SQL（`INSERT/UPDATE/DELETE/REPLACE`）

## 3. 内部守卫（仅源码实现）
以下函数位于 `src/main/ets/repository/rawsql/RawSqlGuards.ets`，由仓储入口自动调用：
- `countSqlPlaceholders(sql)`
- `validateRawQuerySql(sql)`
- `validateRawExecuteSql(sql, argsLength)`
- `isExpectedRawQueryGuardError(message)`
- `isExpectedRawExecuteGuardError(message)`

业务代码不应直接 import 这些函数。

## 4. 正确用法（可复制）
```ts
import { ExecutionError, Repository } from 'ocorm'

const repo = new Repository('User')

try {
  const rows = await repo.rawQuery(
    'SELECT id, name FROM user WHERE id = ?',
    [1]
  )
  console.info(rows.length)

  const affected = await repo.rawExecute(
    'UPDATE user SET name = ? WHERE id = ?',
    ['Alice', 1]
  )
  console.info(affected)
} catch (error) {
  if (error instanceof ExecutionError) {
    console.error(error.message)
  }
  throw error
}
```

## 5. 失败示例与修复
```ts
import { Repository } from 'ocorm'

const repo = new Repository('User')

// 失败1：rawQuery 不能执行写 SQL
await repo.rawQuery('DELETE FROM user WHERE id = ?', [1])

// 失败2：rawExecute 必须参数化且参数数量匹配
await repo.rawExecute('UPDATE user SET name = \"Alice\" WHERE id = 1', [])
```

修复方式：
- `rawQuery` 只用于只读 SQL
- `rawExecute` 只用于写 SQL
- 一律使用 `?` 占位符，并确保 `?` 数量与参数数组长度一致

## 6. 排查顺序
1. SQL 是否为空或多语句  
2. 是否包含注释片段（`--`、`/* */`）  
3. 起始关键字是否符合入口约束  
4. 占位符数量是否与参数数量一致  
5. 是否命中危险关键字

## 7. 源码对齐路径
- `src/main/ets/repository/Repository.ets`
- `src/main/ets/repository/rawsql/RawSqlGuards.ets`
- `src/main/ets/errors/DatabaseError.ets`
