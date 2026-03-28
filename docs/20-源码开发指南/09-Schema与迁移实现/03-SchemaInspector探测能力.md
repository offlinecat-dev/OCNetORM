# 03-SchemaInspector探测能力

> 状态：已完成
> 适用版本：ocorm 3.x（当前仓库实现）
> 最后更新：2026-03-27

## 1. 目标
- 使用 `SchemaInspector` 从 SQLite/HarmonyOS RDB 真实结构中读取表、列、索引信息。
- 为 `SchemaDiffer`、迁移验收、故障排查提供数据库“当前状态”而不是元数据“期望状态”。
- 明确它的边界：只读探测，不执行迁移，不开启事务，不自动记录日志。

## 2. 前置条件
- 已拿到可用的 `relationalStore.RdbStore`。
- 目标表已经存在，或调用方能接受“表不存在时返回空列结构/抛错”的行为差异。
- 需要识别唯一列、自增列时，数据库中的表结构必须真实包含 `UNIQUE` 索引或 `AUTOINCREMENT` 关键字。

## 3. 可用 API
- `getExistingTables(store)`：读取 `sqlite_master` 中非 `sqlite_%` 表名。
- `getTableInfo(store, tableName)`：读取列定义，并补齐 `unique`、`autoIncrement`。
- `getTableIndexes(store, tableName)`：读取 `PRAGMA index_list/index_info` 结果。
- 返回模型：
  - `ColumnInfo`: `name`、`type`、`notNull`、`defaultValue`、`primaryKey`、`unique?`、`autoIncrement?`
  - `IndexInfo`: `name`、`unique`、`columns`
  - `TableInfo`: `name`、`columns`、`indexes?`

```arkts
import { SchemaInspector } from '../schema/SchemaInspector'

const inspector = new SchemaInspector()
const tables = await inspector.getExistingTables(store)

for (let i = 0; i < tables.length; i++) {
  console.info(`table=${tables[i]}`)
}
```

## 4. 探测规则
- `getExistingTables()` 会过滤内部表：查询条件固定为 `type='table' AND name NOT LIKE 'sqlite_%'`。
- `getTableInfo()` 基于 `PRAGMA table_info("table")` 读取列，再调用 `getTableIndexes()` 和 `getTableSql()` 做二次补充。
- `unique` 推断规则：
  - 主键列始终被视为 `unique=true`
  - 只有“单列唯一索引”会把对应列标记为 `unique=true`
  - 多列联合唯一索引不会把任一单列误标为 unique
- `autoIncrement` 推断规则：
  - 列必须是主键
  - 列类型需包含 `INT`
  - 建表 SQL 中必须匹配到该列后的 `AUTOINCREMENT`
- `getIndexColumns()` 失败时直接返回空数组，不向外抛错；`getTableSql()` 失败时返回 `null`（降级继续探测，不包装为 `ExecutionError`）；其余主查询失败会包装为 `ExecutionError`

```sql
-- SchemaInspector.getExistingTables 实际读取来源
SELECT name
FROM sqlite_master
WHERE type='table' AND name NOT LIKE 'sqlite_%';

-- SchemaInspector.getTableInfo / getTableIndexes 的核心探测
PRAGMA table_info("user_profile");
PRAGMA index_list("user_profile");
PRAGMA index_info("idx_user_profile_name");
```

## 5. 正确迁移示例（推荐）
- 推荐把 `SchemaInspector` 用在迁移后验收，而不是把它当迁移执行器。
- 当前仓库测试 `src/test/Stage10SchemaMigration/SchemaInspector.test.ets` 主要覆盖 `ColumnInfo` / `IndexInfo` / `TableInfo` 结构与 `SchemaInspector` 实例化，不等同于真实数据库端到端探测覆盖。

```arkts
import { SchemaInspector } from '../schema/SchemaInspector'
import { MigrationManager } from '../schema/MigrationManager'

const manager = new MigrationManager({ enableLog: true, logTableName: '_migrations' })
manager.register(new V2CreateUserProfileTable())

const migrationResult = await manager.migrateToLatest(store)
if (!migrationResult.success) {
  throw new Error(`迁移失败: ${migrationResult.errorMessage}`)
}

const inspector = new SchemaInspector()
const tableInfo = await inspector.getTableInfo(store, 'user_profile')

const idColumn = tableInfo.columns.find((item) => item.name === 'id') ?? null
const emailColumn = tableInfo.columns.find((item) => item.name === 'email') ?? null
if (idColumn === null || idColumn.primaryKey !== true || idColumn.autoIncrement !== true) {
  throw new Error('迁移后结构不符合预期: id 主键/自增识别失败')
}
if (emailColumn === null || emailColumn.unique !== true) {
  throw new Error('迁移后结构不符合预期: email 唯一性识别失败')
}
```

