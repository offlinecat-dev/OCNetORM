# 07-原生SQL安全守卫-RawSqlGuards

> 状态：已完成
> 适用版本：ocorm 3.x（当前仓库实现）
> 最后更新：2026-03-27

## 1. 目标
- 说明 `RawSqlGuards.ets` 如何在仓储层前置拦截危险 SQL。
- 拆清读 SQL 与写 SQL 各自的允许范围。
- 给出 guard 通过与拒绝的最小样例。

## 2. 核心函数
- `countSqlPlaceholders(sql)`
- `validateRawQuerySql(sql)`
- `validateRawExecuteSql(sql, argsLength)`
- `isExpectedRawQueryGuardError(errorMessage)`
- `isExpectedRawExecuteGuardError(errorMessage)`

## 3. 关键规则
### 3.1 `validateRawQuerySql`
- 不能为空
- 不能多语句
- 只允许 `SELECT`、`WITH`、`EXPLAIN`
- 去掉字符串字面量和注释后，不能包含写关键字

```arkts
import { validateRawQuerySql } from 'ocorm'

const sql = validateRawQuerySql('SELECT id, name FROM user WHERE id = ?')
console.info(sql)
```

### 3.2 `validateRawExecuteSql`
- 不能为空
- 不能多语句
- 禁止 `--`、`/* */`
- 只允许 `INSERT/UPDATE/DELETE/REPLACE`
- 禁止 `DROP/ALTER/CREATE/TRUNCATE/ATTACH/DETACH/VACUUM/REINDEX/PRAGMA`
- 必须参数化，且参数数量严格匹配

```arkts
import { validateRawExecuteSql } from 'ocorm'

const sql = validateRawExecuteSql(
  'UPDATE user SET name = ? WHERE id = ?',
  2
)

console.info(sql)
```

### 3.3 占位符计数
两个入口最终都依赖 `countSqlPlaceholders(sql)` 做参数数量校验。

```arkts
import { countSqlPlaceholders } from 'ocorm'

console.info(countSqlPlaceholders('SELECT * FROM user WHERE id = ? AND age > ?'))
```

## 4. 误用示例
下面这些都会被 guard 拒绝。

```arkts
import { validateRawQuerySql } from 'ocorm'

validateRawQuerySql('DELETE FROM user WHERE id = ?')
```

```arkts
import { validateRawExecuteSql } from 'ocorm'

validateRawExecuteSql('UPDATE user SET name = "Alice"', 0)
```

```arkts
import { validateRawExecuteSql } from 'ocorm'

validateRawExecuteSql('PRAGMA journal_mode = WAL', 0)
```

## 5. 守卫错误识别
仓储层会用 `isExpectedRawQueryGuardError(...)` / `isExpectedRawExecuteGuardError(...)` 区分“预期 guard 拒绝”和“真正执行失败”，前者记 warn，后者记 error。

```arkts
import {
  isExpectedRawExecuteGuardError,
  isExpectedRawQueryGuardError
} from 'ocorm'

console.info(isExpectedRawQueryGuardError('RAW_QUERY 仅允许 SELECT/WITH/EXPLAIN 只读 SQL'))
console.info(isExpectedRawExecuteGuardError('RAW_EXECUTE 参数数量与占位符数量不一致'))
```

## 6. 实战规则
- 读 SQL 和写 SQL 的 guard 不是同一个集合，不要混用入口。
- 参数化是第一优先级，连 guard 都过不了时不要去怪底层数据库。
- 需要日志排查时，先看是不是 guard warn，再看是否为执行层 error。

```text
排查顺序:
1. SQL 是否为空 / 多语句
2. 是否包含注释片段
3. 起始关键字是否在允许列表
4. 占位符数量是否和 args 对齐
5. 是否命中危险关键字
```

## 7. 参考源码
- `src/main/ets/repository/rawsql/RawSqlGuards.ets`
- `src/main/ets/repository/Repository.ets`
- `src/main/ets/errors/DatabaseError.ets`

## 8. 变更记录
- 2026-03-27：补全原生 SQL guard 规则、允许范围与误用样例
