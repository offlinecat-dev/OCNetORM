# 03-Breaking-Changes

> 状态：已完成
> 适用范围：`2.x -> 3.0.2` 与 `3.0.1 -> 3.0.2`
> 最后更新：2026-03-28

## 1. 已确认的 breaking changes

### 1.1 `rawQuery` 默认强参数化（3.0.2）

- 触发条件：无 `?` 占位符，或参数数量与占位符数量不一致
- 典型报错关键词：`RAW_QUERY 仅允许参数化 SQL`、`RAW_QUERY 参数数量与占位符数量不一致`
- 源码：`src/main/ets/repository/Repository.ets`、`rawsql/RawSqlGuards.ets`

### 1.2 实体查询拒绝 `selectRaw/groupBy/having`（3.0.1 起）

- 触发条件：`get/getOne/getPaginated/count` 路径带聚合 DSL
- 典型报错：`实体查询不支持 selectRaw/groupBy/having，请使用 getRaw() 或 aggregate()`
- 源码：`src/main/ets/query/QueryExecutor.ets`

### 1.3 事务隔离级别收紧（3.0）

- `TransactionOptions.serializable()` 在创建阶段直接抛错
- `REPEATABLE_READ/SERIALIZABLE` 在执行阶段被拒绝
- 源码：`src/main/ets/repository/TransactionOptions.ets`、`TransactionManager.ets`

### 1.4 只读事务不再静默降级（3.0）

- 触发条件：平台不支持 `PRAGMA query_only`
- 结果：事务直接失败（fail-fast）
- 源码：`src/main/ets/repository/TransactionManager.ets`

### 1.5 默认加密值变化（3.0）

- `DatabaseConfig.encrypt` 默认值为 `true`
- 旧代码若依赖默认值，迁移后行为可能偏移
- 源码：`src/main/ets/database/DatabaseConfig.ets`

## 2. 升级前批量审计命令

```bash
rg -n "rawQuery\(|rawQuerySafe\(|rawExecute\(|selectRaw\(|groupBy\(|having\(|TransactionOptions\.serializable\(|REPEATABLE_READ|SERIALIZABLE|new DatabaseConfig\(" src test
```

## 3. 升级后最小验收

```bash
ohpm i @offlinecat/ocorm
hvigor test
```

建议新增一组纯库回归：

1. `rawQuery` 参数化用例（通过 + 失败各 1 条）
2. `getRaw()/aggregate()` 聚合用例
3. `transactionWithOptions` 的 `READ_COMMITTED/READ_UNCOMMITTED/readOnly` 用例

## 4. 源码对齐路径

- `CHANGELOG.md`
- `src/main/ets/database/DatabaseConfig.ets`
- `src/main/ets/repository/TransactionOptions.ets`
- `src/main/ets/repository/TransactionManager.ets`
- `src/main/ets/repository/Repository.ets`
- `src/main/ets/repository/rawsql/RawSqlGuards.ets`
- `src/main/ets/query/QueryExecutor.ets`

