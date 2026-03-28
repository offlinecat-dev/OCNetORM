# Repository API 契约

实现依据：`src/main/ets/repository/*.ets`

## `Repository`（CRUD 与聚合）

- 用途：面向实体的读写入口，封装 hooks、软删除、缓存失效、关系写入。
- 参数：
  - 构造：`new Repository(entityName)`
  - 常用：`save/findById/findAll/remove/removeById/restore/count/findPaginated`
- 返回：
  - 写入：`SaveResult` / `DeleteResult`
  - 查询：`EntityData | null` / `EntityData[]` / `PaginatedResult` / `number`
- 异常：
  - 构造时实体未注册：`EntityNotRegisteredError`
  - 底层执行失败统一为 `ExecutionError`
  - hooks 失败可能透传 `HookExecutionError`
- 副作用：
  - 写入路径会执行 hooks
  - 写入后触发缓存失效（实体缓存或全量缓存）
- 事务上下文：默认非事务；若在事务回调内，使用的是事务作用域仓储实例。
- 最小示例：

```ts
import { Repository } from 'ocorm'

const repo = new Repository('User')
const saved = await repo.save(userEntity)
const page = await repo.findPaginated(1, 20)
```

## `transaction(callback)` / `transactionWithOptions(callback, options)`

- 用途：在仓储层执行事务回调，统一处理 commit/rollback。
- 参数：
  - `callback: (repo: Repository) => Promise<void>`
  - `options: TransactionOptions`（仅 `transactionWithOptions`）
- 返回：`Promise<TransactionResult>`
- 异常：
  - 嵌套事务、跨仓储事务嵌套、未绑定上下文启动事务会触发 `TransactionRollbackError`
  - 回调抛错或提交/回滚失败最终统一为事务失败
- 副作用：
  - 开启数据库事务
  - `transactionWithOptions` 支持隔离级别、只读、超时、重试
- 事务上下文：
  - 事务内必须复用回调入参 `repo`
  - 连接池模式下，活动事务期间未绑定上下文写入会被守卫拒绝
- 最小示例：

```ts
import { Repository, TransactionOptions } from 'ocorm'

await new Repository('User').transactionWithOptions(
  async (txRepo) => {
    await txRepo.save(user)
  },
  TransactionOptions.withTimeout(1500)
)
```

## `TransactionOptions`

- 用途：配置事务隔离、超时、重试、只读。
- 参数：
  - `isolation`：`READ_UNCOMMITTED | READ_COMMITTED | REPEATABLE_READ | SERIALIZABLE`
  - `timeout`：毫秒，默认 `30000`
  - `retries/retryDelay`
  - `readOnly`
- 返回：`TransactionOptions`
- 异常与约束：
  - 运行时仅支持 `READ_UNCOMMITTED/READ_COMMITTED`
  - `REPEATABLE_READ/SERIALIZABLE` 在执行期会失败
  - `TransactionOptions.serializable()` 直接抛 `Error`
- 副作用：无（纯配置对象）。
- 事务上下文：用于 `transactionWithOptions`。
- 最小示例：

```ts
import { TransactionOptions, IsolationLevel } from 'ocorm'

const opts = TransactionOptions.fromConfig({
  isolation: IsolationLevel.READ_COMMITTED,
  timeout: 2000,
  retries: 1,
  retryDelay: 100
})
```

## 事务超时语义（`transactionWithOptions`）

- 以 `Promise.race` 实现超时，超时后立即向调用方返回失败（`事务超时 (Nms)`）。
- 超时不代表底层立即结束：事务清理可能在后台继续执行。
- 事务锁与连接租约会在后台清理完成后释放，防止并发误写。

## `rawQuery(sql, args)` / `rawQuerySafe(sql, args)`

- 用途：执行只读原生 SQL，返回 `EntityData[]`。
- 参数：
  - `sql: string`
  - `args: ValueType[]`
- 返回：`Promise<EntityData[]>`
- 异常（安全守卫）：
  - SQL 不能为空、多语句、写语句、危险关键字会失败
  - 必须使用 `?` 参数占位符，且数量与 `args.length` 严格一致
- 副作用：
  - 记录查询日志
  - 触发慢查询事件（`RAW_QUERY`）
- 事务上下文：可在事务内执行；不主动开启事务。
- 最小示例：

```ts
const rows = await repo.rawQuerySafe(
  'SELECT id, user_name FROM users WHERE age >= ? AND status = ?',
  [18, 'active']
)
```

## `rawExecute(sql, args)`

- 用途：执行原生写 SQL（无返回结果集）。
- 参数：`sql: string`, `args: ValueType[]`
- 返回：`Promise<void>`
- 异常（强约束）：
  - 只允许 `INSERT/UPDATE/DELETE/REPLACE`
  - 禁止多语句、注释片段、危险关键字（如 `DROP/ALTER/PRAGMA`）
  - 必须参数化且占位符数量匹配
- 副作用：
  - 执行写入 SQL
  - 出于保守策略，执行后清空 `QueryCache`
  - 触发慢查询事件（`RAW_EXECUTE`）
- 事务上下文：写入路径受事务守卫约束。
- 最小示例：

```ts
await repo.rawExecute(
  'UPDATE users SET last_login_at = ? WHERE id = ?',
  [Date.now(), 1]
)
```

## `batchInsert(entities, options)` / `saveAll(entities)`

- 用途：批量写入。
- 参数：
  - `batchInsert`: `entities: EntityData[]`, `options?: BatchInsertOptions`
  - `saveAll`: `entities: EntityData[]`
- 返回：
  - `batchInsert`: `BatchInsertResult`
  - `saveAll`: `SaveResult[]`
- 异常：
  - 严格事务上下文内，任何失败子项会被提升为 `ExecutionError`
- 副作用：
  - 可能执行局部事务（由 `BatchInsertOptions.useTransaction` 决定）
  - 可能执行 hooks / validation（由选项控制）
- 事务上下文：受写入守卫约束。
- 最小示例：

```ts
import { BatchInsertOptions } from 'ocorm'

const result = await repo.batchInsert(users, BatchInsertOptions.createSafe())
```

## 并发事务限制（必须遵守）

- 不支持同一 `Repository` 嵌套 `transaction/transactionWithOptions`。
- 检测到连接级事务激活时，事务边界外写入会被拒绝。
- 连接池模式下，若存在活动事务且启用了写守卫，未绑定事务上下文写入会被拒绝。
