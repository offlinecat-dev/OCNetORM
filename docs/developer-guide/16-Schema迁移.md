# Schema 迁移

OCORM 提供完整的数据库 Schema 迁移功能，支持手动迁移脚本和自动迁移两种模式，帮助开发者安全地管理数据库结构变更。

---

## SchemaBuilder - 建表工具

`SchemaBuilder` 根据实体元数据生成 CREATE TABLE SQL 语句并执行建表操作。

### 生成建表 SQL

```typescript
import { SchemaBuilder, MetadataStorage } from '@offlinecat/ocorm'

const builder = new SchemaBuilder()

// 根据实体名称生成 SQL
const sql = builder.generateCreateTableSqlByName('User')
// 输出: CREATE TABLE IF NOT EXISTS "users" ("id" INTEGER PRIMARY KEY AUTOINCREMENT, ...)

// 根据实体元数据生成 SQL
const metadata = MetadataStorage.getInstance().getEntityMetadata('User')
if (metadata !== null) {
  const sql = builder.generateCreateTableSql(metadata)
}

// 生成所有已注册实体的建表 SQL
const allSql = builder.generateAllCreateTableSql(true)  // true = 包含多对多中间表
```

### 执行建表操作

```typescript
import { SchemaBuilder, DatabaseManager } from '@offlinecat/ocorm'

const builder = new SchemaBuilder()

// 方式一：使用 DatabaseManager（推荐）
const result = await builder.createAllTablesWithManager(true)

if (result.success) {
  console.log(`成功创建 ${result.successCount} 张表`)
} else {
  console.log(`失败 ${result.failureCount} 张表`)
  for (const r of result.results) {
    if (!r.success) {
      console.log(`表 ${r.tableName} 创建失败: ${r.errorMessage}`)
    }
  }
}

// 方式二：手动传入 RdbStore
const store = DatabaseManager.getInstance().getStore()
const result = await builder.createAllTables(store, true)

// 创建单个表
const singleResult = await builder.createTableByName(store, 'User')
```

### CreateTableResult 结果类

```typescript
class CreateTableResult {
  success: boolean       // 是否成功
  tableName: string      // 表名
  sql: string            // 执行的 SQL
  errorMessage: string   // 错误信息
}

class CreateAllTablesResult {
  success: boolean                    // 是否全部成功
  successCount: number                // 成功数量
  failureCount: number                // 失败数量
  results: Array<CreateTableResult>   // 各表执行结果
}
```

---

## MigrationManager - 迁移管理器

`MigrationManager` 负责注册、排序和执行数据库迁移脚本，支持版本控制和回滚。

### Migration 迁移脚本接口

每个迁移脚本必须实现 `Migration` 接口：

```typescript
import { Migration } from '@offlinecat/ocorm'
import { relationalStore } from '@kit.ArkData'

class Migration_001_CreateUsersTable implements Migration {
  version: number = 1
  description: string = '创建用户表'

  async up(store: relationalStore.RdbStore): Promise<void> {
    await store.executeSql(`
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT UNIQUE
      )
    `)
  }

  async down(store: relationalStore.RdbStore): Promise<void> {
    await store.executeSql('DROP TABLE IF EXISTS users')
  }
}
```

### 注册迁移脚本

```typescript
import { MigrationManager } from '@offlinecat/ocorm'

const migrationManager = new MigrationManager()

// 注册单个迁移
migrationManager.register(new Migration_001_CreateUsersTable())
migrationManager.register(new Migration_002_AddAgeColumn())

// 批量注册
migrationManager.registerAll([
  new Migration_001_CreateUsersTable(),
  new Migration_002_AddAgeColumn(),
  new Migration_003_CreatePostsTable()
])
```

### 执行迁移

```typescript
import { MigrationManager, DatabaseManager } from '@offlinecat/ocorm'

const migrationManager = new MigrationManager()
// ... 注册迁移脚本

// 方式一：使用 DatabaseManager（推荐）
const result = await migrationManager.migrateToLatestWithManager()

// 方式二：迁移到指定版本
const result = await migrationManager.migrateToWithManager(2)

// 方式三：手动传入 RdbStore
const store = DatabaseManager.getInstance().getStore()
const result = await migrationManager.migrateToLatest(store)
const result = await migrationManager.migrateTo(store, 2)
```

### 查询迁移状态

```typescript
// 获取当前数据库版本
const currentVersion = await migrationManager.getCurrentVersionFromDb(store)

// 获取最新迁移版本号
const latestVersion = migrationManager.getLatestVersion()

// 检查是否有待执行的迁移
const hasPending = migrationManager.hasPendingMigrations(currentVersion)

// 获取待执行的迁移列表
const pending = migrationManager.getPendingMigrations(currentVersion)

// 获取迁移摘要
const summary = migrationManager.getSummary()
console.log(summary)
// 输出:
// 已注册 3 个迁移脚本
// 最新版本: 3
// 当前版本: 1
// 
// 迁移列表:
//   v1: 创建用户表
//   v2: 添加年龄列
//   v3: 创建文章表
```

