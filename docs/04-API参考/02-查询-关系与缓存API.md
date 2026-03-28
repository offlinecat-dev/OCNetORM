# 02-查询-关系与缓存API

> 状态：已完成
> 适用版本：ocorm 3.0.2
> 最后更新：2026-03-28

## 1. 覆盖范围

这页覆盖查询主链路：

- `QueryBuilder`：负责描述查询
- `QueryExecutor`：负责执行查询、聚合、分页、更新、删除
- `RelationLoader`：负责关系加载与并行关系加载
- `QueryCache`：负责实体级查询缓存

深度实现文档看：

- [`../02-使用手册/03-查询/00-查询体系总览.md`](../02-使用手册/03-查询/00-查询体系总览.md)
- [`../02-使用手册/03-查询/07-RelationLoader与关系加载策略.md`](../02-使用手册/03-查询/07-RelationLoader与关系加载策略.md)
- [`../02-使用手册/10-性能调优/03-缓存参数调优.md`](../02-使用手册/10-性能调优/03-缓存参数调优.md)

## 2. API 快表

| 类/能力 | 代表方法 | 说明 |
| --- | --- | --- |
| `QueryBuilder` | `where()`、`orWhere()`、`whereIn()`、`whereBetween()`、`whereLike()` | 条件链式构造 |
| `QueryBuilder` | `select()`、`selectRaw()`、`groupBy()`、`having()` | 列选择、聚合、分组 |
| `QueryBuilder` | `with()`、`withLazy()`、`withWhere()`、`withCount()` | 关系加载描述 |
| `QueryBuilder` | `paginate()`、`forPage()`、`orderBy()`、`timeout()` | 分页、排序、超时 |
| `QueryBuilder` | `scope()`、`scopes()`、`whereExists()` | 作用域与子查询 |
| `QueryExecutor` | `get()`、`getOne()`、`getPaginated()`、`getRaw()` | 实体/原始行结果 |
| `QueryExecutor` | `count()`、`sum()`、`avg()`、`max()`、`min()`、`aggregate()` | 聚合 |
| `QueryExecutor` | `update()`、`delete()`、`chunk()`、`explain()` | 写操作、分块遍历、执行计划 |
| `RelationLoader` | `loadRelation()`、`loadRelationsParallel()` | 直接关系加载器 |
| `QueryCache` | `configure()`、`get()`、`set()`、`invalidate()`、`clear()` | 缓存配置与失效 |

## 3. `QueryBuilder` 链式构造

```ts
import { QueryBuilder, ConditionOperator } from 'ocorm'

const qb = new QueryBuilder('User')
  .select(['id', 'user_name'])
  .where('age', ConditionOperator.GREATER_EQUAL, 18)
  .orWhere('vip_level', ConditionOperator.GREATER_EQUAL, 3)
  .whereIn('status', ['active', 'trial'])
  .with('posts')
  .withCount('posts', 'postCount')
  .orderBy('created_at', 'DESC')
  .paginate(1, 20)
  .timeout(1200)

console.info(qb.toSQL())
console.info(JSON.stringify(qb.getSelectedColumns()))
```

几个高频判断：

- 需要复用过滤片段时，用 `scope()` / `scopes()`，不要复制粘贴一堆 `where()`
- 需要聚合表达式时，用 `selectRaw()` + `groupBy()` / `having()`
- 需要实体结果时，最终走 `get()` / `getOne()`；需要原始行时，最终走 `getRaw()`

## 4. `QueryExecutor` 执行速查

```ts
import { QueryBuilder, QueryExecutor } from 'ocorm'

const qb = new QueryBuilder('User')
  .whereLike('user_name', 'A%')
  .forPage(2, 10)

const executor = new QueryExecutor(qb)
const rows = await executor.get()
const one = await executor.getOne()
const page = await executor.getPaginated()
const total = await executor.count()
const raw = await executor.getRaw()
```

实体模式和原生模式边界：

- `get()` / `getOne()`：返回映射后的 `EntityData`
- `getRaw()`：返回 `ResultSetRow[]`，用于自定义读取或调试
- `aggregate()`：一次性拿多聚合值，单列聚合则优先 `sum()` / `avg()` / `max()` / `min()`

