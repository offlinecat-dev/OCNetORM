# 02-使用手册

面向纯库使用者的执行导读，只覆盖公开 API 与可落地用法。

## 使用前确认（2 分钟）

- 已完成依赖安装并可正常编译。
- 已按接入文档完成初始化入口，应用启动后会执行 `OCORMInit`。
- 实体已通过 `defineEntity` 或 `Table`/`Column`/`PrimaryKey` 完成注册。

## 按问题选读

| 你的问题 | 先读 | 再读 | 对应核心 API |
| --- | --- | --- | --- |
| 我第一次接入，最小可运行配置是什么？ | [01-项目接入](./01-项目接入/README.md) | [02-实体与建模](./02-实体与建模/README.md) | `OCORMInit`、`DatabaseConfig` |
| 我该用 `defineEntity` 还是装饰器建模？ | [02-defineEntity与EntitySchema](./02-实体与建模/02-defineEntity与EntitySchema.md) | [03-装饰器建模方式](./02-实体与建模/03-装饰器建模方式.md) | `defineEntity`、`Table`、`Column`、`PrimaryKey` |
| 我需要条件查询、关联加载、分页与缓存 | [03-查询](./03-查询/README.md) | [10-性能调优](./10-性能调优/README.md) | `QueryBuilder`、`QueryExecutor`、`QueryCache` |
| 我要做 CRUD、事务、批量写入、原生 SQL | [04-仓储与事务](./04-仓储与事务/README.md) | [09-安全与最佳实践](./09-安全与最佳实践/README.md) | `Repository`、`TransactionOptions` |
| 我需要做数据映射、类型转换或 ViewModel 映射 | [05-映射与数据转换](./05-映射与数据转换/README.md) | [06-验证与钩子](./06-验证与钩子/README.md) | `EntityData`、`TypedEntityData`、`TypeConverter` |
| 我要管理建表与迁移 | [07-Schema与迁移](./07-Schema与迁移/README.md) | [08-工具链](./08-工具链/README.md) | `SchemaBuilder`、`MigrationManager` |
| 线上报错如何定位？ | [11-日志与错误处理](./11-日志与错误处理/README.md) | [09-安全与最佳实践](./09-安全与最佳实践/README.md) | `Logger`、错误码与错误类型 |

## 最短学习路径（建议 60-90 分钟）

1. [00-术语表](./00-术语表.md)（5 分钟）：先统一术语，避免把概念和 API 对错。
2. [01-项目接入](./01-项目接入/README.md)（10 分钟）：跑通 `DatabaseConfig + OCORMInit`。
3. [02-实体与建模](./02-实体与建模/README.md)（15 分钟）：二选一确定建模方式（`defineEntity` 或装饰器）。
4. [04-仓储与事务](./04-仓储与事务/README.md)（20 分钟）：掌握 `Repository` 与事务边界。
5. [03-查询](./03-查询/README.md)（20 分钟）：掌握 `QueryBuilder` 的过滤、关联、分页与缓存。
6. [07-Schema与迁移](./07-Schema与迁移/README.md)（10 分钟）：确定建表与迁移策略。
7. [11-日志与错误处理](./11-日志与错误处理/README.md)（10 分钟）：建立线上故障排查闭环。

## 目录

- [00-术语表](./00-术语表.md)
- [01-项目接入](./01-项目接入/README.md)
- [02-实体与建模](./02-实体与建模/README.md)
- [03-查询](./03-查询/README.md)
- [04-仓储与事务](./04-仓储与事务/README.md)
- [05-映射与数据转换](./05-映射与数据转换/README.md)
- [06-验证与钩子](./06-验证与钩子/README.md)
- [07-Schema与迁移](./07-Schema与迁移/README.md)
- [08-工具链](./08-工具链/README.md)
- [09-安全与最佳实践](./09-安全与最佳实践/README.md)
- [10-性能调优](./10-性能调优/README.md)
- [11-日志与错误处理](./11-日志与错误处理/README.md)
