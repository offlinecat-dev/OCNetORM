# Session与StoreLease

## 目标
明确 `DatabaseSession` 与 `StoreLease` 的职责边界：Session 负责连接选择，Lease 负责连接生命周期归还。

## 真实接口
- `DatabaseSession.sessionId`
- `getReadStore()` / `getWriteStore()`
- `bindTransactionStore(lease)` / `getTransactionStore()`
- `StoreLease.isReleased()` / `StoreLease.release()`

## 生命周期调用序列
```text
非事务路径
  session.getReadStore/getWriteStore
    -> manager.acquireStoreLease()
    -> 返回 StoreLease
  业务完成 -> lease.release()

事务路径
  事务启动时获取 lease
  session.bindTransactionStore(lease)
  后续 getReadStore/getWriteStore 始终返回同一 lease
  事务结束统一 release
```

## 使用样例：事务内固定连接
```ts
import { DatabaseManager } from '../../src/main/ets/database/DatabaseManager'
import { DefaultDatabaseSession } from '../../src/main/ets/database/session/DatabaseSession'

async function runInSingleTransactionSession(): Promise<void> {
  const manager = DatabaseManager.getInstance()
  const session = new DefaultDatabaseSession(manager)

  const txLease = await manager.acquireStoreLease(1000)
  session.bindTransactionStore(txLease)

  try {
    const writeLease = await session.getWriteStore()
    await writeLease.store.executeSql('INSERT INTO user(name) VALUES (?)', ['alice'])

    const readLease = await session.getReadStore()
    await readLease.store.querySql('SELECT * FROM user WHERE name = ?', ['alice'])
  } finally {
    txLease.release()
  }
}
```

## 并发控制示例：配合 QuerySlotGate
```ts
import { DatabaseManager } from '../../src/main/ets/database/DatabaseManager'
import { DefaultDatabaseSession } from '../../src/main/ets/database/session/DatabaseSession'

async function guardedRead(session: DefaultDatabaseSession): Promise<void> {
  const manager = DatabaseManager.getInstance()
  await manager.acquireQuerySlot()
  let lease = await session.getReadStore()
  try {
    await lease.store.querySql('SELECT 1')
  } finally {
    manager.releaseQuerySlot()
    if (session.getTransactionStore() === null) {
      lease.release()
    }
  }
}
```

## 故障复现脚本：重复释放校验（幂等）
```ts
import { DatabaseManager } from '../../src/main/ets/database/DatabaseManager'

async function reproduceDoubleRelease(): Promise<void> {
  const manager = DatabaseManager.getInstance()
  const lease = await manager.acquireStoreLease(500)

  lease.release()
  lease.release() // 幂等，不应再次污染池状态

  console.info(`isReleased=${lease.isReleased()}`)
}
```

## 排障清单
- 事务中若未 `bindTransactionStore`，读写可能落到不同连接。
- 非事务路径遗漏 `lease.release()` 会直接放大连接池压力。
- `session.getTransactionStore() !== null` 时不要在中途释放该 lease。

## 关键源码路径
- `OCORM/src/main/ets/database/session/DatabaseSession.ets`
- `OCORM/src/main/ets/database/session/SessionStoreResolver.ets`
- `OCORM/src/main/ets/database/pool/StoreLease.ets`
- `OCORM/src/main/ets/database/DatabaseManager.ets`
