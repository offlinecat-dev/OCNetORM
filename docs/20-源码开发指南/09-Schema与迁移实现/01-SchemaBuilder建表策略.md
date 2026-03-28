# 01-SchemaBuilder建表策略

> 状态：已完成
> 适用版本：ocorm 3.x（当前仓库实现）
> 最后更新：2026-03-27

## 1. 目标
- 使用 `SchemaBuilder` 基于已注册实体元数据生成并执行建表 SQL。
- 在迁移脚本中复用 `createTableByName` / `createAllTables`，避免手写重复 SQL。
- 对建表失败进行可观测处理：返回结果、迁移日志、事务回滚路径全部明确。

## 2. 前置条件
- 实体已完成注册（`MetadataStorage.getInstance().getEntityMetadata(entityName)` 能取到元数据）。
- 已拿到 `relationalStore.RdbStore`（或通过 `DatabaseManager.getInstance().getStore()`）。
- 需要索引时，依赖 `resolveEntityIndexes(metadata)` 自动补齐 unique rule 对应索引。

## 3. 建表策略
- 单表优先：迁移脚本里按版本显式调用 `createTableByName`，避免全量建表带来不可控副作用。
- 索引随表执行：`createTable` 会执行 `generateCreateTableSql(metadata)` 与 `generateCreateIndexSql(metadata)`。
- 多对多中间表：仅在 `createAllTables(..., true)` 或 `generateAllCreateTableSql(true)` 时创建。

## 4. 正确迁移示例（推荐）

```arkts
import { relationalStore } from '@kit.ArkData'
import { Migration } from '../schema/Migration'
import { SchemaBuilder } from '../schema/SchemaBuilder'

export class V2CreateUserProfileTable implements Migration {
  version: number = 2
  description: string = '创建 user_profile 表与索引'

  async up(store: relationalStore.RdbStore): Promise<void> {
    const builder = new SchemaBuilder()
    const result = await builder.createTableByName(store, 'UserProfile')
    if (!result.success) {
      throw new Error(`建表失败: ${result.errorMessage}; sql=${result.sql}`)
    }
  }

  async down(store: relationalStore.RdbStore): Promise<void> {
    await store.executeSql('DROP TABLE IF EXISTS "user_profile"')
  }
}
```

```arkts
import { MigrationManager } from '../schema/MigrationManager'

const manager = new MigrationManager({
  enableLog: true,
  logTableName: '_migrations'
})

manager.register(new V2CreateUserProfileTable())
const result = await manager.migrateToLatest(store)
if (!result.success) {
  // MigrationExecutionResult.errorMessage
  throw new Error(`迁移失败: ${result.errorMessage}`)
}
```

## 5. 误用示例（禁止）

```arkts
// 误用 1：实体未注册却直接建表，结果必然失败
const builder = new SchemaBuilder()
const result = await builder.createTableByName(store, 'NotRegisteredEntity')
// result.success === false
// result.errorMessage === "实体 'NotRegisteredEntity' 未注册"
```

```arkts
// 误用 2：忽略返回结果，失败后继续业务写入，造成后续 SQL 连锁异常
await builder.createTableByName(store, 'UserProfile')
await store.executeSql('INSERT INTO "user_profile" ("nickname") VALUES (\'a\')')
// 当上一句建表失败时，这里会报 "no such table"
```

## 6. 失败处理 / 日志 / 回滚说明
- `SchemaBuilder.createTable*` 失败时不会抛出异常，而是返回 `CreateTableResult.createFailure(...)`；调用方必须检查 `success`。
- `MigrationRunner.migrateTo` 在事务中执行：失败会调用 `MigrationStepExecutor.rollbackSafely(store)`，并写入失败日志（`MigrationLogService.safeLog`）。
- 日志写入失败不影响主流程（`safeLog` 内部吞掉日志异常），故主错误以迁移结果 `errorMessage` 为准。

```arkts
// 推荐的失败处理骨架
const result = await manager.migrateTo(store, 2)
if (!result.success) {
  // 可能包含 "...; 回滚失败: ..."（mergeFailureMessage）
  console.error(`from=${result.fromVersion}, to=${result.toVersion}, actual=${result.actualVersion}`)
  console.error(result.errorMessage)
  // 视业务策略触发告警/熔断
}
```

```sql
-- 迁移日志表结构由 MigrationLogManager.ensureTable 自动创建
CREATE TABLE IF NOT EXISTS "_migrations" (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  version INTEGER,
  name TEXT,
  type TEXT NOT NULL,
  direction TEXT,
  table_name TEXT,
  column_name TEXT,
  sql TEXT,
  summary TEXT,
  success INTEGER,
  error_message TEXT,
  created_at INTEGER NOT NULL
)
```

```sql
-- 故障排查：查看最近失败记录
SELECT version, name, type, direction, summary, success, error_message, created_at
FROM "_migrations"
WHERE success = 0
ORDER BY id DESC
LIMIT 20;
```

## 7. 验收清单
- `createTableByName` 返回成功，且 `sql` 同时包含建表与索引语句。
- 迁移失败时 `MigrationExecutionResult.success=false`，`errorMessage` 可定位到具体版本。
- `_migrations` 中存在失败记录（若启用日志）。
- 需要回滚时，`down()` 可独立执行并清理目标表。

## 8. 变更记录
- 2026-03-27：基于 `SchemaBuilder` / `MigrationRunner` / `MigrationLogService` 等源码实现补全文档。