```ts
import { BatchUpdateValues, QueryBuilder, QueryExecutor } from 'ocorm'

const updates = BatchUpdateValues.create()
  .set('status', 'archived')
  .set('archived_at', Date.now())

const affectedRows = await new QueryExecutor(
  new QueryBuilder('Post').whereIn('id', [7, 9, 11])
).update(updates)

console.info(`affectedRows=${affectedRows}`)
```

## 5. 子查询、作用域、关系约束

```ts
import { QueryBuilder, ConditionOperator } from 'ocorm'

const qb = new QueryBuilder('User')
  .scope('active')
  .whereExists('posts', (postQb) => {
    postQb.where('status', ConditionOperator.EQUAL, 'published')
  })
  .withWhere('posts', (postQb) => {
    postQb.where('status', ConditionOperator.EQUAL, 'published')
  })
```

这三个能力的区别不要混：

- `scope()`：复用当前实体的命名查询片段
- `whereExists()`：做存在性过滤
- `withWhere()`：限制要加载的关联数据，不直接改变主查询的存在性判断

深入说明看：

- [`../02-使用手册/03-查询/03-子查询-whereExists-SubQuery.md`](../02-使用手册/03-查询/03-子查询-whereExists-SubQuery.md)
- [`../02-使用手册/03-查询/08-with-withLazy-withWhere-withCount.md`](../02-使用手册/03-查询/08-with-withLazy-withWhere-withCount.md)

## 6. `RelationLoader` 与并发限制

`RelationLoader` 是底层关系加载器。业务代码通常通过 `with()` / `withCount()` 间接触发；只有扩展查询框架或做专项测试时，才建议直接 new。

```ts
import { DatabaseManager, RelationLoader } from 'ocorm'

const loader = new RelationLoader('User', () => DatabaseManager.getInstance().getStore())

const relationResult = await loader.loadRelation(users, 'posts')
const parallelResult = await loader.loadRelationsParallel(users, ['posts', 'roles'])
```

关系加载的吞吐和失败边界还受两组配置控制：

- `DatabaseConfig.setRelationInClauseLimit()`
- `DatabaseConfig.setRelationLoadConcurrency()`

对应深度页：

- [`../02-使用手册/10-性能调优/02-关系加载并发与IN子句限制.md`](../02-使用手册/10-性能调优/02-关系加载并发与IN子句限制.md)

## 7. `QueryCache` 速查

```ts
import { DatabaseManager } from 'ocorm'

const cache = DatabaseManager.getInstance().getQueryCache()
cache.configure({ enabled: true, maxSize: 200, ttlMs: 10_000 })

const cached = cache.get('User', 1)
if (cached === null) {
  cache.set('User', 1, user)
}

cache.invalidate('User', 1)
console.info(JSON.stringify(cache.getStatistics()))
```

缓存边界：

- 这是实体级缓存，不是 SQL 文本级缓存
- 仓储写入、删除、恢复操作会触发失效，手工改库时你要自己负责清理
- `setStatisticsForTest()` 只给测试用，不要带到业务代码

## 8. 查询安全和误用提醒

- `selectRaw()` 只适合你明确知道表达式来源安全时使用
- `getRaw()` 返回原始行，不做实体校验和 hook，不要误当成 `get()` 的廉价替代
- 高并发关系加载先查 `relationLoadConcurrency` 和 `relationInClauseLimit`，再谈“为什么慢”

```ts
import { QueryBuilder } from 'ocorm'

const bad = new QueryBuilder('User')
  .selectRaw([`COUNT(*) AS total, ${userInput} AS unsafe_alias`])

// 错误点：把外部输入直接拼进原始表达式
```

对应约束文档：

- [`../02-使用手册/09-安全与最佳实践/01-SQL注入防护策略.md`](../02-使用手册/09-安全与最佳实践/01-SQL注入防护策略.md)
- [`../02-使用手册/03-查询/11-查询安全守卫-QueryBuilderGuards.md`](../02-使用手册/03-查询/11-查询安全守卫-QueryBuilderGuards.md)

## 9. 继续下钻

- 仓储事务：[`03-仓储-事务与原生SQLAPI.md`](./03-仓储-事务与原生SQLAPI.md)
- 深度章节：[`../02-使用手册/03-查询/00-查询体系总览.md`](../02-使用手册/03-查询/00-查询体系总览.md)、[`../02-使用手册/03-查询/12-常见误用与失败语义.md`](../02-使用手册/03-查询/12-常见误用与失败语义.md)

## 10. 变更记录

- 2026-03-28：补齐查询、关系加载、缓存 API 速查与交叉引用。

