# 03-事务选项-TransactionOptions

> 状态：已完成
> 适用版本：ocorm 3.x（当前仓库）
> 最后更新：2026-03-27

## 1. 目标
说明 `TransactionOptions.ets` 中各字段和工厂方法的真实含义，以及这些选项被 `TransactionManager.ets` 消费后的实际限制。

这份文档只描述当前源码已经实现的能力，不替未来版本做承诺。

## 2. 背景与适用范围
`TransactionOptions` 本身只是一个轻量配置载体，真正的事务语义由 `Repository.transactionWithOptions(...)` 和 `TransactionManager.transactionWithOptions(...)` 实现。

因此，理解这组选项不能只看字段定义，还必须结合事务执行器的真实行为：
- 哪些隔离级别会直接失败
- `readOnly` 是否依赖底层 `PRAGMA query_only`
- 超时和重试是如何生效的

## 3. 核心 API 速记
- `IsolationLevel.READ_UNCOMMITTED`
- `IsolationLevel.READ_COMMITTED`
- `IsolationLevel.REPEATABLE_READ`
- `IsolationLevel.SERIALIZABLE`
- `TransactionOptions.createDefault()`
- `TransactionOptions.fromConfig(config)`
- `TransactionOptions.readOnly()`
- `TransactionOptions.withRetry(retries, retryDelay?)`
- `TransactionOptions.withTimeout(timeout)`
- `TransactionOptions.serializable()`

## 4. 默认值与工厂方法
`TransactionOptions` 的默认值非常明确：
- `isolation = READ_COMMITTED`
- `timeout = 30000`
- `retries = 0`
- `retryDelay = 100`
- `readOnly = false`

`createDefault()` 只是返回一个新的默认实例，没有额外逻辑。`fromConfig(...)` 也是逐字段覆写，不做额外校验。

```ts
import { TransactionOptions, IsolationLevel } from 'ocorm'

const defaults = TransactionOptions.createDefault()
console.info(
  defaults.isolation === IsolationLevel.READ_COMMITTED,
  defaults.timeout,
  defaults.retries,
  defaults.retryDelay,
  defaults.readOnly
)
```

`fromConfig(...)` 只覆盖你显式提供的字段，未提供的字段仍然沿用默认值。

```ts
import { TransactionOptions, IsolationLevel } from 'ocorm'

const options = TransactionOptions.fromConfig({
  isolation: IsolationLevel.READ_UNCOMMITTED,
  timeout: 5000
})

console.info(options.isolation, options.timeout, options.retries, options.readOnly)
```

几个便捷工厂方法都很“窄”：
- `readOnly()` 只会把 `readOnly` 设为 `true`
- `withRetry(...)` 只设置 `retries` 和 `retryDelay`
- `withTimeout(...)` 只设置 `timeout`

```ts
import { TransactionOptions } from 'ocorm'

const readOnlyOptions = TransactionOptions.readOnly()
const retryOptions = TransactionOptions.withRetry(3, 200)
const timeoutOptions = TransactionOptions.withTimeout(8000)

console.info(readOnlyOptions.readOnly, retryOptions.retries, timeoutOptions.timeout)
```

## 5. 隔离级别的真实限制
枚举里定义了 4 个值，但事务执行器当前只支持两种路径：
- `READ_COMMITTED`
- `READ_UNCOMMITTED`

在 `TransactionManager.applyIsolationLevel(...)` 里：
- `READ_UNCOMMITTED` 会尝试执行 `PRAGMA read_uncommitted = 1`
- `READ_COMMITTED` 会尝试执行 `PRAGMA read_uncommitted = 0`
- `REPEATABLE_READ` / `SERIALIZABLE` 会直接抛 `TransactionRollbackError`

另外，`TransactionOptions.serializable()` 甚至不会等到事务执行阶段，它会立即 `throw new Error(...)`。

## 6. 正确示例
最常见的做法是显式组装一个选项对象，再传给 `transactionWithOptions(...)`。

```ts
import { EntityData, EntityDataInput, IsolationLevel, Repository, TransactionOptions } from 'ocorm'

function makeUser(id: number, name: string): EntityData {
  const input = EntityDataInput.create()
  input.set('id', id)
  input.set('name', name)
  return EntityData.from('User', input)
}

const userRepo = new Repository('User')

const options = TransactionOptions.fromConfig({
  isolation: IsolationLevel.READ_COMMITTED,
  timeout: 10000,
  retries: 1,
  retryDelay: 200,
  readOnly: false
})

await userRepo.transactionWithOptions(async (txRepo) => {
  await txRepo.save(makeUser(801, 'Tx-User'))
}, options)
```

只读事务可以使用 `readOnly()` 起步，再按需覆写其他字段。是否真正可用，取决于底层平台是否支持 `PRAGMA query_only`。

```ts
import { Repository } from 'ocorm'
import { TransactionOptions } from 'ocorm'

const userRepo = new Repository('User')
const options = TransactionOptions.readOnly()
options.timeout = 3000

await userRepo.transactionWithOptions(async (txRepo) => {
  await txRepo.findAll()
}, options)
```

