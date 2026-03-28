# Schema API 契约

实现依据：`src/main/ets/schema/*.ets`

## `SchemaBuilder`

- 用途：按元数据生成建表 SQL 并执行建表/建索引。
- 参数：
  - `generateCreateTableSql(metadata)`
  - `createTable(store, metadata)`
  - `createAllTables(store, includeJoinTables?)`
  - `createAllTablesWithManager(includeJoinTables?)`
- 返回：
  - `CreateTableResult` / `CreateAllTablesResult`
- 异常：
  - `create*WithManager` 不抛出，失败写入 `result.success=false`
  - 直接 `createTable/createAllTables` 过程中底层执行异常会体现在返回结果 `errorMessage`
- 副作用：执行 DDL，创建实体表、索引、多对多中间表。
- 事务上下文：`SchemaBuilder` 本身不自动开启事务。
- 最小示例：

```ts
import { SchemaBuilder } from 'ocorm'

const result = await new SchemaBuilder().createAllTablesWithManager(true)
```

## `SchemaInspector`

- 用途：读取数据库真实结构（表、列、索引）。
- 参数：
  - `getExistingTables(store)`
  - `getTableInfo(store, tableName)`
  - `getTableIndexes(store, tableName)`
- 返回：
  - `string[]` / `TableInfo` / `IndexInfo[]`
- 异常：
  - 查询失败抛 `ExecutionError`
- 副作用：只读查询，无写入。
- 事务上下文：不要求事务，可在外部事务中调用。
- 最小示例：

```ts
import { DatabaseManager, SchemaInspector } from 'ocorm'

const store = DatabaseManager.getInstance().getStore()
const info = await new SchemaInspector().getTableInfo(store, 'users')
```

## `SchemaDiffer.diff(store, options?)`

- 用途：比较“期望元数据”与“当前数据库结构”，产出变更计划。
- 参数：
  - `store: RdbStore`
  - `options.includeJoinTables?: boolean`
- 返回：`SchemaDiffResult`
  - `changes[]`（含 `type/summary/destructive/sql/rollbackSql`）
  - `plannedSql[]`
  - `rollbackSql[]`
- 异常：依赖 `SchemaInspector`，其读取失败时抛 `ExecutionError`。
- 副作用：无，纯 diff 计算。
- 事务上下文：无。
- 最小示例：

```ts
import { DatabaseManager, SchemaDiffer } from 'ocorm'

const diff = await new SchemaDiffer().diff(DatabaseManager.getInstance().getStore())
if (diff.hasChanges()) {
  console.info(diff.plannedSql)
}
```

## `MigrationManager`

- 用途：管理版本化迁移脚本与自动迁移流程。
- 参数：
  - 注册：`register(migration)` / `registerAll(migrations)`
  - 执行：`migrateTo(store, version)` / `migrateToLatest(store)`
  - 便捷：`migrateToWithManager` / `migrateToLatestWithManager`
  - 自动迁移：`autoMigrate(store, options?)` / `autoMigrateWithManager(options?)`
- 返回：
  - 版本迁移：`MigrationExecutionResult`
  - 自动迁移：`SchemaMigrationExecutionResult`
- 异常：
  - `*WithManager` 版本会兜底并返回 `success=false` 结果对象（不抛）
  - 非 `WithManager` 版本依赖调用方处理底层异常
- 副作用：
  - 执行迁移脚本 `up/down`
  - 更新版本表、写迁移日志
- 事务上下文：
  - `migrateTo` 在单事务中执行（失败回滚）
  - 自动迁移内部也以事务提交变更
- 最小示例：

```ts
import { MigrationManager } from 'ocorm'

const manager = new MigrationManager()
const result = await manager.migrateToLatestWithManager()
```

## 自动迁移模式（`AutoMigrationMode`）

- `SAFE`：仅执行 `destructive=false` 的变更，破坏性变更会跳过并记录。
- `FULL`：执行全部变更（包含重建表等破坏性步骤）。
- 建议：生产默认 `SAFE`，人工评审后再执行 `FULL`。
