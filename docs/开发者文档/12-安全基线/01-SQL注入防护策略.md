# 01-SQL注入防护策略

> 状态：已落地
> 适用版本：ocorm 3.x（按当前仓库源码）
> 最后更新：2026-03-28

## 1. 目标

本基线只约束当前仓库已经实现的原始 SQL 防护逻辑，不讨论未落地的“理想策略”。

- `RAW_QUERY` 入口只允许单条、只读 SQL，语句起始必须是 `SELECT`、`WITH` 或 `EXPLAIN`
- `RAW_EXECUTE` 入口只允许单条写入 SQL，语句起始必须是 `INSERT`、`UPDATE`、`DELETE` 或 `REPLACE`
- 失败日志与错误输出必须经过脱敏，避免把 SQL 字面值、路径、长数字标识直接打到日志里

## 2. 基线来源

本页全部结论来自以下真实文件：

- `OCORM/src/main/ets/repository/rawsql/RawSqlGuards.ets`
- `OCORM/src/main/ets/errors/ErrorSanitizer.ets`
- `OCORM/src/main/ets/errors/ErrorCodes.ets`
- `OCORM/src/main/ets/errors/ErrorLocale.ets`
- `OCORM/src/main/ets/logging/Logger.ets`
- `OCORM/src/main/ets/logging/LogLevel.ets`

## 3. 实现级规则

| 入口 | 已实现的强制规则 | 失败语义 |
| --- | --- | --- |
| `validateRawQuerySql(sql)` | SQL 不能为空；只允许单条 SQL；校验时会剥离字符串与注释后再判断；仅允许 `SELECT/WITH/EXPLAIN`；命中写关键字直接拒绝 | 抛出 `RAW_QUERY` 相关错误消息 |
| `validateRawExecuteSql(sql, argsLength)` | SQL 不能为空；只允许单条 SQL；禁止 `--`、`/*`、`*/` 注释片段；只允许 `INSERT/UPDATE/DELETE/REPLACE`；禁止 `DROP/ALTER/CREATE/TRUNCATE/ATTACH/DETACH/VACUUM/REINDEX/PRAGMA`；必须使用 `?` 占位符；占位符数量必须与 `argsLength` 一致 | 抛出 `RAW_EXECUTE` 相关错误消息 |
| `sanitizeErrorMessage(rawMessage)` / `sanitizeSqlPreview(rawSql)` | 替换敏感键值、字符串字面值、长数字、磁盘路径；限制最大长度 | 返回脱敏后的文本 |
| `Logger` | `DEBUG` 才记录查询 SQL；`ERROR`/`WARN` 日志会进行敏感信息脱敏 | 输出 `[ocorm][TYPE][duration] ...` |

需要明确的一点：当前源码里，`validateRawQuerySql` 不校验占位符数量，也不强制只读查询必须参数化。这意味着只读查询的“是否拼接用户输入”不能交给守卫兜底，调用方自己必须禁止字符串拼接。

## 4. 正确示例

下面的用法符合当前实现。

```ts
import {
  countSqlPlaceholders,
  validateRawExecuteSql,
  validateRawQuerySql
} from '../../src/main/ets/repository/rawsql/RawSqlGuards'

const readonlySql = validateRawQuerySql(
  'SELECT id, nickname FROM users WHERE status = ?'
)

const writeSql = validateRawExecuteSql(
  'UPDATE users SET status = ? WHERE id = ?',
  2
)

const placeholderCount = countSqlPlaceholders(writeSql)
// placeholderCount === 2
```

```ts
const explainSql = validateRawQuerySql(
  'EXPLAIN SELECT id FROM users WHERE nickname = ?'
)

const withSql = validateRawQuerySql(`
  WITH active_users AS (
    SELECT id, nickname FROM users WHERE status = 'ACTIVE'
  )
  SELECT id, nickname FROM active_users
`)

// 两条都能通过：一条是 EXPLAIN，只读；另一条是 WITH 开头，且没有写关键字
```

```ts
import { Logger } from '../../src/main/ets/logging/Logger'
import { LogLevel } from '../../src/main/ets/logging/LogLevel'

const logger = Logger.getInstance()
logger.configure(true, LogLevel.DEBUG)
logger.logQuery("SELECT * FROM users WHERE phone = '13800138000'", 12)

// Logger 在 DEBUG 下会记录查询，但会把字符串字面值脱敏成 '[***]'
```

## 5. 误用示例

下面这些写法会被当前守卫拒绝，或者虽然能过守卫，但仍然违反本基线。

```ts
validateRawExecuteSql(
  "UPDATE users SET nickname = 'root' WHERE id = 7",
  0
)

// 失败原因：RAW_EXECUTE 仅允许参数化 SQL（必须使用 ? 占位符）
// 根因：把字面值直接拼进写入 SQL
```

```ts
validateRawExecuteSql(
  'DELETE FROM users WHERE id = ?; DROP TABLE users',
  1
)

// 失败原因：RAW_EXECUTE 不允许执行多条 SQL
// 根因：中间出现分号，多语句被直接拒绝
```

```ts
const keyword = "'ACTIVE' OR 1=1 --"
const riskyQuery = `SELECT id FROM users WHERE status = ${keyword}`
validateRawQuerySql(riskyQuery)

// 这个例子未必被守卫拦下，因为 validateRawQuerySql 只校验只读语义和单语句语义
// 它不会统计占位符，也不会判断“是否把外部输入直接拼进 SELECT”
// 结论：RAW_QUERY 守卫不是字符串拼接的免责条款
```