如果你只需要超时或重试，也可以使用便捷方法后再补其他字段。

```ts
import { Repository } from 'ocorm'
import { TransactionOptions, IsolationLevel } from 'ocorm'

const userRepo = new Repository('User')
const options = TransactionOptions.withRetry(2, 150)
options.isolation = IsolationLevel.READ_UNCOMMITTED
options.timeout = 5000

await userRepo.transactionWithOptions(async (txRepo) => {
  await txRepo.findById(1)
}, options)
```

## 7. 误用示例
最明显的误用是把枚举里声明的值当成“全部已支持”。当前实现并不是这样。

```ts
import { Repository } from 'ocorm'
import { TransactionOptions, IsolationLevel } from 'ocorm'

const userRepo = new Repository('User')

const options = TransactionOptions.fromConfig({
  isolation: IsolationLevel.REPEATABLE_READ
})

await userRepo.transactionWithOptions(async (txRepo) => {
  await txRepo.findAll()
}, options)
```

另一个误用是把 `serializable()` 当作可用工厂。它在 `TransactionOptions.ets` 里直接抛错，不会返回选项对象。

```ts
import { TransactionOptions } from 'ocorm'

// 误用：这里会立即抛 Error
const options = TransactionOptions.serializable()
console.info(options)
```

还有一种误用更隐蔽：把非正数超时写进 `withTimeout(...)` 或 `fromConfig(...)`，并假设框架会自动修正。`TransactionOptions` 本身不做这类参数清洗。

```ts
import { Repository } from 'ocorm'
import { TransactionOptions } from 'ocorm'

const userRepo = new Repository('User')
const options = TransactionOptions.withTimeout(0)

await userRepo.transactionWithOptions(async (txRepo) => {
  await txRepo.findAll()
}, options)
```

## 8. 失败语义与抛错说明
事务执行器会把一部分配置错误视为“不可重试错误”，直接停止重试并抛出 `TransactionRollbackError`。这些情况包括：
- 不支持的事务隔离级别
- 当前平台不支持 `READ_UNCOMMITTED`
- 当前平台不支持只读事务
- 设置隔离级别或只读模式失败

```ts
import { Repository } from 'ocorm'
import { TransactionOptions, IsolationLevel } from 'ocorm'

const userRepo = new Repository('User')

try {
  const options = TransactionOptions.fromConfig({
    isolation: IsolationLevel.REPEATABLE_READ,
    retries: 3
  })

  await userRepo.transactionWithOptions(async (txRepo) => {
    await txRepo.findAll()
  }, options)
} catch (e) {
  console.error('配置错误不会按业务失败无限重试:', e)
}
```

只读事务不是静态类型约束，而是运行时约束。如果底层支持 `query_only`，写操作会在执行时失败并触发回滚。

```ts
import { EntityData, EntityDataInput, Repository, TransactionOptions } from 'ocorm'

function makeUser(id: number, name: string): EntityData {
  const input = EntityDataInput.create()
  input.set('id', id)
  input.set('name', name)
  return EntityData.from('User', input)
}

const userRepo = new Repository('User')

try {
  await userRepo.transactionWithOptions(async (txRepo) => {
    await txRepo.save(makeUser(901, 'should-fail'))
  }, TransactionOptions.readOnly())
} catch (e) {
  console.error('只读事务中的写入会失败:', e)
}
```

超时也不是“软提示”。`TransactionManager` 使用 `Promise.race` 监控超时，超时后会进入后台清理并向上抛出事务回滚错误。

```ts
import { Repository } from 'ocorm'
import { TransactionOptions } from 'ocorm'

const userRepo = new Repository('User')

try {
  await userRepo.transactionWithOptions(async (_txRepo) => {
    await new Promise<void>((resolve) => setTimeout(() => resolve(), 5000))
  }, TransactionOptions.withTimeout(100))
} catch (e) {
  console.error('事务超时:', e)
}
```

## 9. 实战规则
- 不要被 `IsolationLevel` 枚举误导，当前实际可用的只有 `READ_COMMITTED` 和 `READ_UNCOMMITTED`。
- 想要只读事务时，先接受一个现实：是否可用取决于底层 `PRAGMA query_only` 支持。
- `TransactionOptions` 是配置载体，不会帮你修正不合理的 `timeout` 或 `retries`。
- 需要组合多个选项时，优先 `createDefault()` / `fromConfig(...)` 后再做局部覆写，语义更清楚。

## 10. 参考源码
- `src/main/ets/repository/TransactionOptions.ets`
- `src/main/ets/repository/TransactionManager.ets`
- `src/main/ets/repository/Repository.ets`
- `src/main/ets/errors/TransactionError.ets`

## 11. 变更记录
- 2026-03-27：补全事务选项默认值、工厂方法、隔离级别限制与失败语义说明
