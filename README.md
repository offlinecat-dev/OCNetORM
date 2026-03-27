# ocorm

> HarmonyOS / OpenHarmony 的 ArkTS SQLite ORM
> 当前文档对应版本：`3.0.2`
> 交流 QQ 群：`1012852504`

`ocorm` 基于 `@ohos.data.relationalStore` 构建，提供统一的 `Repository`、`QueryBuilder`、`QueryExecutor`、Schema/迁移、验证、钩子和工具链能力。

仓库入口：<https://github.com/offlinecat-dev/OCNetORM>

## 1. 3.0.2 重点

3.0.2 不是单纯补丁版，它把 3.0 的安全与可维护性继续收口到了更稳定的状态：

- 原生 SQL 继续收紧：`rawQuery/rawQuerySafe/rawExecute` 默认强制参数化
- 连接层测试桥接下沉到 `DatabaseManagerTestHooks`，主类职责更干净
- `QueryExecutor` / `RelationLoader` / `Repository` 多个大文件继续拆分，复杂度显著下降
- 回归测试补强，重点覆盖事务并发、原生 SQL 守卫、连接关闭类问题

完整变更见 [`CHANGELOG.md`](./CHANGELOG.md)。

## 2. 安装

在 HarmonyOS 项目的 `oh-package.json5` 中添加依赖：

```json5
{
  "dependencies": {
    "ocorm": "3.0.2"
  }
}
```

或使用命令：

```bash
ohpm install ocorm
```

## 3. 30 秒上手

### 3.1 定义实体

```ts
import { ColumnType, defineEntity } from 'ocorm'

defineEntity('User', {
  tableName: 'users',
  columns: [
    { property: 'id', name: 'id', primaryKey: true, autoIncrement: true },
    { property: 'userName', name: 'user_name', type: ColumnType.TEXT, unique: true },
    { property: 'age', name: 'age', type: ColumnType.INTEGER, nullable: true }
  ],
  softDelete: true
})
```

### 3.2 初始化数据库

```ts
import { DatabaseConfig, LogLevel, OCORMInit } from 'ocorm'

const config = new DatabaseConfig('app.db')
  .setQueryCache(true, 200, 60_000)
  .setQueryTimeout(1500)
  .setMaxConcurrentQueries(4)

await OCORMInit(context, {
  config,
  autoCreateTables: true,
  enableLogger: true,
  logLevel: LogLevel.INFO
})
```

### 3.3 保存与查询

```ts
import {
  ConditionOperator,
  EntityData,
  EntityDataInput,
  QueryExecutor,
  Repository
} from 'ocorm'

const userRepo = new Repository('User')
const input = EntityDataInput.create()
input.set('userName', 'neo')
input.set('age', 28)

const user = EntityData.from('User', input)
await userRepo.save(user)

const qb = userRepo.createQueryBuilder()
  .where('age', ConditionOperator.GREATER_EQUAL, 18)
  .orderBy('userName', 'ASC')
  .paginate(1, 20)

const page = await new QueryExecutor(qb).getPaginated()
console.info(`total=${page.total}`)
```

## 4. 常用能力

### 4.1 事务

```ts
import { Repository, TransactionOptions } from 'ocorm'

const userRepo = new Repository('User')

await userRepo.transaction(async (txRepo) => {
  await txRepo.save(user)
})

await userRepo.transactionWithOptions(
  async (txRepo) => {
    await txRepo.save(user)
  },
  TransactionOptions.withTimeout(1500)
)
```

事务边界：

- 事务回调内统一使用 `txRepo`
- 不支持同一 `Repository` 嵌套事务
- 不支持跨 `Repository` 嵌套事务
- 当前仅建议使用 `READ_COMMITTED` / `READ_UNCOMMITTED`

### 4.2 原生 SQL

```ts
import { Repository } from 'ocorm'

const userRepo = new Repository('User')

const rows = await userRepo.rawQuerySafe(
  'SELECT id, user_name FROM users WHERE age >= ?',
  [18]
)

await userRepo.rawExecute(
  'UPDATE users SET user_name = ? WHERE id = ?',
  ['trinity', 1]
)
```

安全约束：

- 必须参数化
- `rawExecute` 仅允许写语句白名单
- 多语句、注释片段、危险关键字会被拒绝

### 4.3 Schema / 工具链

```ts
import {
  MigrationGenerator,
  MigrationManager,
  SchemaBuilder,
  SeederManager,
  defineFactory
} from 'ocorm'

const builder = new SchemaBuilder()
await builder.createAllTablesWithManager()

const generated = await MigrationGenerator.generate()
console.info(generated.fileName)

const userFactory = defineFactory('User', (faker, index) => ({
  userName: `${faker.name()}-${index}`,
  age: faker.number({ min: 18, max: 60 })
}))

await SeederManager.run([])
```

## 5. 能力概览

- 建模：`defineEntity`、装饰器建模、`ScopeRegistry`
- 查询：链式条件、分页、聚合、`whereExists`、`withWhere`、`withCount`
- 仓储：CRUD、批量写入、关系写入、事务、原生 SQL
- 数据库层：连接池、查询并发槽、Session、测试钩子
- 映射与治理：`DataMapper`、验证、生命周期钩子、错误国际化、日志脱敏
- Schema 与工具链：建表、差异计算、迁移、Seeder、Factory、MigrationGenerator

## 6. 3.x 行为提醒

从 2.x 升到 3.x，重点不是“API 全换了”，而是默认行为更严格了：

- `DatabaseConfig.encrypt` 默认值为 `true`
- `rawQuery/rawQuerySafe/rawExecute` 默认强制参数化
- 实体查询模式 `get/getPaginated/count` 不支持 `selectRaw/groupBy/having`
- `TransactionOptions.serializable()` 为 fail-fast
- 只读事务与部分隔离级别在底层不支持时会明确失败，不再静默降级

## 7. 文档入口

推荐顺序：

1. [开发者文档总索引](./docs/开发者文档/README.md)
2. [API 速查](./docs/开发者文档/18-API速查/README.md)
3. [2.x 到 3.x 升级指南](./docs/开发者文档/15-升级与兼容/01-2.x到3.x升级指南.md)
4. [3.0.1 到 3.0.2 行为变化](./docs/开发者文档/15-升级与兼容/02-3.0.1-3.0.2行为变化.md)
5. [SQL 注入防护策略](./docs/开发者文档/12-安全基线/01-SQL注入防护策略.md)
6. [测试分层与目录映射](./docs/开发者文档/14-测试与验收/01-测试分层与目录映射.md)
7. [变更记录](./CHANGELOG.md)
8. [示例说明](./example/README.md)

## 8. 构建与测试

```bash
ohpm install
hvigor assembleHar
hvigor test
```

如果你在多模块工程里联调 `entry`，也需要看仓库根目录下的示例与回归套件入口。

## 9. 兼容性

- HarmonyOS NEXT
- OpenHarmony 5.0+
- ArkTS
- SQLite / `@ohos.data.relationalStore`

## 10. License

MIT
