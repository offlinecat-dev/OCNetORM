# 04-事务执行器-TransactionManager

> 状态：已完成
> 适用版本：ocorm 3.x（当前仓库实现）
> 最后更新：2026-03-27

## 1. 目标
- 说明 `TransactionManager.ets` 在当前仓库中的真实事务执行路径。
- 说明普通事务与带选项事务在超时、重试、只读、隔离级别上的行为差异。
- 明确哪些失败会直接抛 `TransactionRollbackError`，哪些会先进入后台清理。

## 2. 背景与适用范围
`Repository.transaction(...)` 和 `Repository.transactionWithOptions(...)` 最终都落到 `TransactionManager`。这一层负责：
- 获取 `StoreLease`
- 给连接加事务锁
- `beginTransaction / commit / rollBack`
- 可选只读事务与 `PRAGMA read_uncommitted`
- 超时后的后台清理与资源释放

如果你只是想在业务代码里开事务，应优先通过 `Repository` 调用，而不是手动 new `TransactionManager`。

## 3. 核心 API 速记
- `transaction(action)`
- `transactionWithOptions(action, options)`
- `TransactionOptions.createDefault()`
- `TransactionOptions.withTimeout(timeout)`
- `TransactionOptions.withRetry(retries, retryDelay)`
- `TransactionOptions.readOnly()`
- `TransactionOptions.fromConfig(config)`
- `TransactionManager.hasAnyActiveTransaction()`

## 4. 关键语义
### 4.1 普通事务路径
普通事务路径很直接：取连接、加锁、`beginTransaction`、执行回调、成功则 `commit`、失败则 `rollBack`。

```text
Repository.transaction(...)
  -> TransactionManager.acquireTransactionLeaseOrThrow()
  -> TransactionManager.acquireTransactionLock(store)
  -> store.beginTransaction()
  -> action(store)
  -> store.commit()
  -> releaseLock()
  -> lease.release()
```

### 4.2 带选项事务路径
`transactionWithOptions(...)` 多了三层能力：
- 超时：`Promise.race` 抢先返回，后台继续清理
- 重试：按 `retries + 1` 次循环执行
- 配置：只读事务、隔离级别、超时、重试延迟

```arkts
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
  timeout: 5000,
  retries: 1,
  retryDelay: 200,
  readOnly: false
})

await userRepo.transactionWithOptions(async (txRepo) => {
  await txRepo.save(makeUser(1, 'inside-tx'))
}, options)
```

### 4.3 超时不是“立刻停止数据库动作”
源码里的超时语义是“调用方先返回超时错误，底层执行继续清理”。如果清理还没结束，`pendingCleanupCount` 会先加一，直到清理完成再减回去。

```arkts
import { Repository } from 'ocorm'
import { TransactionOptions } from 'ocorm'

const repo = new Repository('User')

try {
  await repo.transactionWithOptions(async (_txRepo) => {
    await new Promise<void>((resolve) => setTimeout(resolve, 500))
  }, TransactionOptions.withTimeout(10))
} catch (error) {
  console.error('调用侧先收到超时:', error)
}
```

### 4.4 隔离级别不是都可用
- `READ_COMMITTED` 是默认值。
- `READ_UNCOMMITTED` 通过 `PRAGMA read_uncommitted = 1` 尝试开启。
- `REPEATABLE_READ`、`SERIALIZABLE` 当前实现不提供强语义，配置时会显式失败或直接拒绝。

## 5. 正确示例
需要原子写入时，优先通过 `Repository.transaction(...)` 获取受控的 `txRepo`。

```arkts
import { Repository } from 'ocorm'

const accountRepo = new Repository('Account')

await accountRepo.transaction(async (txRepo) => {
  await txRepo.rawExecute('UPDATE account SET balance = balance - ? WHERE id = ?', [100, 1])
  await txRepo.rawExecute('UPDATE account SET balance = balance + ? WHERE id = ?', [100, 2])
})
```

需要带只读与超时策略时，再使用 `transactionWithOptions(...)`。

```arkts
import { Repository } from 'ocorm'
import { TransactionOptions } from 'ocorm'

const repo = new Repository('User')

const result = await repo.transactionWithOptions(async (txRepo) => {
  const rows = await txRepo.findAll()
  console.info(rows.length)
}, TransactionOptions.readOnly())

console.info(result.success)
```

## 6. 误用示例
下面的误用是把“超时”理解成“底层动作已经停止”。当前实现不是取消执行，而是进入后台清理。

```arkts
import { Repository } from 'ocorm'
import { TransactionOptions } from 'ocorm'

const repo = new Repository('User')

try {
  await repo.transactionWithOptions(async (_txRepo) => {
    await new Promise<void>((resolve) => setTimeout(resolve, 1000))
  }, TransactionOptions.withTimeout(50))

  // 误用：假设这里之后绝对没有任何事务尾部清理
  console.info('数据库一定完全空闲')
} catch (error) {
  console.error(error)
}
```

另一个误用是为不支持的隔离级别强行配置选项。

```arkts
import { TransactionOptions } from 'ocorm'

// 误用：当前实现直接拒绝 SERIALIZABLE
const options = TransactionOptions.serializable()
console.info(options)
```

## 7. 失败语义与抛错说明
普通事务和带选项事务最终都会把失败包装成 `TransactionRollbackError`。差异在于超时分支会先构造 `TransactionTimeoutPendingError`，再在外层转成回滚错误抛给调用方。

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
    await txRepo.save(makeUser(10, 'A'))
    throw new Error('mock failure')
  })
} catch (error) {
  console.error('事务失败并已回滚:', error)
}
```

如果回滚本身失败，错误会升级成“原始错误 + 回滚错误”的组合信息。

```text
原始错误: <业务异常>
回滚错误: <rollBack 失败信息>
```

## 8. 实战规则
- 业务层默认走 `Repository.transaction(...)`，不要自己拼接 `beginTransaction / commit / rollBack`。
- 使用超时事务时，要接受“调用方先返回、清理稍后结束”的现实语义。
- 只读事务和 `READ_UNCOMMITTED` 都是能力探测型行为，不要假设所有平台都支持。
- 需要重试时优先重试幂等逻辑，不要把非幂等写入直接塞进 `retries > 0` 的事务。

## 9. 参考源码
- `src/main/ets/repository/TransactionManager.ets`
- `src/main/ets/repository/TransactionOptions.ets`
- `src/main/ets/repository/TransactionResult.ets`
- `src/main/ets/errors/TransactionError.ets`
- `src/main/ets/repository/Repository.ets`

## 10. 变更记录
- 2026-03-27：补全事务执行路径、超时/重试/只读语义与失败边界说明
