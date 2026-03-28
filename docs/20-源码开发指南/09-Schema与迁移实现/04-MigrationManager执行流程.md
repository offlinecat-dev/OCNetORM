# 04-MigrationManager执行流程

> 状态：已完成
> 适用版本：ocorm 3.x（当前仓库实现）
> 最后更新：2026-03-27

## 1. 目标
- 使用 `MigrationManager` 统一管理手动迁移脚本注册、排序、执行、回滚与自动迁移入口。
- 说明它与 `MigrationRunner`、`MigrationStepExecutor`、`MigrationVersionStore`、`AutoMigrationHandler` 的真实协作关系。
- 明确失败语义：返回 `MigrationExecutionResult` / `SchemaMigrationExecutionResult`，并在事务失败时保持数据库版本不前移。

## 2. 构成与边界
- `MigrationManager` 本身主要是门面层，不直接执行业务 SQL。
- 构造函数会组装以下组件：
  - `SchemaDiffer`
  - `MigrationRegistry`
  - `MigrationLogService`
  - `MigrationVersionStore`
  - `MigrationRunner`
  - `AutoMigrationHandler`
- 手动迁移入口：
  - `register` / `registerAll`
  - `migrateTo`
  - `migrateToLatest`
  - `getCurrentVersionFromDb`
- 自动迁移入口：
  - `autoMigrate`
- 免传 `store` 的包装入口：
  - `migrateToWithManager`
  - `migrateToLatestWithManager`
  - `autoMigrateWithManager`

```arkts
import { MigrationManager, AutoMigrationMode } from '../schema/MigrationManager'

const manager = new MigrationManager({
  enableLog: true,
  logTableName: '_migrations',
  autoMigrationMode: AutoMigrationMode.SAFE
})

console.info(manager.getSummary())
```

## 3. 执行流程
- 注册阶段：
  - `register()` 遇到重复版本直接抛错
  - `registerAll()` 内部逐个调用 `register()`，重复版本会被忽略
- 手动迁移阶段：
  - `MigrationRunner.getCurrentVersionFromDb()` 先通过 `MigrationVersionStore` 确保 `_orm_version` 存在
  - `MigrationRunner.migrateTo()` 根据目标版本决定走升级还是回滚
  - `runUpgrade()` 逐个执行 `migration.up(store)`
  - `runRollback()` 按倒序执行 `migration.down(store)`
  - 全部成功后写回 `_orm_version.version`
- 自动迁移阶段：
  - `AutoMigrationHandler.autoMigrate()` 先调用 `SchemaDiffer.diff()`
  - `SAFE` 只执行 `destructive=false` 的变更
  - `FULL` 执行全部 diff 结果

```sql
-- MigrationVersionStore.ensureVersionTable 创建的版本表
CREATE TABLE IF NOT EXISTS _orm_version (
  id INTEGER PRIMARY KEY,
  version INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL
);
```

```arkts
// 手动迁移成功后的关键结果字段
const result = await manager.migrateToLatest(store)

console.info(`success=${result.success}`)
console.info(`from=${result.fromVersion}, to=${result.toVersion}, actual=${result.actualVersion}`)
console.info(`executed=${result.executedCount}`)
```

## 4. 正确迁移示例（推荐）
- 推荐先显式注册迁移，再使用 `migrateToLatest(store)`。
- 当需要精确回滚到某个版本时，使用 `migrateTo(store, targetVersion)`，不要自己手工倒序调 `down()`。

```arkts
import { relationalStore } from '@kit.ArkData'
import { Migration } from '../schema/Migration'
import { MigrationManager } from '../schema/MigrationManager'

class V1CreateUserTable implements Migration {
  version: number = 1
  description: string = '创建 user 表'

  async up(store: relationalStore.RdbStore): Promise<void> {
    await store.executeSql('CREATE TABLE IF NOT EXISTS "user" ("id" INTEGER PRIMARY KEY AUTOINCREMENT, "name" TEXT)')
  }

  async down(store: relationalStore.RdbStore): Promise<void> {
    await store.executeSql('DROP TABLE IF EXISTS "user"')
  }
}

class V2AddEmailColumn implements Migration {
  version: number = 2
  description: string = '为 user 表增加 email 列'

  async up(store: relationalStore.RdbStore): Promise<void> {
    await store.executeSql('ALTER TABLE "user" ADD COLUMN "email" TEXT')
  }

  async down(store: relationalStore.RdbStore): Promise<void> {
    await store.executeSql('CREATE TABLE IF NOT EXISTS "__tmp_user_down" ("id" INTEGER PRIMARY KEY AUTOINCREMENT, "name" TEXT)')
    await store.executeSql('INSERT INTO "__tmp_user_down" ("id", "name") SELECT "id", "name" FROM "user"')
    await store.executeSql('DROP TABLE "user"')
    await store.executeSql('ALTER TABLE "__tmp_user_down" RENAME TO "user"')
  }
}

const manager = new MigrationManager({ enableLog: true, logTableName: '_migrations' })
manager.registerAll([new V1CreateUserTable(), new V2AddEmailColumn()])

const result = await manager.migrateToLatest(store)
if (!result.success) {
  throw new Error(`迁移失败: ${result.errorMessage}`)
}
```

