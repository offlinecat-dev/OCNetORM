# 03-仓储-事务与原生SQLAPI

> 状态：已完成
> 适用版本：ocorm 3.0.2
> 最后更新：2026-03-28
> 对照源码：`src/main/ets/repository/Repository.ets`、`TransactionOptions.ets`、`BatchInsertOptions.ets`、`BatchInsertResult.ets`

## 1. 覆盖范围

这页覆盖仓储层主入口：

- `Repository`
- `TransactionOptions` / `IsolationLevel`
- `BatchInsertOptions` / `BatchInsertResult`
- `SaveResult` / `DeleteResult` / `TransactionResult`
- `rawQuery()` / `rawQuerySafe()` / `rawExecute()`

深入文档看：

- [`../06-仓储与事务/00-Repository总览.md`](../06-仓储与事务/00-Repository总览.md)
- [`../06-仓储与事务/04-事务执行器-TransactionManager.md`](../06-仓储与事务/04-事务执行器-TransactionManager.md)
- [`../06-仓储与事务/07-原生SQL安全守卫-RawSqlGuards.md`](../06-仓储与事务/07-原生SQL安全守卫-RawSqlGuards.md)

## 2. API 快表

| 类/能力 | 代表方法 | 说明 |
| --- | --- | --- |
| `Repository` CRUD | `save()`、`findById()`、`findAll()`、`remove()`、`removeById()`、`restore()` | 标准实体写入与软删除/恢复 |
| `Repository` 查询辅助 | `count()`、`findPaginated()`、`createQueryBuilder()` | 仓储入口下钻到查询层 |
| `Repository` 事务 | `transaction()`、`transactionWithOptions()` | 单仓储事务回调 |
| `Repository` 批量与关系写入 | `saveAll()`、`batchInsert()`、`attach()`、`detach()`、`sync()` | 批量保存与多对多关系管理 |
| `Repository` 聚合 | `sum()`、`avg()`、`max()`、`min()` | 常用单列聚合 |
| 原生 SQL | `rawQuery()`、`rawQuerySafe()`、`rawExecute()` | 原始查询与执行 |
| 事务选项 | `createDefault()`、`readOnly()`、`withRetry()`、`withTimeout()`、`serializable()` | 构造 `TransactionOptions`（`serializable()` 当前为 fail-fast） |
| 批量选项 | `createDefault()`、`createFast()`、`createSafe()` | 构造 `BatchInsertOptions` |

## 3. 基础 CRUD

```ts
import { Repository } from 'ocorm'

const userRepo = new Repository('User')

const saveResult = await userRepo.save(user)
const saved = await userRepo.findById(1)
const allUsers = await userRepo.findAll()
const total = await userRepo.count()
const deleteResult = await userRepo.removeById(1)
const restoreResult = await userRepo.restore(1)
```

结果对象字段速记：

- `SaveResult`: `success`、`affectedRows`、`insertId`、`errorMessage`
- `DeleteResult`: `success`、`affectedRows`、`errorMessage`
- `TransactionResult`: `success`、`errorMessage`

## 4. 事务调用

默认事务用 `transaction()`；需要只读、超时、隔离级别或重试时，用 `transactionWithOptions()`。

```ts
import { Repository, TransactionOptions } from 'ocorm'

const userRepo = new Repository('User')

const txResult = await userRepo.transaction(async (txRepo) => {
  await txRepo.save(user)
  await txRepo.save(profile)
})

const guardedResult = await userRepo.transactionWithOptions(
  async (txRepo) => {
    await txRepo.save(user)
  },
  TransactionOptions.withTimeout(1500)
)
```

常用事务选项：

```ts
import { TransactionOptions, IsolationLevel } from 'ocorm'

const readOnly = TransactionOptions.readOnly()
const retryable = TransactionOptions.withRetry(2, 100)
const timeoutOnly = TransactionOptions.withTimeout(1200)
const custom = TransactionOptions.fromConfig({
  isolation: IsolationLevel.READ_COMMITTED,
  timeout: 2000,
  retries: 1,
  retryDelay: 50,
  readOnly: false
})

try {
  TransactionOptions.serializable()
} catch (error) {
  // 当前实现对 SERIALIZABLE 采用 fail-fast
}
```

事务安全约束不要猜，直接看：

- [`../12-安全基线/02-事务安全与并发保护.md`](../12-安全基线/02-事务安全与并发保护.md)
- [`../06-仓储与事务/05-事务守卫-嵌套-跨仓库-未绑定写入.md`](../06-仓储与事务/05-事务守卫-嵌套-跨仓库-未绑定写入.md)

## 5. 批量写入与关系写入

```ts
import { BatchInsertOptions, Repository } from 'ocorm'

const userRepo = new Repository('User')
const options = BatchInsertOptions.createSafe()
const batchResult = await userRepo.batchInsert(users, options)

console.info(`allSuccess=${batchResult.isAllSuccess()}`)
console.info(`successRate=${batchResult.getSuccessRate()}`)

await userRepo.attach(1, 7, 'roles')
await userRepo.detach(1, 7, 'roles')
await userRepo.sync(1, [7, 8, 9], 'roles')
```

批量选项选择原则：

- `createFast()`：吞吐优先，适合你已明确输入质量可靠的导入场景
- `createSafe()`：保守模式，适合线上批量写入和回归修复
- `createDefault()`：按当前默认配置走

## 6. 原生 SQL

`rawQuery()` 和 `rawQuerySafe()` 都要求参数化 SQL。区别在于 `rawQuerySafe()` 会走更严格的安全守卫语义；`rawExecute()` 适合不返回结果集的执行语句。

```ts
import { Repository } from 'ocorm'

const userRepo = new Repository('User')

const rows = await userRepo.rawQuerySafe(
  'SELECT id, user_name FROM users WHERE age >= ? AND status = ?',
  [18, 'active']
)

await userRepo.rawExecute(
  'UPDATE users SET last_login_at = ? WHERE id = ?',
  [Date.now(), 1]
)
```

错误示例不要再写：

```ts
import { Repository } from 'ocorm'

const bad = new Repository('User')
await bad.rawQuery(`SELECT * FROM users WHERE user_name = '${userInput}'`)

// 错误点：字符串拼接原生 SQL
```

对应约束与测试：

- [`../12-安全基线/01-SQL注入防护策略.md`](../12-安全基线/01-SQL注入防护策略.md)
- [`../14-测试与验收/04-回归清单-事务-查询-安全.md`](../14-测试与验收/04-回归清单-事务-查询-安全.md)

## 7. 仓储与查询的边界

- 需要领域对象级写入、事务、关系写入、缓存失效时，优先 `Repository`
- 需要复杂过滤、分组、Explain、批量更新/删除时，下钻 `createQueryBuilder()` / `QueryExecutor`
- 不要为了一条简单 CRUD 去手写 `rawExecute()`

```ts
import { QueryExecutor, Repository } from 'ocorm'

const repo = new Repository('User')
const qb = repo.createQueryBuilder().whereLike('user_name', 'A%')
const users = await new QueryExecutor(qb).get()
```

## 8. 继续下钻

- 查询层：[`02-查询-关系与缓存API.md`](./02-查询-关系与缓存API.md)
- 深度章节：[`../06-仓储与事务/00-Repository总览.md`](../06-仓储与事务/00-Repository总览.md)、[`../06-仓储与事务/09-仓储层性能与风险点.md`](../06-仓储与事务/09-仓储层性能与风险点.md)

## 9. 变更记录

- 2026-03-28：补齐 Repository、事务、批量写入和原生 SQL API 速查。
