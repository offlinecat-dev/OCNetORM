# CHANGELOG

## [2.4.37] - 2026-02-21

### 安全加固
- 强化 `HAVING` 安全校验：新增危险 SQL 关键字拦截，阻断 `UNION/SELECT/FROM/JOIN` 等高风险片段
- 强化 `ORDER BY` 方向校验：`QueryBuilder.orderBy` 增加运行时白名单（仅允许 `ASC/DESC`）
- 增加二次防线：`QueryExecutor` 与 `AggregateExecutor` 在 SQL 组装阶段再次校验排序方向
- 降低事务配置串扰风险：`TransactionManager` 对事务入口新增串行互斥，避免连接级 `PRAGMA` 在并发事务间互相影响
- 修复事务锁释放时机：超时场景下等待内部回滚/清理结束后再释放锁，避免后续事务提前进入
- 提升安全默认值：`DatabaseConfig.encrypt` 默认由 `false` 调整为 `true`
- 降低慢查询信息泄露风险：`OrmContext.emitSlowQuery` 改为透传脱敏后的 SQL 预览
- 消除隔离级别语义冲突：`TransactionOptions.serializable()` 改为前置失败，避免“构造成功、执行期才失败”
- 修正更新日志语义：`CrudOperations` 的 UPDATE 日志补齐 `SET` 片段，避免排障误导

### 测试
- `entry/src/test/EntryOrmSecurityFix.test.ets` 新增安全回归：
  - `having` 关键字拦截
  - `orderBy` 方向运行时校验
  - 篡改排序方向的执行层拦截
  - 事务并发串行化验证
  - 默认加密配置验证
  - 慢查询 SQL 脱敏事件验证
- `OCORM/src/test/Stage9Database/Database.test.ets` 同步更新默认加密断言

## [2.4.36] - 2026-02-13

### 修复
- 修复 `#8 类型转换静默改写`：`TypeConverter.toDbValue` 在 `INTEGER/REAL` 场景下，非法输入默认改为抛出 `TypeConversionError`，不再静默回退为 `0`
- 新增 `toDbValue` 宽松模式：仅当显式传入 `{ strict: false, fallbackValue }` 时才返回兜底值
- `DataMapper` 调用 `toDbValue` 时补充列名参数，确保类型错误上下文可定位到具体列

### 测试
- `OCORM/src/test/Stage4Mapping/TypeConverter.test.ets` 新增 strict 抛错与 lenient 兜底回归，并修正 REAL 字符串数值断言
- `entry/src/main/ets/suites/MappingSuite.ets` 新增 `TypeConverter_ToDbValue_StrictAndLenient` 集成回归

## [2.4.35] - 2026-02-13

### 修复
- 修复 `#6 Unique` 并发竞态收敛不足：`@Unique` 规则自动映射为数据库唯一索引（含 SchemaBuilder/SchemaDiffer 路径）
- 修复写入阶段唯一冲突语义不一致：`CrudOperations` 在数据库唯一约束失败时统一抛出 `UniqueValidationError`

### 测试
- `OCORM/src/test/Stage7Repository/SaveInsertUpdate.test.ets` 新增数据库唯一冲突映射回归（insert/update）
- `OCORM/src/test/Stage10SchemaMigration/SchemaBuilder.test.ets` 新增 `@Unique` 规则索引生成回归
- `OCORM/src/test/Stage10SchemaMigration/SchemaDiffer.test.ets` 新增 `@Unique` 规则索引差异回归

## [2.4.34] - 2026-02-13

### 修复
- 修复切库缓存串库风险：`QueryCache` 缓存键新增数据库命名空间，`DatabaseManager` 在连接配置变化时强制清空缓存并绑定当前命名空间
- 强化 `rawExecute` 安全护栏：仅允许参数化 `INSERT/UPDATE/DELETE/REPLACE`，拒绝多语句、SQL 注释片段和危险关键字

