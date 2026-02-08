# CHANGELOG

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

