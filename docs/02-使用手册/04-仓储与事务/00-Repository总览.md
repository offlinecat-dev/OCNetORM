# 00-Repository总览

> 状态：已完成
> 适用版本：ocorm 3.x（当前仓库）
> 最后更新：2026-03-27

## 1. 目标
`Repository` 是实体读写的统一入口，封装 CRUD、批量写入、事务、关系维护、原生 SQL 与写入守卫。

## 2. 背景与适用范围
- 适用于通过实体名创建仓储并执行数据库读写。
- 读操作示例：`findById`、`findAll`、`count`、`findPaginated`。
- 写操作示例：`save`、`remove`、`batchInsert`、`attach/detach/sync`、`rawExecute`。

## 3. 核心 API（来自真实源码）
- 构造：`new Repository(entityName: string)`
- 基础读写：`save`、`findById`、`findAll`、`remove`、`removeById`、`restore`
- 事务：`transaction`、`transactionWithOptions`
- 批量：`saveAll`、`batchInsert(entities, options?)`
- 关系：`attach`、`detach`、`sync`
- 原生 SQL：`rawQuery`、`rawQuerySafe`、`rawExecute`

## 4. 正确示例
```ts
import { EntityData, EntityDataInput, Repository } from 'ocorm'

function makeUser(id: number, name: string): EntityData {
  const input = EntityDataInput.create()
  input.set('id', id)
  input.set('name', name)
  return EntityData.from('User', input)
}

const userRepo = new Repository('User')

const saveResult = await userRepo.save(makeUser(1, 'Alice'))
if (!saveResult.success) {
  // 非严格事务下可能返回失败结果而非抛错
  console.error(saveResult.errorMessage)
}

const one = await userRepo.findById(1)
const total = await userRepo.count()
console.info(one, total)
```

```ts
import { EntityData, EntityDataInput, Repository } from 'ocorm'

function makeUser(id: number, name: string): EntityData {
  const input = EntityDataInput.create()
  input.set('id', id)
  input.set('name', name)
  return EntityData.from('User', input)
}

const userRepo = new Repository('User')

await userRepo.transaction(async (txRepo) => {
  await txRepo.save(makeUser(10, 'TxUser'))
  await txRepo.rawExecute('UPDATE user SET name = ? WHERE id = ?', ['TxUserV2', 10])
})
```

## 5. 误用示例（会触发守卫）
```ts
import { EntityData, EntityDataInput, Repository } from 'ocorm'

function makeUser(id: number, name: string): EntityData {
  const input = EntityDataInput.create()
  input.set('id', id)
  input.set('name', name)
  return EntityData.from('User', input)
}

const userRepo = new Repository('User')

await userRepo.transaction(async (txRepo) => {
  await txRepo.save(makeUser(100, 'InTx'))

  // 误用：在事务回调里使用“外部 repo”写入
  // 可能触发 RepositoryTransactionGuardSupport 的写入拦截
  await userRepo.save(makeUser(101, 'OutOfTxWrite'))
})
```

```ts
import { Repository } from 'ocorm'

const userRepo = new Repository('User')

// 误用：把写 SQL 放到 rawQuery（只读入口）
await userRepo.rawQuery('UPDATE user SET name = ? WHERE id = ?', ['Bad', 1])
```

## 6. 失败语义与抛错说明
```ts
import { Repository } from 'ocorm'

const userRepo = new Repository('User')

try {
  // rawQuerySafe 要求必须有 ? 占位符，且参数数量匹配
  await userRepo.rawQuerySafe('SELECT * FROM user WHERE id = 1', [])
} catch (e) {
  // Repository 内部会抛 ExecutionError('RAW_QUERY', ...)
  console.error(e)
}
```

- `new Repository('UnknownEntity')`：实体未注册时，构造阶段抛 `EntityNotRegisteredError`。
- `transaction/transactionWithOptions` 内部失败：由 `事务执行层` 转换为 `TransactionRollbackError`（含回滚语义）。
- 严格事务上下文中（回调提供的 `txRepo`）若 `save/remove/batchInsert` 返回失败结果，仓储会升级为 `ExecutionError` 抛出，保证失败即中断。
- `rawQuery/rawQuerySafe`：
  - 非参数化 SQL（无 `?`）会被拒绝。
  - 参数个数与占位符不一致会抛错。
- `rawExecute`：受 `RawSqlGuards` 与事务守卫限制，违规 SQL 或越界写入会抛 `ExecutionError('RAW_EXECUTE', ...)`。

## 7. 设计约束速记
- 写操作必须优先使用事务回调传入的 `repo`，不要跨上下文写入。
- 原生 SQL：读走 `rawQuery/rawQuerySafe`，写走 `rawExecute`。
- 批量导入优先 `batchInsert`，并根据场景设置 `BatchInsertOptions`。

## 8. 参考源码