### 测试
- `OCORM/src/test/Stage8Cache/QueryCache.test.ets` 新增命名空间隔离与按命名空间失效回归
- `OCORM/src/test/Stage9Database/Database.test.ets` 新增切库清缓存与命名空间同步回归
- `OCORM/src/test/Stage7Repository/RepositoryQuery.test.ets` 新增 rawExecute 安全闸回归
- `entry/src/main/ets/suites/QuerySuite.ets` 新增 rawExecute 安全闸集成回归

## [2.4.33] - 2026-02-13

### 修复
- 强化 `Critical #2`：`CrudOperations.save` / `DeleteOperations.remove` 在需要级联原子性时，`SAVEPOINT` 不可用将立即失败，不再静默降级为“跳过 savepoint”
- 强化回滚可靠性：保存点 `RELEASE/ROLLBACK` 失败改为显式报错，避免吞错导致的“假成功”
- 调整 `RelationManager.sync`：优先使用 `SAVEPOINT`；若语句不被底层支持则自动回退旧事务模式
- 强化 `WP-03` 事务语义：`REPEATABLE_READ` / `SERIALIZABLE` 改为显式拒绝，不再映射为兼容降级
- 强化 `WP-03` 只读语义：`PRAGMA query_only` 设置失败改为立即失败，不再降级执行

### 测试
- `entry/src/test/EntryOrmCriticalFix.test.ets` 新增回归：
  - save/remove 在 savepoint 不可用时应阻断写入
  - sync 在 savepoint 路径下的提交与回滚行为
- 事务语义回归补充：
  - `entry/src/test/EntryOrmReviewFix.test.ets` 覆盖 readOnly/隔离级别强语义失败
  - `OCORM/src/test/Stage7Repository/RepositoryTransaction.test.ets` 覆盖配置错误不启动事务

## [2.4.32] - 2026-02-10

### 新增
- `QueryBuilder` 新增 `chunk(batchSize, callback)` 分块查询 API（大数据量分批处理）

### 改进
- `QueryExecutor` 新增分块执行能力，支持自动恢复原 `limit/offset` 查询状态

### 测试
- `entry/src/main/ets/suites/QuerySuite.ets` 新增分块查询回归用例（正常分批、非法批大小、回调异常恢复）

## [2.4.31] - 2026-02-09

### 重构（Phase 4 收口）
- `Repository` 拆分重构完成：事务、批量、CRUD、删除、关联职责已分别收口到 `TransactionManager`、`BatchOperations`、`CrudOperations`、`DeleteOperations`、`RelationManager`
- 本轮为内部实现重构，**无 API Breaking Change**
- Repository 模块导出统一通过 `repository/index.ets` 聚合，对外调用继续走包入口 `Index.ets`（`import { ... } from 'ocorm'`）

## [2.4.30] - 2026-02-08

### Bug 修复
- 修复 `TypeConverter.fromDbValue()` 仅支持严格抛错的问题，新增宽松模式可返回兜底值
- 修复 `EntityValidator` 对 `undefined` 空值处理不一致的问题，并收紧邮箱校验（拒绝短 TLD）
- 修复单例初始化并发安全问题（`MetadataStorage`/`DatabaseManager`/`QueryCache` 等）
- 优化 `MigrationManager.getMigrationsByOrder()`，由冒泡排序改为内置排序
- 修复 `MigrationManager` 日志写入与事务边界不清晰问题，统一失败日志路径并在提交后记录成功日志
- 修复 `RelationLoader` IN 条件上限硬编码问题，支持运行时配置
- 补充 `CascadeHandler.resetInstance()`，提升测试隔离性
- 修复 `QueryCache` 统计计数在接近 `MAX_SAFE_INTEGER` 时停滞的问题，改为可缩放并持续增长
- 错误链路增加统一脱敏（路径/长数字/字面量）以降低敏感信息泄露风险

