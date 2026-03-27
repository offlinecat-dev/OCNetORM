# 02-SchemaDiffer差异计算

> 状态：已完成
> 适用版本：ocorm 3.x（当前仓库实现）
> 最后更新：2026-03-27

## 1. 目标
- 使用 `SchemaDiffer.diff()` 基于实体元数据与数据库现状生成可审阅的 Schema 变更计划。
- 在执行自动迁移前识别破坏性变更，决定走 `SAFE` 还是 `FULL` 策略。
- 明确 `plannedSql`、`rollbackSql`、日志与事务边界，避免把“差异预览”误当成“迁移执行器”。

## 2. 前置条件
- 实体元数据已注册完成，`MetadataStorage.getInstance().getAllEntities()` 能返回目标实体。
- 目标数据库已可访问，`SchemaInspector` 能正常读取 `sqlite_master`、`PRAGMA table_info` 与 `PRAGMA index_list`。
- 若实体使用验证层 `unique` 规则，接受 `resolveEntityIndexes(metadata)` 在 diff 阶段补齐单列唯一索引。

## 3. 差异模型
- `SchemaDiffer` 只负责计算，不执行 SQL，不开启事务，也不直接写日志。
- `SchemaDiffResult.changes` 是结构化变更列表；`plannedSql` 与 `rollbackSql` 是按变更追加后的平铺 SQL 数组。
- 当前只会产生 4 类变更：`CREATE_TABLE`、`ADD_COLUMN`、`CREATE_INDEX`、`REBUILD_TABLE`。

```arkts
import { SchemaDiffer, SchemaChangeType } from '../schema/SchemaDiffer'

const differ = new SchemaDiffer()
const diff = await differ.diff(store, { includeJoinTables: true })

for (let i = 0; i < diff.changes.length; i++) {
  const change = diff.changes[i]
  console.info(
    `[${change.type}] table=${change.tableName}, destructive=${change.destructive}, summary=${change.summary}`
  )
  if (change.type === SchemaChangeType.REBUILD_TABLE) {
    console.warn(`需要重建表: ${change.tableName}`)
  }
}
```

## 4. 计算规则
- 缺表：生成 `CREATE_TABLE`，同时把该表对应的索引 SQL 一并加入 `sql`，回滚语句为 `DROP TABLE IF EXISTS`。
- 新增列：仅当新增列不是主键、不要求自增，且不是“无默认值的非空列”时，才生成 `ALTER TABLE ... ADD COLUMN`。
- 修改列或删列：一律触发 `REBUILD_TABLE`。实现会创建 `__ocorm_backup_*` 备份表、`__ocorm_tmp_*` 临时表，复制交集列后替换原表。
- 索引差异：按“唯一性 + 列集合”判断等价，索引名不是主要判断条件。重建表后会继续补 `CREATE_INDEX` 变更。
- 多对多中间表：`includeJoinTables` 默认开启；设为 `false` 时，中间表不会进入差异结果。

```sql
-- REBUILD_TABLE 的 plannedSql 典型片段
CREATE TABLE IF NOT EXISTS "__ocorm_backup_user_1710000000000" AS
SELECT "id", "email" FROM "user";

CREATE TABLE IF NOT EXISTS "__ocorm_tmp_user_1710000000000" (
  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
  "email" TEXT NOT NULL,
  "nickname" TEXT
);

INSERT INTO "__ocorm_tmp_user_1710000000000" ("id", "email")
SELECT "id", "email" FROM "user";

DROP TABLE "user";
ALTER TABLE "__ocorm_tmp_user_1710000000000" RENAME TO "user";
```

## 5. 正确迁移示例（推荐）
- 推荐流程是先 `diff()` 预览，再决定是否交给 `MigrationManager.autoMigrate()` 执行。
- 当存在 `destructive=true` 的变更时，默认应走 `AutoMigrationMode.SAFE`，只执行非破坏性项。

```arkts
import { MigrationManager, AutoMigrationMode } from '../schema/MigrationManager'
import { SchemaDiffer } from '../schema/SchemaDiffer'

const differ = new SchemaDiffer()
const preview = await differ.diff(store, { includeJoinTables: true })

const destructiveChanges = preview.changes.filter((item) => item.destructive)
if (destructiveChanges.length > 0) {
  console.warn(`发现 ${destructiveChanges.length} 个破坏性变更，先走 SAFE 模式`)
}

const manager = new MigrationManager({
  enableLog: true,
  logTableName: '_migrations',
  autoMigrationMode: AutoMigrationMode.SAFE
})

const result = await manager.autoMigrate(store, {
  includeJoinTables: true,
  mode: destructiveChanges.length > 0 ? AutoMigrationMode.SAFE : AutoMigrationMode.FULL,
  logChanges: true
})

if (!result.success) {
  throw new Error(`自动迁移失败: ${result.errorMessage}`)
}

console.info(`executed=${result.executedCount}, skipped=${result.skippedCount}`)
```

