# ScopeRegistry 与作用域

## 1. 作用域是什么
作用域是可复用查询片段，类型定义为：
```ts
type ScopeFunction = (qb: QueryBuilder) => QueryBuilder
```

它的目标是把稳定筛选逻辑（如 `active/adult/tenant`）从业务代码里抽离，避免每个查询都手写重复条件。

## 2. ScopeRegistry 真实 API
对应源码：`src/main/ets/core/ScopeRegistry.ets`

单例：`ScopeRegistry.getInstance()`

关键方法：
- `registerScope(entityName, scopeName, scopeFunction)`
- `registerScopes(entityName, scopes)`
- `getScope(entityName, scopeName)`
- `hasScope(entityName, scopeName)`
- `getScopeNames(entityName)`
- `removeScope(entityName, scopeName)`
- `removeAllScopes(entityName)`
- `clear()`
- `applyScope(entityName, scopeName, queryBuilder)`

便捷函数：
- `registerEntityScope/registerEntityScopes`
- `registerScope/registerScopes`（别名）

## 3. 与 QueryBuilder 的集成行为
`QueryBuilder.scope(name)` 的语义：
1. 先 `hasScope` 检查
2. 不存在直接抛 `ScopeNotFoundError`
3. 存在则调用 `applyScope`

`QueryBuilder.scopes([...])` 只是循环调用 `scope(name)`。

重要差异：
- 直接调用 `ScopeRegistry.applyScope`，若找不到作用域，会返回原始 `QueryBuilder`（不抛错）。
- 通过 `QueryBuilder.scope`，找不到会抛错（更安全）。

## 4. 建模阶段注册（defineEntity.scopes）
`defineEntity` 支持在 schema 中传 `scopes`，内部最终调用 `ScopeRegistry.registerScopes`。
这使“实体定义 + 查询作用域”可以集中在一个声明块内。

## 5. 可运行示例
```ts
import {
  registerScope,
  QueryBuilder,
  QueryExecutor,
  ConditionOperator,
  Repository
} from 'ocorm'

registerScope('User', 'active', (qb: QueryBuilder): QueryBuilder => {
  return qb.where('status', ConditionOperator.EQUAL, 1)
})

registerScope('User', 'adult', (qb: QueryBuilder): QueryBuilder => {
  return qb.where('age', ConditionOperator.GREATER_EQUAL, 18)
})

const repo = new Repository('User')
const qb = repo.createQueryBuilder().scope('active').scope('adult')
const rows = await new QueryExecutor(qb).get()
```

## 6. 边界条件与命名规则
- 同实体下同名 scope 会被后注册覆盖（`Map.set` 语义）。
- 作用域函数应返回 `QueryBuilder`；否则会破坏链式调用。
- 作用域函数操作的是传入的同一个 builder（非克隆）。
- 测试场景建议在 `beforeEach` 调 `ScopeRegistry.resetInstance()` 或 `clear()`。
- 命名建议统一小写语义词（如 `active`, `notDeleted`, `tenantScoped`），避免与业务方法名冲突。

## 7. 回归测试对齐点
- 从模型定义到查询作用域（实战）：
```ts
import {
  defineEntity,
  ColumnType,
  ConditionOperator,
  Repository,
  QueryExecutor
} from 'ocorm'

defineEntity('User', {
  tableName: 'users',
  columns: [
    { property: 'id', primaryKey: true },
    { property: 'status', type: ColumnType.INTEGER, defaultValue: 1 },
    { property: 'age', type: ColumnType.INTEGER }
  ],
  scopes: {
    active: qb => qb.where('status', ConditionOperator.EQUAL, 1),
    adult: qb => qb.where('age', ConditionOperator.GREATER_EQUAL, 18)
  }
})

const qb = new Repository('User').createQueryBuilder().scopes(['active', 'adult'])
const users = await new QueryExecutor(qb).get()
```

- 错误建模示例 + 运行期后果（未注册 scope）：
```ts
import { Repository, QueryExecutor } from 'ocorm'

// 运行时后果：QueryBuilder.scope('tenant') 会抛 ScopeNotFoundError
const qb = new Repository('User').createQueryBuilder().scope('tenant')
const rows = await new QueryExecutor(qb).get()
```

- `entry/src/main/ets/suites/QuerySuite.ets` 已覆盖：
  - 连续 `scope('active').scope('adult')` 正常过滤
  - `scopes(['active','adult'])` 等价行为
  - 未注册作用域抛 `ScopeNotFoundError`

## 8. 源码定位
- `OCORM/src/main/ets/core/ScopeRegistry.ets:24`
- `OCORM/src/main/ets/core/ScopeRegistry.ets:60`
- `OCORM/src/main/ets/core/ScopeRegistry.ets:74`
- `OCORM/src/main/ets/core/ScopeRegistry.ets:88`
- `OCORM/src/main/ets/core/ScopeRegistry.ets:160`
- `OCORM/src/main/ets/core/ScopeRegistry.ets:175`
- `OCORM/src/main/ets/query/QueryBuilder.ets:1135`
- `OCORM/src/main/ets/query/QueryBuilder.ets:1138`
- `OCORM/src/main/ets/core/EntitySchema.ets:173`
- `entry/src/main/ets/suites/QuerySuite.ets:1229`
- `entry/src/main/ets/suites/QuerySuite.ets:1263`