```arkts
// 回滚到指定版本，真实执行顺序由 MigrationRegistry.getRollbackMigrations 决定
const rollbackResult = await manager.migrateTo(store, 1)
if (!rollbackResult.success) {
  throw new Error(`回滚失败: ${rollbackResult.errorMessage}`)
}
```

## 5. 误用示例（禁止）
- 误用 1：重复调用 `register()` 注册同一版本，当前实现会直接抛错。
- 误用 2：迁移脚本已失败，却仍把 `actualVersion` 当成 `toVersion` 使用。
- 误用 3：跳过 `MigrationManager` 自己拼事务、自己更新 `_orm_version`，最终让版本表与真实结构脱节。

```arkts
import { MigrationManager } from '../schema/MigrationManager'

const manager = new MigrationManager()
manager.register(new V1CreateUserTable())

// 误用：重复版本会抛出 Error("迁移版本 1 已存在")
manager.register(new V1CreateUserTable())
```

```arkts
const result = await manager.migrateToLatest(store)

// 误用：失败后 actualVersion 仍可能停留在旧版本
if (result.toVersion === 2) {
  console.info('错误写法：不能据此断定数据库已升级到 v2')
}
```

```arkts
// 误用：手工执行 up/down 然后自己改 _orm_version，绕过日志和统一回滚
await new V1CreateUserTable().up(store)
await store.executeSql('UPDATE _orm_version SET version = 1, updated_at = 123456789 WHERE id = 1')
```

## 6. 失败处理 / 日志 / 回滚说明
- 手动迁移：
  - `MigrationRunner.migrateTo()` 在事务内执行
  - 任一 `migration.up/down` 失败后，`MigrationStepExecutor.rollbackSafely(store)` 会尝试 `store.rollBack()`
  - 返回 `MigrationExecutionResult.createFailure(...)`
- 自动迁移：
  - `AutoMigrationHandler.autoMigrate()` 同样使用事务
  - 失败时返回 `SchemaMigrationExecutionResult.createFailure(...)`
- 日志：
  - 单步迁移失败会立刻用 `MigrationLogService.safeLog()` 写失败日志
  - 全部成功后的 success 日志会在事务提交后批量写入
  - 日志写入失败会被吞掉，不影响主迁移结果
- 版本：
  - 只有全部步骤成功后才会调用 `updateVersionInDb(store, targetVersion)`
  - 失败时 `_orm_version` 保持旧值，`actualVersion` 也保持旧版本

```arkts
const result = await manager.migrateToLatest(store)

if (!result.success) {
  console.error(`from=${result.fromVersion}, to=${result.toVersion}, actual=${result.actualVersion}`)
  console.error(`executedCount=${result.executedCount}`)
  console.error(result.errorMessage)
  // 失败时不要假设版本已经推进
}
```

```sql
-- 手动迁移与自动迁移共用的日志表结构
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
);
```

```sql
-- 故障排查：查看最近的迁移事务失败/回滚失败痕迹
SELECT version, name, type, direction, success, error_message, created_at
FROM "_migrations"
WHERE success = 0
ORDER BY id DESC
LIMIT 20;
```

## 7. 自动迁移与手动迁移的选择
- 手动迁移适合需要精确控制数据修复、复杂回滚、跨表数据搬迁的场景。
- 自动迁移适合纯 schema 补齐，且能接受 `SAFE/FULL` 的 diff 执行模型。
- 不要混淆两条链路：
  - `migrateTo*` 消费的是注册好的 `Migration`
  - `autoMigrate*` 消费的是 `SchemaDiffer.diff()` 的结果

```arkts
import { AutoMigrationMode, MigrationManager } from '../schema/MigrationManager'

const manager = new MigrationManager({
  enableLog: true,
  autoMigrationMode: AutoMigrationMode.SAFE
})

const autoResult = await manager.autoMigrate(store, {
  includeJoinTables: true,
  mode: AutoMigrationMode.SAFE,
  logChanges: true
})

if (!autoResult.success) {
  throw new Error(`自动迁移失败: ${autoResult.errorMessage}`)
}
```

## 8. 验收清单
- `register()` 对重复版本抛错，`registerAll()` 忽略重复版本。
- `migrateToLatest()` 首次成功后再次执行，`executedCount` 应为 `0`。
- 任一迁移失败后，事务回滚，`actualVersion` 保持旧版本。
- 成功完成后，`_orm_version.version` 与 `manager.getCurrentVersion()` 保持一致。

## 9. 变更记录
- 2026-03-27：基于 `MigrationManager`、`MigrationRunner`、`MigrationStepExecutor`、`MigrationVersionStore`、`MigrationLogService` 与相关测试补全文档。
