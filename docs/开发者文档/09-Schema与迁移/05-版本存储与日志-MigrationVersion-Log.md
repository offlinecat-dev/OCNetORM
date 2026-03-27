# 05-版本存储与日志-MigrationVersion-Log

> 状态：已完成
> 适用版本：ocorm 3.x（当前仓库实现）
> 最后更新：2026-03-27

## 1. 目标
- 说明 `MigrationVersionStore` 如何维护 `_orm_version` 表中的单行版本状态。
- 说明 `MigrationLogManager` / `MigrationLogService` 如何把手动迁移与自动迁移记录落到 `_migrations`。
- 明确版本推进、日志写入、失败处理三者的边界，避免把日志成功误当成迁移成功。

## 2. 版本存储规则
- 版本表名固定为 `_orm_version`，主键固定为 `id = 1`。
- `getCurrentVersionFromDb(store)` 会先 `ensureVersionTable(store)`，表不存在时自动创建，记录不存在时自动插入版本 `0`。
- `updateVersionInDb(store, version)` 先按 `id = 1` 更新；若受影响行数为 `0`，则补插一条记录。
- `MigrationVersionStore` 自身不负责事务；它只在调用成功后通过构造函数注入的 `setVersion(version)` 同步内存版本。

```sql
-- MigrationVersionStore.ensureVersionTable 的真实结构
CREATE TABLE IF NOT EXISTS _orm_version (
  id INTEGER PRIMARY KEY,
  version INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL
);
```

```arkts
import { MigrationVersionStore } from '../schema/MigrationVersionStore'

let currentVersion = 0
const versionStore = new MigrationVersionStore((version) => currentVersion = version)

const before = await versionStore.getCurrentVersionFromDb(store)
await versionStore.updateVersionInDb(store, before + 1)

console.info(`dbBefore=${before}, inMemoryNow=${currentVersion}`)
```

## 3. 日志存储规则
- 默认日志表名为 `_migrations`，也可在 `MigrationLogManager(tableName)` 中自定义。
- `MigrationLogManager.log()` 会先 `ensureTable(store)`，再插入一条日志记录。
- `tableName`、`columnName` 会经过清洗：
  - `trim()`
  - 移除控制字符
  - 空值转 `null`
  - 最长截断到 128 字符
- `MigrationLogService` 是安全包装层：
  - `safeLog()` 吞掉日志异常
  - `safeLogBatch()` 顺序写入多条记录
  - `safeLogSchemaChange()` 固定写入 `type='AUTO_SCHEMA'`、`direction='UP'`

```sql
-- MigrationLogManager.ensureTable 的真实结构
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

```arkts
import { MigrationLogManager } from '../schema/MigrationLogManager'

const logManager = new MigrationLogManager('_migrations')
await logManager.log(store, {
  version: 2,
  name: 'Add user.email',
  type: 'MIGRATION',
  direction: 'UP',
  tableName: 'user',
  columnName: 'email',
  sql: 'ALTER TABLE "user" ADD COLUMN "email" TEXT',
  summary: '新增列 user.email',
  success: true
})
```

## 4. 正确迁移示例（推荐）
- 正确用法是让 `MigrationRunner` / `MigrationManager` 在事务成功后推进 `_orm_version`，并由 `MigrationLogService` 负责记录。
- 直接使用底层类时，也应保持“业务 SQL 成功后再更新版本”的顺序。

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

const manager = new MigrationManager({
  enableLog: true,
  logTableName: '_migrations'
})
manager.register(new V1CreateUserTable())

const result = await manager.migrateToLatest(store)
if (!result.success) {
  throw new Error(`迁移失败: ${result.errorMessage}`)
}
```

```sql
-- 迁移成功后，版本表与日志表应同时可观测
SELECT version, updated_at
FROM _orm_version
WHERE id = 1;

SELECT version, name, type, direction, success, created_at
FROM "_migrations"
ORDER BY id DESC
LIMIT 20;
```

## 5. 误用示例（禁止）
- 误用 1：业务 SQL 还没成功就提前写 `_orm_version`。
- 误用 2：把 `safeLog()` 当成强一致日志接口，指望日志失败时中断主迁移。
- 误用 3：直接写入未清洗的表名/列名并假设落库值与原始输入完全一致。

```arkts
import { MigrationVersionStore } from '../schema/MigrationVersionStore'

const versionStore = new MigrationVersionStore((_version) => {})

// 误用：业务迁移还未执行，先把版本改到 5
await versionStore.updateVersionInDb(store, 5)
await store.executeSql('CREATE TABLE broken_sql')
```

```arkts
import { MigrationLogService } from '../schema/MigrationLogService'

const logService = new MigrationLogService(true, '_migrations')

// 误用：safeLog 内部吞异常，下面的 try/catch 不能代表日志一定落库
try {
  await logService.safeLog(store, { type: 'MIGRATION', summary: 'expect strict logging' })
  console.info('这里只能说明 safeLog 调用结束，不能说明日志一定成功')
} catch (error) {
  console.info('通常不会进入这里')
}
```

```arkts
import { MigrationLogManager } from '../schema/MigrationLogManager'

const logManager = new MigrationLogManager('_migrations')
await logManager.log(store, {
  type: 'AUTO_SCHEMA',
  tableName: '  tb_with_space_and_control_\n',
  columnName: '\u0000email\u0001',
  success: true
})

// 误用：不要假设数据库里保存的是原始字符串
```

## 6. 失败处理 / 日志 / 回滚说明
- `MigrationVersionStore` 失败会抛 `ExecutionError`：
  - 读版本失败：`获取数据库版本失败`
  - 更新版本失败：`更新数据库版本失败`
  - 建版本表失败：`创建版本表失败`
- `MigrationLogManager.log()` 失败也会抛 `ExecutionError`，但如果它被 `MigrationLogService.safeLog()` 包裹，异常会被吞掉。
- 版本存储与日志存储本身都不负责 `rollBack()`；真正的事务回滚由 `MigrationRunner` 或 `AutoMigrationHandler` 驱动。
- 因此排障顺序应是：
  - 先看主迁移结果 `success/errorMessage`
  - 再看 `_orm_version`
  - 最后看 `_migrations`

```arkts
import { MigrationVersionStore } from '../schema/MigrationVersionStore'

const versionStore = new MigrationVersionStore((_version) => {})

try {
  await versionStore.updateVersionInDb(store, 7)
} catch (error) {
  const message = error instanceof Error ? error.message : String(error)
  console.error(`版本写入失败: ${message}`)
  // 这里没有自动回滚，外层事务必须自己处理
}
```

```sql
-- 排障顺序 1：版本是否推进
SELECT id, version, updated_at
FROM _orm_version
WHERE id = 1;

-- 排障顺序 2：最近失败日志
SELECT version, name, type, direction, summary, success, error_message, created_at
FROM "_migrations"
WHERE success = 0
ORDER BY id DESC
LIMIT 20;
```

## 7. 验收清单
- `_orm_version` 在首次读取时可自动创建并初始化为版本 `0`。
- 删除 `_orm_version` 的唯一版本行后，再次迁移可自动恢复该行。
- `_migrations.table_name` / `column_name` 会被裁剪和清洗，不保留控制字符。
- 日志写入失败不会反向改变主迁移结果。

## 8. 变更记录
- 2026-03-27：基于 `MigrationVersionStore`、`MigrationLogManager`、`MigrationLogService` 及对应测试补全文档。
