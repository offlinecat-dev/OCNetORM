# 06-自动迁移策略-AutoMigration

> 状态：已完成
> 适用版本：ocorm 3.x（当前仓库实现）
> 最后更新：2026-03-27

## 1. 目标
- 说明 `MigrationManager.autoMigrate()` / `AutoMigrationHandler.autoMigrate()` 如何把 `SchemaDiffer.diff()` 的结果转换成实际 SQL 执行。
- 明确 `SAFE` 与 `FULL` 两种模式的真实差别，以及 `includeJoinTables`、`logChanges` 的默认行为。
- 明确失败语义：自动迁移是事务型 schema 变更流程，但它不推进 `_orm_version`。

## 2. 核心规则
- 差异来源：始终先执行 `schemaDiffer.diff(store, { includeJoinTables })`。
- 模式选择：
  - `SAFE`：只执行 `destructive=false` 的变更
  - `FULL`：执行全部变更
- `includeJoinTables` 默认是 `true`；只有显式传 `false` 时才跳过 many-to-many 中间表。
- `logChanges` 默认跟随 `MigrationLogService.isEnabled()`；显式传值可覆盖。
- 结果模型为 `SchemaMigrationExecutionResult`：
  - `success`
  - `executedCount`
  - `skippedCount`
  - `changes`
  - `skippedChanges`
  - `executedSql`
  - `rollbackSql`
  - `errorMessage`

```arkts
import { MigrationManager, AutoMigrationMode } from '../schema/MigrationManager'

const manager = new MigrationManager({
  enableLog: true,
  autoMigrationMode: AutoMigrationMode.SAFE
})

const result = await manager.autoMigrate(store, {
  includeJoinTables: true,
  mode: AutoMigrationMode.SAFE,
  logChanges: true
})

console.info(`success=${result.success}, executed=${result.executedCount}, skipped=${result.skippedCount}`)
```

## 3. 执行流程
- `diff` 无变化：
  - 直接返回 `createSuccess(diff, [], [])`
  - 不开事务
  - 不写 schema 变更日志
- `SAFE` 且全部都是破坏性变更：
  - 返回成功
  - `executedSql` 为空
  - `skippedChanges` 包含全部变更
  - 若 `logChanges=true`，会写“自动迁移跳过（破坏性变更）”
- 有可执行变更时：
  - `beginTransaction()`
  - 顺序执行每个 `change.sql`
  - `commit()`
  - 若启用日志，逐条写 `AUTO_SCHEMA` 成功记录和跳过记录

```arkts
import { SchemaDiffer } from '../schema/SchemaDiffer'

const preview = await new SchemaDiffer().diff(store, { includeJoinTables: true })
for (let i = 0; i < preview.changes.length; i++) {
  const change = preview.changes[i]
  console.info(`[${change.type}] destructive=${change.destructive} summary=${change.summary}`)
}
```

```sql
-- 自动迁移的执行对象来自 SchemaDiffer.plannedSql / change.sql
CREATE TABLE IF NOT EXISTS "user_profile" (...);
ALTER TABLE "user_profile" ADD COLUMN "nickname" TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS "uidx_user_profile_email" ON "user_profile" ("email");
```

## 4. 正确迁移示例（推荐）
- 推荐流程是“先预览、后执行、再验收”。
- 发现 `destructive=true` 时，默认先走 `SAFE`，确认后再决定是否切换 `FULL`。
- 自动迁移适合纯 schema 对齐，不适合复杂数据修复或手写数据搬迁。

```arkts
import { MigrationManager, AutoMigrationMode } from '../schema/MigrationManager'
import { SchemaDiffer } from '../schema/SchemaDiffer'

const preview = await new SchemaDiffer().diff(store, { includeJoinTables: true })
const hasDestructive = preview.changes.some((change) => change.destructive)

const manager = new MigrationManager({
  enableLog: true,
  logTableName: '_migrations',
  autoMigrationMode: AutoMigrationMode.SAFE
})

const result = await manager.autoMigrate(store, {
  includeJoinTables: true,
  mode: hasDestructive ? AutoMigrationMode.SAFE : AutoMigrationMode.FULL,
  logChanges: true
})

if (!result.success) {
  throw new Error(`自动迁移失败: ${result.errorMessage}`)
}
```

