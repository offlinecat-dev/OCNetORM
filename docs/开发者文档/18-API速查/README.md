# 18-API速查

> 状态：已完成
> 适用版本：ocorm 3.0.2
> 最后更新：2026-03-28

## 1. 这目录怎么用

这不是教程章节，它只回答三个问题：

1. 这个能力从哪个导出进。
2. 典型调用长什么样。
3. 想看实现语义时，应该跳回哪一组深度文档。

如果你准备系统学习，请先看 [`../00-导航与约定/01-文档阅读路径.md`](../00-导航与约定/01-文档阅读路径.md)。
如果你已经在写代码，只想快速确认 API，直接按下面索引跳。

## 2. 目录索引

| 文件 | 覆盖导出面 | 推荐在什么场景看 |
| --- | --- | --- |
| [`01-核心入口-错误与类型API.md`](./01-核心入口-错误与类型API.md) | `OCORMInit`、`defineEntity`、`OrmContext`、装饰器、错误与日志、基础类型 | 起步初始化、建模入口、全局配置 |
| [`02-查询-关系与缓存API.md`](./02-查询-关系与缓存API.md) | `QueryBuilder`、`QueryExecutor`、`RelationLoader`、`QueryCache` | 列表查询、聚合、关系加载、缓存 |
| [`03-仓储-事务与原生SQLAPI.md`](./03-仓储-事务与原生SQLAPI.md) | `Repository`、`TransactionOptions`、`BatchInsertOptions`、`rawQuerySafe` | CRUD、事务、批量写入、原生 SQL |
| [`04-数据库-连接池与测试钩子API.md`](./04-数据库-连接池与测试钩子API.md) | `DatabaseConfig`、`DatabaseManager`、`StoreLease`、`DefaultDatabaseSession`、`DatabaseManagerTestHooks` | 连接层初始化、连接池调优、测试隔离 |
| [`05-Schema-迁移与工具链API.md`](./05-Schema-迁移与工具链API.md) | `SchemaBuilder`、`SchemaDiffer`、`MigrationManager`、`MigrationGenerator`、`SeederManager`、`defineFactory` | 建表、迁移、种子、工厂 |
| [`06-映射-验证与装饰器API.md`](./06-映射-验证与装饰器API.md) | `DataMapper`、`ResultSetUtils`、`EntityValidator`、`ValidationMetadataStorage`、`HooksProcessor`、验证装饰器 | DTO 映射、校验规则、钩子 |

## 3. 包级导出入口

所有速查项都以 `OCORM/Index.ets` 为准。正常业务代码只需要从 `ocorm` 包导入，不要绕过包级出口去引用内部文件。

```ts
import {
  OCORMInit,
  QueryBuilder,
  Repository,
  DatabaseConfig,
  SchemaBuilder,
  DataMapper,
  Required,
  ValidationError
} from 'ocorm'
```

如果你需要核对当前版本到底暴露了什么，直接看仓库里的统一出口：

```text
OCORM/Index.ets
  -> src/main/ets/core/index.ets
  -> src/main/ets/query/index.ets
  -> src/main/ets/repository/index.ets
  -> src/main/ets/database/index.ets
  -> src/main/ets/schema/index.ets
  -> src/main/ets/mapping/index.ets
  -> src/main/ets/validation/index.ets
  -> src/main/ets/tools/index.ets
  -> src/main/ets/decorators/index.ets
  -> src/main/ets/types/index.ets
```

## 4. 交叉引用规则

速查页和深度页的职责边界固定如下：

- 速查页：只给导出入口、常用方法、典型片段、风险提示、跳转链接。
- 深度页：解释内部语义、边界条件、测试覆盖、性能约束和审查结论。
- 同一个 API 如果涉及安全、性能、测试，优先把深入说明放在 `12`、`13`、`14`，速查页只给跳转。

```powershell
# 校验目录是否完整
Get-ChildItem 'OCORM/docs/开发者文档/18-API速查' -Name

# 检查速查页是否还残留骨架占位符
$draftTokens = @('状态：草' + '稿', '待补' + '充', 'TO' + 'DO', 'TB' + 'D')
rg -n ($draftTokens -join '|') 'OCORM/docs/开发者文档/18-API速查'
```

## 5. 推荐跳转

- 初始化 / 建模：[`01-核心入口-错误与类型API.md`](./01-核心入口-错误与类型API.md)
- 查询 / 关系 / 缓存：[`02-查询-关系与缓存API.md`](./02-查询-关系与缓存API.md)
- CRUD / 事务 / 原生 SQL：[`03-仓储-事务与原生SQLAPI.md`](./03-仓储-事务与原生SQLAPI.md)
- 连接池 / Session / 测试钩子：[`04-数据库-连接池与测试钩子API.md`](./04-数据库-连接池与测试钩子API.md)
- Schema / 迁移 / Seeder / Factory：[`05-Schema-迁移与工具链API.md`](./05-Schema-迁移与工具链API.md)
- DataMapper / 验证 / 钩子：[`06-映射-验证与装饰器API.md`](./06-映射-验证与装饰器API.md)

## 6. 变更记录

- 2026-03-28：补齐 `18-API速查` 全部目录索引，并统一到中文编号命名。