## 6. 失败语义与排障

`RawSqlGuards.ets` 已经提供了两组“预期守卫失败”识别函数，用于把安全拒绝和其他异常区分开处理。

```ts
import {
  isExpectedRawExecuteGuardError,
  isExpectedRawQueryGuardError,
  validateRawExecuteSql,
  validateRawQuerySql
} from '../../src/main/ets/repository/rawsql/RawSqlGuards'
import { sanitizeErrorMessage, sanitizeSqlPreview } from '../../src/main/ets/errors/ErrorSanitizer'

try {
  validateRawExecuteSql('UPDATE users SET nickname = "root"', 0)
} catch (error) {
  const message = String(error)
  if (isExpectedRawExecuteGuardError(message)) {
    const safeMessage = sanitizeErrorMessage(message)
    const safePreview = sanitizeSqlPreview('UPDATE users SET nickname = "root"')
    // 这里记录脱敏后的失败信息，不回传原始 SQL
  }
}

try {
  validateRawQuerySql('DELETE FROM users WHERE id = 1')
} catch (error) {
  const message = String(error)
  if (isExpectedRawQueryGuardError(message)) {
    const safeMessage = sanitizeErrorMessage(message)
    // 按安全基线，这属于预期拦截，不应当被误判为数据库故障
  }
}
```

常见失败语义如下。

```text
RAW_QUERY
- SQL 语句不能为空
- RAW_QUERY 不允许执行多条 SQL
- RAW_QUERY 仅允许 SELECT/WITH/EXPLAIN 只读 SQL
- RAW_QUERY 禁止写操作 SQL

RAW_EXECUTE
- SQL 语句不能为空
- RAW_EXECUTE 不允许执行多条 SQL
- RAW_EXECUTE 禁止 SQL 注释片段
- RAW_EXECUTE 仅允许 INSERT/UPDATE/DELETE/REPLACE
- RAW_EXECUTE 禁止危险 SQL 关键字
- RAW_EXECUTE 仅允许参数化 SQL（必须使用 ? 占位符）
- RAW_EXECUTE 参数数量与占位符数量不一致
```

排障顺序固定如下：

1. 先看语句入口是否选错：只读 SQL 走 `RAW_QUERY`，写入 SQL 走 `RAW_EXECUTE`
2. 再看是否混入了第二条语句或注释片段：`;`、`--`、`/* */` 都是高频触发点
3. 对 `RAW_EXECUTE`，最后核对 `?` 数量和 `argsLength` 是否一致
4. 如果是 `RAW_QUERY`，额外审计是否存在外部输入字符串拼接；该问题当前守卫不会替你兜底

## 7. 错误脱敏与日志基线

错误码体系里，数据库执行失败统一归类为 `ORM402`；国际化消息中对应模板为“SQL 执行失败: {details}”或 “SQL execution failed: {details}”。安全基线要求这里的 `{details}` 必须先脱敏再出现在日志或上层错误里。

```ts
import { ERROR_SQL_EXECUTION_FAILED } from '../../src/main/ets/errors/ErrorCodes'
import { formatErrorMessage, setErrorLocale } from '../../src/main/ets/errors/ErrorLocale'
import { sanitizeErrorMessage } from '../../src/main/ets/errors/ErrorSanitizer'
import { Logger } from '../../src/main/ets/logging/Logger'
import { LogLevel } from '../../src/main/ets/logging/LogLevel'

setErrorLocale('zh')

const rawDetails = 'SQLITE_ERROR: near "DROP": patient_id=12345678, sql="DELETE FROM users"'
const safeDetails = sanitizeErrorMessage(rawDetails)
const localized = formatErrorMessage(ERROR_SQL_EXECUTION_FAILED, 'SQL 执行失败', {
  entityName: '',
  columnName: '',
  tableName: '',
  operation: '',
  details: safeDetails,
  min: null,
  max: null,
  getValue(key: string) {
    return (this as Record<string, string | number | null>)[key] ?? null
  }
})

const logger = Logger.getInstance()
logger.configure(true, LogLevel.ERROR)
logger.logError(localized)
```

基于当前实现，最低运行要求如下：

- 生产环境不要启用 `LogLevel.DEBUG`，因为即使 SQL 会被脱敏，也没有必要长期暴露完整查询形态
- 对外报错统一走 `sanitizeErrorMessage` 或 `Logger.logError` 的脱敏链路
- 任何“为了定位问题先把原始 SQL 全量打印出来”的临时改动，都应视为违反安全基线

## 8. 验收清单

- 所有 `RAW_EXECUTE` 调用都使用 `?` 占位符，且参数数量与占位符一致
- 所有 `RAW_QUERY` 调用都没有拼接外部输入形成 SQL 字面值
- 没有任何原始 SQL 通过 `ERROR`、`WARN` 或对外异常消息直接暴露
- 出现安全守卫拦截时，调用方能区分“预期拒绝”与“数据库异常”

## 9. 变更记录

- 2026-03-28：从骨架改为基于真实源码的安全基线文档，补充正确示例、误用示例、失败语义与排障方式
- 2026-03-27：创建文档骨架
