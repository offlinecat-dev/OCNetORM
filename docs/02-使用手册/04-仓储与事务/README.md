# 04-仓储与事务

## 文档目标
本目录对齐 `src/main/ets/repository/**` 的真实行为，重点覆盖：
- 事务 API（`transaction/transactionWithOptions`）
- 事务守卫（嵌套、跨仓库、未绑定写入）
- 原生 SQL（`rawQuery/rawQuerySafe/rawExecute`）
- 并发与连接上下文保护（事务锁、连接池写入保护）

## 核心契约速览

| API | 参数契约 | 返回契约 | 异常契约 | 上下文限制 |
|---|---|---|---|---|
| `transaction(callback)` | `callback(repo)` 必须使用回调内 `repo` | `Promise<TransactionResult>`，成功时 `success=true` | 失败抛 `TransactionRollbackError` | 不支持同仓库/跨仓库嵌套启动事务 |
| `transactionWithOptions(callback, options)` | `options` 支持 `isolation/timeout/retries/retryDelay/readOnly` | 同上 | 失败抛 `TransactionRollbackError` | 超时后可能先返回错误，回滚在后台收敛完成 |
| `rawQuery(sql, args)` | 仅 `SELECT/WITH/EXPLAIN`；必须参数化且占位符数匹配 | `Promise<EntityData[]>` | 失败抛 `ExecutionError('RAW_QUERY', ...)` | 不执行 `afterLoad` 钩子，仅做行映射 |
| `rawQuerySafe(sql, args)` | 在入口先严格做占位符校验，然后委托 `rawQuery` | 同上 | 同上 | 适合对外暴露 |
| `rawExecute(sql, args)` | 仅 `INSERT/UPDATE/DELETE/REPLACE`；必须参数化 | `Promise<void>` | 失败抛 `ExecutionError('RAW_EXECUTE', ...)` 或事务守卫抛 `TransactionRollbackError` | 成功后执行 `queryCache.clear()` |

## 可运行示例（事务 + 原生 SQL 正常路径）

```arkts
import { Context } from '@kit.AbilityKit'
import {
  ColumnType,
  DatabaseConfig,
  EntityData,
  EntityDataInput,
  OCORMInit,
  Repository,
  defineEntity
} from 'ocorm'

async function bootstrap(context: Context): Promise<void> {
  defineEntity('User', {
    tableName: 'users',
    columns: [
      { property: 'id', name: 'id', type: ColumnType.INTEGER, primaryKey: true, autoIncrement: false },
      { property: 'name', name: 'user_name', type: ColumnType.TEXT }
    ]
  })

  await OCORMInit(context, {
    config: new DatabaseConfig('repo_contract.db').setPooledWriteGuardMode('global'),
    autoCreateTables: true
  })
}

function makeUser(id: number, name: string): EntityData {
  const input = EntityDataInput.create()
  input.set('id', id)
  input.set('name', name)
  return EntityData.from('User', input)
}

export async function runRepositoryHappyPath(context: Context): Promise<void> {
  await bootstrap(context)
  const repo = new Repository('User')

  await repo.transaction(async (txRepo) => {
    await txRepo.save(makeUser(1, 'A'))
    await txRepo.rawExecute('UPDATE users SET user_name = ? WHERE id = ?', ['A-1', 1])
  })

  const rows = await repo.rawQuerySafe('SELECT id, user_name FROM users WHERE id = ?', [1])
  console.info(rows.length)
}
```

## 失败案例（嵌套事务被拒绝）

```arkts
import { Context } from '@kit.AbilityKit'
import { Repository } from 'ocorm'

export async function failNestedTransaction(context: Context): Promise<void> {
  await bootstrap(context)
  const repo = new Repository('User')
  try {
    await repo.transaction(async (txRepo) => {
      await txRepo.transaction(async () => {
      })
    })
  } catch (e) {
    // 源码语义：TransactionRollbackError（不支持同一 Repository 嵌套调用 transaction）
    console.error('expected nested tx rejection:', e)
  }
}
```

## 推荐阅读顺序
1. `00-Repository总览.md`
2. `03-事务选项-TransactionOptions.md`
3. `04-事务执行器-TransactionManager.md`
4. `05-事务守卫-嵌套-跨仓库-未绑定写入.md`
5. `06-rawQuery-rawQuerySafe-rawExecute.md`