```arkts
// 仅当你已经审阅 destructive 变更并接受风险时，再显式使用 FULL
const fullResult = await manager.autoMigrate(store, {
  includeJoinTables: true,
  mode: AutoMigrationMode.FULL,
  logChanges: true
})

if (!fullResult.success) {
  throw new Error(fullResult.errorMessage)
}
```

## 5. 误用示例（禁止）
- 误用 1：把 `SAFE` 当成“无脑成功升级”，忽略 `skippedChanges`。
- 误用 2：把 `autoMigrate()` 当成版本迁移器，期待它更新 `_orm_version`。
- 误用 3：直接 `FULL` 落生产库，不审阅 `REBUILD_TABLE` 这类破坏性变更。

```arkts
import { MigrationManager, AutoMigrationMode } from '../schema/MigrationManager'

const manager = new MigrationManager({ autoMigrationMode: AutoMigrationMode.SAFE })
const result = await manager.autoMigrate(store)

// 误用：SAFE 成功不代表所有变更都执行了
if (result.success) {
  console.info('错误推断：这里还必须检查 skippedCount / skippedChanges')
}
```

```arkts
const result = await manager.autoMigrate(store, { mode: AutoMigrationMode.FULL })

// 误用：自动迁移不会更新 _orm_version
const rs = await store.querySql('SELECT version FROM _orm_version WHERE id = 1')
rs.close()
console.info('错误推断：autoMigrate 完成后版本号会自动推进')
```

```arkts
// 误用：不看 diff 直接 FULL
await manager.autoMigrate(store, {
  mode: AutoMigrationMode.FULL,
  includeJoinTables: true,
  logChanges: false
})
```

## 6. 失败处理 / 日志 / 回滚说明
- 失败时：
  - `rollbackSafely(store)` 会尝试 `store.rollBack()`
  - 返回 `SchemaMigrationExecutionResult.createFailure(...)`
  - `errorMessage` 可能带上 `; 回滚失败: ...`
- 日志：
  - 成功执行的变更：`safeLogSchemaChange(..., success=true)`
  - 跳过的破坏性变更：`summary='自动迁移跳过（破坏性变更）'`
  - 失败中的当前变更：`summary='自动迁移执行失败'`
- 回滚：
  - 自动迁移本身只回滚事务
  - 结果里的 `rollbackSql` 来自 `SchemaDiffer`，属于建议性回滚信息，不会自动再次执行
- 版本：
  - 自动迁移链路不调用 `MigrationVersionStore`
  - 因此 `_orm_version` 不会因为 `autoMigrate()` 自动变化

```arkts
const result = await manager.autoMigrate(store, {
  mode: AutoMigrationMode.SAFE,
  logChanges: true
})

if (!result.success) {
  console.error(`executedSql=${result.executedSql.join(' | ')}`)
  console.error(`rollbackSql=${result.rollbackSql.join(' | ')}`)
  console.error(result.errorMessage)
}
```

```sql
-- 自动迁移日志排障
SELECT type, table_name, column_name, summary, success, error_message, created_at
FROM "_migrations"
WHERE type = 'AUTO_SCHEMA'
ORDER BY id DESC
LIMIT 20;
```

```sql
-- autoMigrate 不推进 _orm_version，若此值变化，来源应是手动迁移链路
SELECT version, updated_at
FROM _orm_version
WHERE id = 1;
```

## 7. 验收清单
- `SAFE` 模式下，破坏性变更进入 `skippedChanges`，不会进入 `executedSql`。
- `FULL` 模式下，`SchemaDiffer` 产出的全部变更都可进入执行队列。
- 自动迁移失败时，`success=false`，并伴随事务回滚。
- 自动迁移完成后，`_orm_version` 不会被该流程自动更新。

## 8. 变更记录
- 2026-03-27：基于 `AutoMigrationHandler`、`MigrationManagerTypes`、`MigrationLogService`、`SchemaDiffer` 真实实现补全文档。
