# Query API 契约

实现依据：`src/main/ets/query/*.ets`

## `QueryBuilder`（条件、排序、分页、关系描述）

- 用途：声明式构建查询，不直接执行 SQL。
- 参数：
  - 构造：`new QueryBuilder(entityName)`
  - 条件：`where/andWhere/orWhere/whereIn/whereBetween/whereLike/whereNull`
  - 关系：`with/withLazy/withWhere/withCount`
  - 分页排序：`paginate/forPage/orderBy/limit/offset`
- 返回：链式返回 `QueryBuilder`
- 异常：
  - 实体未注册：`EntityNotRegisteredError`
  - 列不存在或参数非法：`InvalidConditionError`
  - 作用域未注册：`ScopeNotFoundError`
  - 关系未注册：`RelationNotFoundError`
- 副作用：仅修改 builder 内部状态，不触发数据库 IO。
- 事务上下文：无。
- 最小示例：

```ts
import { QueryBuilder, ConditionOperator } from 'ocorm'

const qb = new QueryBuilder('User')
  .where('age', ConditionOperator.GREATER_EQUAL, 18)
  .with('posts')
  .orderBy('created_at', 'DESC')
  .paginate(1, 20)
```

## `QueryBuilder.having()` 与 `selectRaw()`

- 用途：构建聚合/分组查询表达式（与 `getRaw()`/`aggregate()` 配合）。
- 参数：
  - `having(clause: string, args?: ValueType[])`
  - `selectRaw(expressions: string[])`
- 返回：`QueryBuilder`
- 异常：
  - `having` 为空、无参数、占位符数不匹配、含危险 token/关键字：`InvalidConditionError`
  - `selectRaw` 仅允许标识符或 `COUNT/SUM/AVG/MIN/MAX` 形态，非法表达式抛 `InvalidConditionError`
- 副作用：保存 HAVING/RAW 表达式供执行阶段使用。
- 事务上下文：无。
- 最小示例：

```ts
const qb = new QueryBuilder('Order')
  .selectRaw(['user_id', 'SUM(amount) AS total_amount'])
  .groupBy('user_id')
  .having('SUM(amount) > ?', [1000])
```

## `QueryBuilder.timeout(timeoutMs)`

- 用途：设置当前查询超时，覆盖全局 `DatabaseConfig.queryTimeoutMs`。
- 参数：`timeoutMs: number`（`<= 0` 视为禁用）
- 返回：`QueryBuilder`
- 异常：无。
- 副作用：设置 `queryTimeoutMs`，由 `QueryExecutor` 执行时生效。
- 事务上下文：无。
- 最小示例：

```ts
const qb = new QueryBuilder('User').timeout(1200)
```

## `QueryExecutor`（执行器）

- 用途：执行 `QueryBuilder`，返回实体结果、分页结果、原始行、聚合结果。
- 参数：`new QueryExecutor(queryBuilder)`
- 返回：
  - `get/getAsync(): Promise<EntityData[]>`
  - `getOne(): Promise<EntityData | null>`
  - `count(): Promise<number>`
  - `getPaginated(): Promise<PaginatedResult>`
  - `getRaw(): Promise<ResultSetRow[]>`
  - `aggregate(): Promise<AggregateResult>`
- 异常：
  - 统一转为 `ExecutionError`（按 operation 分组：`SELECT/COUNT/RAW_SELECT/...`）
  - 同一实例并发复用会抛错：`同一 QueryExecutor 实例不支持并发复用`
  - 实体模式 `get/getOne/count/getPaginated/getAsync` 不允许 `selectRaw/groupBy/having`
- 副作用：
  - 执行真实数据库查询
  - 触发慢查询事件 `OrmContext.emitSlowQuery(...)`
  - 读取关系时可能追加延迟加载句柄
- 事务上下文：
  - 不主动开启事务
  - 在连接池模式下会自动租约连接并在操作结束释放
- 最小示例：

```ts
import { QueryExecutor } from 'ocorm'

const executor = new QueryExecutor(qb)
const rows = await executor.get()
const total = await executor.count()
```

## `QueryExecutor.update(values)` / `delete()`

- 用途：基于条件批量更新/删除，不加载实体。
- 参数：
  - `update(values: BatchUpdateValues)`
  - `delete()`
- 返回：`Promise<number>`（匹配行数）
- 异常（硬性限制）：
  - 必须至少一个 WHERE 条件
  - 不支持 `whereExists`、`LIMIT/OFFSET`、`ORDER BY`、`GROUP BY/HAVING`、`selectRaw`
  - 更新主键字段会报错
- 副作用：
  - 执行写 SQL
  - 失效实体缓存：`QueryCache.invalidateEntity(entityName)`
- 事务上下文：不自动开事务，依赖外部上下文。
- 最小示例：

```ts
import { BatchUpdateValues, QueryExecutor } from 'ocorm'

const values = BatchUpdateValues.create().set('status', 'archived')
const affected = await new QueryExecutor(qb).update(values)
```

## `RelationLoader`

- 用途：加载 `ONE_TO_ONE/ONE_TO_MANY/MANY_TO_ONE/MANY_TO_MANY/MORPH_TO` 关联。
- 参数：
  - 构造：`new RelationLoader(sourceEntityName, storeProvider?)`
  - `loadRelation(entities, relationName, options?, morphWithWhereCallback?)`
  - `loadRelationsParallel(entities, relationNames)`
- 返回：`Promise<EntityData[]>`
- 异常：
  - 关联未注册：`RelationNotFoundError`
  - 数据库访问失败：`ExecutionError`
- 副作用：向实体写入关联数据。
- 事务上下文：不主动开事务；可通过 `storeProvider` 复用外部连接。
- 最小示例：

```ts
const loader = new RelationLoader('User')
await loader.loadRelationsParallel(users, ['posts', 'roles'])
```

## `QueryCache`

- 用途：实体级一级缓存（键为 namespace + entity + id）。
- 参数：
  - `configure({ enabled, maxSize, ttlMs })`
  - `get/set/invalidate/invalidateEntity/clear`
- 返回：
  - `get` 返回 `EntityData | null`（深拷贝）
  - `getStatistics` 返回命中统计
- 异常：无显式抛错。
- 副作用：
  - 维护内存缓存
  - `set` 达到上限时驱逐最旧条目
- 事务上下文：无。
- 最小示例：

```ts
import { QueryCache } from 'ocorm'

const cache = QueryCache.getInstance()
cache.configure({ enabled: true, maxSize: 200, ttlMs: 10_000 })
```

## 查询超时与并发语义

- 查询超时优先级：`QueryBuilder.timeout(ms)` > `DatabaseConfig.queryTimeoutMs`。
- 查询并发槽：`DatabaseConfig.maxConcurrentQueries > 0` 时启用排队；等待超时会报 `等待查询槽位超时`。
- 关系加载并发：`DatabaseConfig.relationLoadConcurrency`（`<=1` 串行）。
