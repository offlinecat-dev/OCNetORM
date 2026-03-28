# 04-API参考

本目录只覆盖 `Index.ets` 对外导出的公共 API，并与 `src/main/ets/**` 实现保持一一对应。

## 分层索引

1. [core](./core/README.md)  
   初始化入口、实体注册、作用域、全局上下文事件
2. [query](./query/README.md)  
   QueryBuilder / QueryExecutor / RelationLoader / QueryCache
3. [repository](./repository/README.md)  
   Repository、事务、批量写入、原生 SQL 安全守卫
4. [schema](./schema/README.md)  
   SchemaBuilder、SchemaInspector、SchemaDiffer、MigrationManager
5. [mapping](./mapping/README.md)  
   DataMapper、TypeConverter、ViewModelMapper
6. [validation](./validation/README.md)  
   ValidationDecorators、ValidationMetadataStorage、EntityValidator

## 全局约束速记

- 参数化 SQL 是强约束：`rawQuery/rawQuerySafe/rawExecute` 均要求 `?` 占位符且参数数量匹配。
- 并发事务有守卫：连接池启用且存在活动事务时，未绑定事务上下文的写入会被拒绝。
- 超时语义分层：查询超时由 `QueryBuilder.timeout()` 或 `DatabaseConfig.queryTimeoutMs` 控制；事务超时由 `TransactionOptions.timeout` 控制，超时后会触发后台清理流程。

## 范围声明

- 仅文档化公共 API 契约：用途 / 参数 / 返回 / 异常 / 副作用 / 事务上下文 / 最小示例。
- 不包含：测试专用钩子、内部连接池细节实现、`entry` 模块测试基建。
