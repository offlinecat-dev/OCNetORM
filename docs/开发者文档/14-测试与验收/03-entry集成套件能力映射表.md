# 03-entry集成套件能力映射表

> 状态：已完成
> 适用范围：`entry/src/main/ets/suites/*`
> 最后更新：2026-03-28

## 1. 目标
- 说明 entry 模块集成套件当前覆盖了哪些能力。
- 区分“Suite 已注册”和“Hypium 入口已挂载”。
- 给新增回归用例时提供落点参考。

## 2. 当前 Suite 注册面
`entry/src/main/ets/suites/index.ets` 当前注册了核心套件、Phase 8 性能/边界套件，以及 Phase 9 Entry 同步套件。

```arkts
// Phase 9 Entry 同步套件
suites.push(new EntryBatchInsertTransactionRegressionSuite())
suites.push(new EntryConnectionPoolSuite())
suites.push(new EntryOrmConcurrencyFixSuite())
suites.push(new EntryOrmCoreFixSuite())
suites.push(new EntryOrmCriticalFixSuite())
suites.push(new EntryOrmObservabilityFixSuite())
suites.push(new EntryOrmPerformanceBatchSuite())
suites.push(new EntryOrmReviewFixSuite())
suites.push(new EntryOrmReviewReport19FixSuite())
suites.push(new EntryOrmReviewReport20FixSuite())
suites.push(new EntryOrmSecurityFixSuite())
suites.push(new EntryOrmSubQueryFixSuite())
suites.push(new EntryOrmToolsSuite())
suites.push(new EntryRelationTimeoutSuite())
suites.push(new EntrySuiteProfileSuite())
suites.push(new EntryLocalUnitSuite())
suites.push(new EntryListSuite())
```

## 3. 能力映射

| Suite | 主要能力 |
| --- | --- |
| `EntryBatchInsertTransactionRegressionSuite` | 批量插入事务回归、事务边界与嵌套防护 |
| `EntryConnectionPoolSuite` | 连接池、事务绑定、未绑定写入保护 |
| `EntryOrmConcurrencyFixSuite` | 并发复用、事务活跃状态、查询执行器并发限制 |
| `EntryOrmCoreFixSuite` | 事务超时、查询超时、基础保存语义 |
| `EntryOrmCriticalFixSuite` | savepoint、回滚、关系写入关键路径 |
| `EntryOrmObservabilityFixSuite` | 慢查询、日志级别、关系加载观测 |
| `EntryOrmPerformanceBatchSuite` | 关系分批、批量写入、唯一校验查询次数 |
| `EntryOrmReviewFixSuite` | 只读事务、隔离级别、迁移失败汇总 |
| `EntryOrmReviewReport19FixSuite` | 事务守卫、跨仓库嵌套与未绑定写入 |
| `EntryOrmReviewReport20FixSuite` | `getRaw`、`rawQuery`、实体查询拒绝聚合语义 |
| `EntryOrmSecurityFixSuite` | 事务并发调用、超时前重叠拦截 |
| `EntryOrmSubQueryFixSuite` | 子查询、软删除返回值语义 |
| `EntryOrmToolsSuite` | 工具函数与辅助能力回归 |
| `EntryRelationTimeoutSuite` | 关系加载 timeout 行为 |
| `EntrySuiteProfileSuite` | 套件档位与过滤策略校验（`default/ci/ci-performance`） |
| `EntryLocalUnitSuite` | entry 本地单测封装与基础能力回归 |
| `EntryListSuite` | 套件列表聚合与入口完整性校验 |

## 4. 正确示例
如果新增的是“连接池 + 事务守卫”相关回归，应优先放到 `EntryConnectionPoolSuite` 或 `EntryOrmReviewReport19FixSuite`，而不是新开一个散乱 suite。

```text
落点判断:
连接池/lease/guard -> EntryConnectionPoolSuite / EntryOrmReviewReport19FixSuite
rawQuery/getRaw      -> EntryOrmReviewReport20FixSuite
timeout/cleanup      -> EntryOrmCoreFixSuite / EntryOrmSecurityFixSuite
批量/性能           -> EntryOrmPerformanceBatchSuite
```

Hypium 入口若要跑到这些 suite 对应主题，还要检查 `entry/src/test/*.test.ets` 和 `entry/src/test/List.test.ets` 的挂载情况。

```bash
rg -n "EntryOrm|EntryConnectionPool|EntryRelationTimeout" entry/src/main/ets/suites entry/src/test
```

## 5. 误用示例
不要因为一个用例跨了“事务+查询”，就随手放到任何一个 suite 里。entry suite 现在已经按问题域分层，乱放会让回归口径失真。

```text
错误做法:
把 rawQuery 参数化回归放进 EntryConnectionPoolSuite
把连接池事务绑定回归放进 EntryOrmReviewReport20FixSuite
```

## 6. 参考路径
- `entry/src/main/ets/suites/index.ets`
- `entry/src/main/ets/suites/*.ets`
- `entry/src/test/*.test.ets`

## 7. 变更记录
- 2026-03-28：补全 entry 集成套件能力映射表