**版本表**：`MigrationManager` 使用内部版本表 `_orm_version` 记录当前 schema 版本。该表会在首次调用 `getCurrentVersionFromDb()` 或执行迁移时自动创建并初始化：

```sql
CREATE TABLE IF NOT EXISTS _orm_version (
  id INTEGER PRIMARY KEY,
  version INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL
)
```

若表中无记录，会自动插入一条初始记录：`id=1, version=0`。

### MigrationExecutionResult 结果类

```typescript
class MigrationExecutionResult {
  success: boolean                    // 是否全部成功
  fromVersion: number                 // 起始版本
  toVersion: number                   // 目标版本
  actualVersion: number               // 实际到达的版本
  executedCount: number               // 执行的迁移数量
  results: Array<MigrationResult>     // 各迁移执行结果
  errorMessage: string                // 错误信息
}

class MigrationResult {
  version: number        // 迁移版本号
  success: boolean       // 是否成功
  executionTime: number  // 执行时间（毫秒）
  errorMessage: string   // 错误信息
}
```

### 回滚迁移

```typescript
// 回滚到指定版本
const result = await migrationManager.migrateTo(store, 1)  // 从当前版本回滚到 v1

// 获取需要回滚的迁移列表
const rollbackMigrations = migrationManager.getRollbackMigrations(currentVersion, targetVersion)
```

---

## AutoMigration - 自动迁移

自动迁移功能通过比较实体元数据与数据库实际结构，自动生成并执行变更 SQL。

### 启用自动迁移

```typescript
import { OCORMInit, DatabaseConfig, AutoMigrationMode } from '@offlinecat/ocorm'

// 在初始化时启用自动迁移
await OCORMInit(this.context, {
  config: new DatabaseConfig('myapp.db'),
  autoMigrate: true,
  autoMigrationOptions: {
    includeJoinTables: true,
    mode: AutoMigrationMode.SAFE,  // 仅执行非破坏性变更
    logChanges: true
  }
})
```

`autoMigrationOptions` 为可选项，未传时使用默认行为：

- includeJoinTables 默认 true（除非显式传 false）
- mode 默认使用 MigrationManager 的 autoMigrationMode（默认 SAFE）
- logChanges 默认跟随 MigrationManager.enableLog（默认 true）

### AutoMigrationMode 迁移模式

```typescript
enum AutoMigrationMode {
  SAFE = 'SAFE',  // 仅允许非破坏性变更（新增表/列）
  FULL = 'FULL'   // 允许重建表等破坏性变更
}
```

| 模式 | 新增表 | 新增列 | 修改列 | 删除列 |
|------|--------|--------|--------|--------|
| SAFE | ✓ | ✓ | ✗ | ✗ |
| FULL | ✓ | ✓ | ✓ | ✓ |

### 手动执行自动迁移

```typescript
import { MigrationManager, AutoMigrationMode } from '@offlinecat/ocorm'

const migrationManager = new MigrationManager()

const result = await migrationManager.autoMigrateWithManager({
  includeJoinTables: true,
  mode: AutoMigrationMode.SAFE,
  logChanges: true
})

if (result.success) {
  console.log(`执行了 ${result.executedCount} 条 SQL`)
  console.log(`跳过了 ${result.skippedCount} 个破坏性变更`)
} else {
  console.log(`迁移失败: ${result.errorMessage}`)
}

// 查看执行的 SQL
for (const sql of result.executedSql) {
  console.log(sql)
}

// 查看跳过的变更
for (const change of result.skippedChanges) {
  console.log(`跳过: ${change.summary}`)
}
```

### SchemaDiffer - Schema 差异分析

`SchemaDiffer` 用于比较实体元数据与数据库实际结构的差异：

```typescript
import { SchemaDiffer, DatabaseManager } from '@offlinecat/ocorm'

const differ = new SchemaDiffer()
const store = DatabaseManager.getInstance().getStore()

const diff = await differ.diff(store, { includeJoinTables: true })

if (diff.hasChanges()) {
  console.log('检测到以下变更:')
  for (const change of diff.changes) {
    console.log(`- [${change.type}] ${change.summary}`)
    console.log(`  破坏性: ${change.destructive}`)
    console.log(`  SQL: ${change.sql.join('; ')}`)
  }
}
```

### SchemaChange 变更类型

