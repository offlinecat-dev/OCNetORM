# 05-Schema-迁移与工具链API

> 状态：已完成
> 适用版本：ocorm 3.0.2
> 最后更新：2026-03-28
> 对照源码：`src/main/ets/schema/*`、`src/main/ets/tools/*`

## 1. 覆盖范围

这页覆盖两块能力：

- Schema / migration：`SchemaBuilder`、`SchemaInspector`、`SchemaDiffer`、`MigrationManager`
- 工具链：`MigrationGenerator`、`SeederManager`、`defineFactory`

深入章节看：

- [`../09-Schema与迁移/01-SchemaBuilder建表策略.md`](../09-Schema与迁移/01-SchemaBuilder建表策略.md)
- [`../09-Schema与迁移/04-MigrationManager执行流程.md`](../09-Schema与迁移/04-MigrationManager执行流程.md)
- [`../10-工具链/04-工具链组合工作流.md`](../10-工具链/04-工具链组合工作流.md)

## 2. API 快表

| 类/能力 | 代表方法 | 说明 |
| --- | --- | --- |
| `SchemaBuilder` | `generateCreateTableSql()`、`createTable()`、`createAllTablesWithManager()` | 生成建表 SQL 与实际建表 |
| `SchemaInspector` | `getExistingTables()`、`getTableInfo()`、`getTableIndexes()` | 读取数据库现状 |
| `SchemaDiffer` | `diff()` | 计算目标元数据与现有库的差异 |
| `MigrationManager` | `register()`、`migrateTo()`、`migrateToLatest()`、`autoMigrate()` | 注册并执行迁移 |
| `MigrationVersionStore` | `getCurrentVersionFromDb()`、`updateVersionInDb()` | 版本号读写 |
| `MigrationGenerator` | `generate()`、`generateWithStore()` | 基于差异生成迁移草稿 |
| `SeederManager` | `run()` | 顺序执行 Seeder 队列 |
| `EntityFactory` / `defineFactory` | `make()`、`makeMany()`、`create()`、`createMany()` | 构造或落库测试/演示数据 |

## 3. 建表与自动迁移

```ts
import {
  DatabaseConfig,
  MigrationManager,
  OCORMInit,
  SchemaBuilder
} from 'ocorm'

await OCORMInit(context, {
  config: new DatabaseConfig('app.db'),
  autoMigrate: true,
  migrationManager: new MigrationManager()
})

const builder = new SchemaBuilder()
const createResult = await builder.createAllTablesWithManager()
console.info(`tableCount=${createResult.results.length}`)
```

选择原则：

- 冷启动直接建表：`SchemaBuilder.createAllTablesWithManager()`
- 需要升级路径和版本管理：`MigrationManager.autoMigrateWithManager()` / `migrateToLatestWithManager()`
- 应用统一入口：`OCORMInit({ autoMigrate: true })`

## 4. 差异计算与数据库探测

```ts
import {
  DatabaseManager,
  SchemaDiffer,
  SchemaInspector
} from 'ocorm'

const store = DatabaseManager.getInstance().getStore()
const inspector = new SchemaInspector()
const differ = new SchemaDiffer(inspector)

const tables = await inspector.getExistingTables(store)
const info = await inspector.getTableInfo(store, 'users')
const indexes = await inspector.getTableIndexes(store, 'users')
const diff = await differ.diff(store, { includeJoinTables: true })

console.info(JSON.stringify(tables))
console.info(JSON.stringify(info))
console.info(JSON.stringify(indexes))
console.info(`hasChanges=${diff.hasChanges()}`)
```

这条链路是发布前核对 Schema 的标准入口。不要只看元数据，不看真实库。

## 5. 迁移管理器

```ts
import { DatabaseManager, MigrationManager } from 'ocorm'

const store = DatabaseManager.getInstance().getStore()
const manager = new MigrationManager()

manager.register(migration20260327010101)
manager.register(migration20260327010202)

const currentVersion = await manager.getCurrentVersionFromDb(store)
const latest = manager.getLatestVersion()
const result = await manager.migrateToLatest(store)

console.info(`current=${currentVersion}, latest=${latest}, success=${result.success}`)
```

配合阅读：

- [`../09-Schema与迁移/05-版本存储与日志-MigrationVersion-Log.md`](../09-Schema与迁移/05-版本存储与日志-MigrationVersion-Log.md)
- [`../15-升级与兼容/03-Breaking-Changes清单.md`](../15-升级与兼容/03-Breaking-Changes清单.md)

## 6. 自动生成迁移文件

```ts
import { MigrationGenerator } from 'ocorm'

const generated = await MigrationGenerator.generate({
  includeJoinTables: true,
  classNamePrefix: 'Migration',
  fileExtension: 'ets'
})

console.info(generated.fileName)
console.info(generated.description)
console.info(generated.content)
```

`MigrationGenerator` 生成的是“迁移草稿”，不是免审查产物。生成后仍然要检查：

- `upSql` / `downSql` 是否符合预期
- 是否误伤线上已有数据
- 是否需要手工补数据迁移逻辑

## 7. Seeder 与 Factory

```ts
import {
  SeederManager,
  SeederClass,
  defineFactory
} from 'ocorm'

const userFactory = defineFactory('User', (faker, index) => ({
  userName: `${faker.name()}-${index}`,
  age: faker.number({ min: 18, max: 60 })
}))

class UserSeeder extends SeederClass {
  entityName: string = 'User'

  async run(repo) {
    const users = await userFactory.makeMany(3)
    for (let i = 0; i < users.length; i++) {
      await repo.save(users[i])
    }
  }
}

const seedResult = await SeederManager.run([new UserSeeder()])
console.info(JSON.stringify(seedResult))
```

使用边界：

- `make()` / `makeMany()`：只构造数据，不落库
- `create()` / `createMany()`：构造后直接保存
- `SeederManager.run()`：顺序执行 Seeder，并返回统一执行结果

## 8. 推荐组合工作流

```text
建模变更 -> SchemaDiffer.diff() -> MigrationGenerator.generate() -> 手工审迁移
          -> MigrationManager.register() -> 测试环境 migrateToLatest()
          -> SeederManager.run() / defineFactory() 造数 -> 回归验证
```

如果这条链路里任何一步没做，发布风险就会转嫁到线上排障。

## 9. 继续下钻

- 数据库与连接：[`04-数据库-连接池与测试钩子API.md`](./04-数据库-连接池与测试钩子API.md)
- 深度章节：[`../09-Schema与迁移/04-MigrationManager执行流程.md`](../09-Schema与迁移/04-MigrationManager执行流程.md)、[`../10-工具链/04-工具链组合工作流.md`](../10-工具链/04-工具链组合工作流.md)

## 10. 变更记录

- 2026-03-28：补齐 Schema、迁移、Seeder、Factory、MigrationGenerator API 速查。