```arkts
import { SchemaInspector } from '../schema/SchemaInspector'

const inspector = new SchemaInspector()
const indexes = await inspector.getTableIndexes(store, 'user_profile')

for (let i = 0; i < indexes.length; i++) {
  const index = indexes[i]
  console.info(`index=${index.name}, unique=${index.unique}, columns=${index.columns.join(',')}`)
}
```

## 6. 误用示例（禁止）
- 误用 1：假设 `getExistingTables()` 会返回 `sqlite_sequence` 等内部表。
- 误用 2：把联合唯一索引误判为“每个单列都 unique”。
- 误用 3：把 `SchemaInspector` 当写库工具，指望探测失败时自动回滚。

```arkts
import { SchemaInspector } from '../schema/SchemaInspector'

const inspector = new SchemaInspector()
const tables = await inspector.getExistingTables(store)

// 误用：sqlite 内部表已被过滤，这个判断没有意义
if (tables.includes('sqlite_sequence')) {
  console.info('错误假设：这里通常不会成立')
}
```

```arkts
const inspector = new SchemaInspector()
const tableInfo = await inspector.getTableInfo(store, 'order_item')

// 误用：联合唯一索引不会让单个列自动 unique=true
const productId = tableInfo.columns.find((item) => item.name === 'product_id')
if (productId?.unique === true) {
  console.info('错误推断：可能只是 (order_id, product_id) 的联合唯一索引')
}
```

## 7. 失败处理 / 日志 / 回滚说明
- `SchemaInspector` 是只读组件，不调用 `beginTransaction()`，也不调用 `commit()` / `rollBack()`。
- 它自身不写 `_migrations` 日志。若探测发生在迁移链路之外，日志与告警完全由调用方负责。
- `getExistingTables()`、`getTableInfo()`、`getTableIndexes()` 主流程失败时会抛 `ExecutionError`；调用方必须捕获。例外：`getTableSql()` 内部失败会吞掉异常并返回 `null`。
- 若你在“迁移后验收”阶段使用 `SchemaInspector`，事务回滚只能由外层迁移执行器负责，`SchemaInspector` 不参与任何回滚。

```arkts
import { SchemaInspector } from '../schema/SchemaInspector'

const inspector = new SchemaInspector()

try {
  const info = await inspector.getTableInfo(store, 'user_profile')
  console.info(`columns=${info.columns.length}`)
} catch (error) {
  const message = error instanceof Error ? error.message : String(error)
  console.error(`Schema 探测失败: ${message}`)
  // 这里没有自动日志，也没有自动回滚
}
```

```sql
-- 以下 SQL 用于手工验证 SchemaInspector 探测行为（不是仓库现有自动化用例）
CREATE TABLE schema_probe_xxx (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  email TEXT UNIQUE,
  status INTEGER DEFAULT 7,
  created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_schema_probe_xxx_name ON schema_probe_xxx (name);
```

```sql
-- 若你在迁移后验收阶段开启了 MigrationManager 日志，
-- 结构探测本身不会写日志，只能结合迁移执行记录排障
SELECT version, name, type, direction, summary, success, error_message, created_at
FROM "_migrations"
WHERE type = 'MIGRATION'
ORDER BY id DESC
LIMIT 20;
```

## 8. 验收清单
- 能枚举真实创建的业务表，且不会返回 `sqlite_%` 内部表。
- `PRIMARY KEY AUTOINCREMENT` 列会得到 `primaryKey=true`、`autoIncrement=true`、`unique=true`。
- 单列 `UNIQUE` 或 UNIQUE autoindex 能映射到 `ColumnInfo.unique=true`。
- 普通手工索引可在 `getTableIndexes()` 中读出，`unique=false` 且列顺序正确。

## 9. 变更记录
- 2026-03-27：基于 `SchemaInspector` 源码与 `Stage10SchemaMigration/SchemaInspector.test.ets` 现状补全文档。