```typescript
enum SchemaChangeType {
  CREATE_TABLE = 'CREATE_TABLE',    // 新建表
  ADD_COLUMN = 'ADD_COLUMN',        // 新增列
  REBUILD_TABLE = 'REBUILD_TABLE'   // 重建表（包含删除/修改列）
}

interface SchemaChange {
  type: SchemaChangeType
  tableName: string
  columnName?: string
  sql: Array<string>           // 执行的 SQL
  rollbackSql: Array<string>   // 回滚 SQL
  summary: string              // 变更描述
  destructive: boolean         // 是否为破坏性变更
}
```

---

## MigrationManagerOptions 配置选项

```typescript
const migrationManager = new MigrationManager({
  enableLog: true,                      // 是否记录迁移日志，默认 true
  logTableName: '_custom_migration_log', // 自定义日志表名（默认 _migrations）
  autoMigrationMode: AutoMigrationMode.SAFE  // 默认自动迁移模式
})
```

---

## 迁移日志

启用日志后，所有迁移操作会记录到 `_migrations` 表（可通过 `MigrationManagerOptions.logTableName` 自定义）：

```typescript
interface MigrationLogRecord {
  version?: number           // 迁移版本号（手动迁移时使用）
  name?: string              // 迁移名称或描述
  type: string               // 记录类型（例如：MIGRATION / AUTO_SCHEMA）
  direction?: string         // 迁移方向（UP / DOWN）
  tableName?: string         // 表名（自动迁移）
  columnName?: string        // 列名（自动迁移）
  sql?: string               // 执行的 SQL
  summary?: string           // 摘要
  success?: boolean          // 是否成功
  errorMessage?: string      // 错误信息
  createdAt?: number         // 创建时间戳（毫秒）；不传则自动使用 Date.now()
}
```

日志写入失败不会中断迁移主流程（内部会忽略日志写入错误）。

---

## 完整示例

### 项目迁移脚本管理

```typescript
// migrations/index.ets
import { Migration } from '@offlinecat/ocorm'
import { relationalStore } from '@kit.ArkData'

export class Migration_001_InitialSchema implements Migration {
  version = 1
  description = '初始化数据库结构'

  async up(store: relationalStore.RdbStore): Promise<void> {
    await store.executeSql(`
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT UNIQUE NOT NULL,
        created_at INTEGER NOT NULL
      )
    `)
  }

  async down(store: relationalStore.RdbStore): Promise<void> {
    await store.executeSql('DROP TABLE IF EXISTS users')
  }
}

export class Migration_002_AddUserAge implements Migration {
  version = 2
  description = '添加用户年龄字段'

  async up(store: relationalStore.RdbStore): Promise<void> {
    await store.executeSql('ALTER TABLE users ADD COLUMN age INTEGER DEFAULT 0')
  }

  async down(store: relationalStore.RdbStore): Promise<void> {
    // SQLite 不支持直接删除列，需要重建表
    await store.executeSql(`
      CREATE TABLE users_backup AS SELECT id, name, email, created_at FROM users
    `)
    await store.executeSql('DROP TABLE users')
    await store.executeSql('ALTER TABLE users_backup RENAME TO users')
  }
}

// 导出所有迁移
export const allMigrations: Array<Migration> = [
  new Migration_001_InitialSchema(),
  new Migration_002_AddUserAge()
]
```

### 应用初始化集成

```typescript
// EntryAbility.ets
import { OCORMInit, DatabaseConfig, MigrationManager } from '@offlinecat/ocorm'
import { allMigrations } from './migrations'

export default class EntryAbility extends UIAbility {
  async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Promise<void> {
    const config = new DatabaseConfig('myapp.db')
    
    // 注册迁移脚本
    const migrationManager = new MigrationManager({ enableLog: true })
    migrationManager.registerAll(allMigrations)
    
    // 初始化数据库并执行迁移
    await OCORMInit(this.context, {
      config,
      autoCreateTables: false,  // 使用迁移脚本，禁用自动建表
      migrationManager
    })
    
    // 执行迁移到最新版本
    const result = await migrationManager.migrateToLatestWithManager()
    if (!result.success) {
      console.error(`迁移失败: ${result.errorMessage}`)
    }
  }
}
```

---

## 最佳实践

1. **版本号递增** - 迁移脚本的版本号必须唯一且递增
2. **编写回滚脚本** - 每个 `up` 都应有对应的 `down`，便于回滚
3. **生产环境使用 SAFE 模式** - 避免意外的数据丢失
4. **测试迁移脚本** - 在开发环境充分测试后再上线
5. **备份数据** - 执行破坏性迁移前务必备份数据
6. **使用事务** - 迁移操作会自动在事务中执行，失败时自动回滚