```arkts
// 读取 diff 结果时，优先关注 destructive 和 rollbackSql
const preview = await new SchemaDiffer().diff(store, { includeJoinTables: true })

for (let i = 0; i < preview.changes.length; i++) {
  const change = preview.changes[i]
  console.info(change.summary)
  console.info(`sql=${change.sql.join(' | ')}`)
  console.info(`rollback=${change.rollbackSql.join(' | ')}`)
}
```

## 6. 误用示例（禁止）
- 误用 1：把 `plannedSql` 当成可直接逐条裸执行的脚本，绕过事务、失败处理和日志。
- 误用 2：忽略 `destructive` 标记，在生产库直接执行 `REBUILD_TABLE`。
- 误用 3：传 `includeJoinTables: false` 却期待 many-to-many 中间表也出现在差异结果里。

```arkts
import { SchemaDiffer } from '../schema/SchemaDiffer'

const diff = await new SchemaDiffer().diff(store)

// 误用：手工逐条执行，失败时没有统一回滚，也没有 MigrationLogService 记录
for (let i = 0; i < diff.plannedSql.length; i++) {
  await store.executeSql(diff.plannedSql[i])
}
```

```arkts
import { MigrationManager, AutoMigrationMode } from '../schema/MigrationManager'
import { SchemaDiffer } from '../schema/SchemaDiffer'

// 误用：看到 REBUILD_TABLE 仍直接放行
const preview = await new SchemaDiffer().diff(store)
if (preview.hasChanges()) {
  // 错误点：没有检查 destructive，也没有评估 rollbackSql 是否可接受
  await new MigrationManager().autoMigrate(store, { mode: AutoMigrationMode.FULL })
}
```

## 7. 失败处理 / 日志 / 回滚说明
- `SchemaDiffer.diff()` 失败通常来自 `SchemaInspector` 读库异常；该阶段会抛错，不会吞异常，也不会自动落日志。
- `rollbackSql` 是“建议性回滚脚本集合”，不是自动执行逻辑。尤其 `ADD_COLUMN` 的回滚只有注释提示，因为 SQLite 不支持直接删列。
- 真正的事务回滚发生在执行阶段：`AutoMigrationHandler.autoMigrate()` 失败时调用 `store.rollBack()`；手动迁移链路则由 `MigrationRunner` + `MigrationStepExecutor.rollbackSafely()` 处理。
- 若启用 `logChanges`，执行阶段会通过 `MigrationLogService.safeLogSchemaChange()` 写入 `_migrations`；纯 diff 预览本身不会写日志。

```arkts
import { SchemaDiffer } from '../schema/SchemaDiffer'

try {
  const diff = await new SchemaDiffer().diff(store, { includeJoinTables: true })
  console.info(`plannedSql=${diff.plannedSql.length}`)
} catch (error) {
  const message = error instanceof Error ? error.message : String(error)
  console.error(`Schema diff 失败: ${message}`)
  // 这里还没有任何事务，也没有自动日志；需要调用方自行告警
}
```

```sql
-- ADD_COLUMN 的 rollbackSql 只有建议，不会被框架自动执行
-- 回滚建议: SQLite 不支持直接删除列，请手动重建表

-- REBUILD_TABLE 典型 rollbackSql 片段
-- 回滚建议: 从备份表 __ocorm_backup_user_1710000000000 恢复列数据
INSERT INTO "user" ("id", "email")
SELECT "id", "email" FROM "__ocorm_backup_user_1710000000000";
```

```sql
-- 开启日志后，可在 _migrations 中排查自动迁移对 diff 的执行结果
SELECT type, table_name, column_name, summary, success, error_message, created_at
FROM "_migrations"
WHERE type = 'AUTO_SCHEMA'
ORDER BY id DESC
LIMIT 20;
```

## 8. 验收清单
- `diff.changes` 中只出现仓库当前实现支持的 4 种类型。
- 新增非空且无默认值的列时，结果应为 `REBUILD_TABLE`，而不是 `ADD_COLUMN`。
- `includeJoinTables=false` 时，多对多中间表不应出现在 `changes` 中。
- 走 `SAFE` 自动迁移时，`destructive=true` 的项应进入 `skippedChanges`，而不是 `executedSql`。

## 9. 变更记录
- 2026-03-27：基于 `SchemaDiffer`、`SchemaInspector`、`AutoMigrationHandler`、`MigrationLogService` 等源码实现补全文档。