### 改进
- `DatabaseConfig` 新增查询超时、并发查询上限、关联 IN 上限配置
- `QueryBuilder` 新增 `timeout()`；`QueryExecutor` 支持查询超时与并发槽位控制
- `DatabaseManager` 支持运行时应用日志级别、查询超时和并发查询限制
- 正式导出查询作用域注册能力：`ScopeRegistry`、`registerScope(s)`、`registerEntityScope(s)`
- 开发者文档补充查询作用域注册与 `scope/scopes` 使用说明

### 测试
- `entry/src/main/ets/suites` 新增对应回归用例（Mapping/Validation/Schema/Relation/Query/Database/Error）

## [2.4.20] - 2026-01-30

### 严重 Bug 修复
- **HIGH-01** 修复事务超时后仍可能提交的问题，增加超时状态检测和强制回滚机制
- **HIGH-02** 修复非自增主键插入被无条件剔除的问题，现仅在 `isAutoIncrement` 为 true 时跳过主键列
- **HIGH-03** 修复软删除过滤在 OR 条件下失效的问题，使用 beginWrap/endWrap 确保条件分组正确

### 中等 Bug 修复
- **MED-01** 修复 `getAsync()` 不支持 whereExists 子查询的问题，补齐子查询执行逻辑
- **MED-02** 修复子查询过滤"污染"原 QueryBuilder 的问题，使用克隆副本避免条件累积
- **MED-03** 修复关联加载未应用软删除过滤的问题，RelationLoader 现复用软删除过滤逻辑
- **MED-04** 修复 COUNT 语句未转义表/列名的问题，统一使用转义处理
- **MED-05** 修复同名数据库再次初始化不刷新配置的问题，支持配置变更检测
- **MED-06** 修复健康检查依赖 `_orm_version` 表的问题，改用 sqlite_master 通用查询
- **MED-07** 修复 TypeConverter 对 Date/Object 写入支持不完整的问题，增加 Date 转时间戳和 Object 序列化
- **MED-08** 修复子查询 IN 列表缺少分批处理的问题，参照 RelationLoader 分批策略

### 低级 Bug 修复
- **LOW-01** 修复 `QueryBuilder.reset()` 未清理 `lazyRelationNames` 的问题
- **LOW-02** 修复 `whereIn` 空数组未处理的问题，空数组时短路返回空结果

### 文档
- 完善 README.md，新增 12 个功能示例
- 使用分类表格展示全部 25 篇开发者指南文档
- 修正目录索引中批量操作和事务处理的说明

### 测试
- 新增事务超时/重试场景测试
- 新增非自增主键插入测试
- 新增软删除 OR 条件测试
- 新增子查询相关测试
- 新增 TypeConverter Date/Object 转换测试

## [2.4.14] - 2026-01-28

### 修复
- 修复示例代码 ArkTS 规范问题（对象字面量改为类实现）
- 修复 UsageExamplePage 输入框样式问题
- 更新 README 文档链接为 GitHub 完整地址

## [2.4.12] - 2026-01-27

### 新增
- 完善的开发者文档 (developer-guide)
- 开源项目配套文档 (CONTRIBUTING, CODE_OF_CONDUCT, SECURITY)
- GitHub Issue/PR 模板

### 改进
- 文档结构优化

---

## [2.1.19] - 2025-01-24

### 新增
- 初始版本发布
- 轻量级 SQLite ORM 框架核心功能
- Data Mapper 模式实现
- Repository 模式实现
- 链式 QueryBuilder API
- 完整 CRUD 操作支持
- 自动建表与 Schema 管理
-  ArkTS 与 SQLite 类型自动转换
- 关联查询支持 (OneToMany/ManyToOne/ManyToMany)
- 生命周期钩子 (beforeSave/afterLoad/beforeDelete)
- 软删除支持
- SQL 日志与性能监控
- EntityData.from() 简化 API
- 分页查询功能
- 批量插入功能
- TaskPool 异步数据转换
- ViewModel 双向映射
- 子查询支持
- 查询缓存 (TTL, 统计)
- 高级事务 (超时/重试/隔离级别)
- 并行关联加载

### 修复
- 初始版本，无修复记录

### 优化
- 初始版本，无优化记录

