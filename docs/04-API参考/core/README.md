# Core API 契约

实现依据：`src/main/ets/core/*.ets`

## `OCORMInit(context, options)`

- 用途：统一初始化数据库、日志、关系加载参数，并触发自动建表或自动迁移。
- 参数：
  - `context: Context`
  - `options: OCORMInitOptions`
  - `options.config: DatabaseConfig`（必填）
  - `options.autoMigrate?: boolean`（为 `true` 时优先自动迁移）
  - `options.autoCreateTables?: boolean`（默认 `true`）
- 返回：
  - `Promise<CreateAllTablesResult | SchemaMigrationExecutionResult | null>`
  - `autoMigrate=true` 返回迁移结果
  - `autoCreateTables=false` 且未迁移时返回 `null`
- 异常：
  - 可能透传初始化异常（如数据库连接失败）
  - 若使用自定义 manager，异常行为取决于自定义实现
- 副作用：
  - 调用 `DatabaseManager.initialize()`
  - 配置 `Logger`
  - 调用 `RelationLoader.setInClauseLimit(options.config.relationInClauseLimit)`
- 事务上下文：函数本身不显式开启事务；迁移/建表由下游模块决定是否启用事务。
- 最小示例：

```ts
import { OCORMInit, DatabaseConfig } from 'ocorm'

const result = await OCORMInit(context, {
  config: new DatabaseConfig('app.db'),
  autoCreateTables: true
})
```

## `defineEntity(entityName, schema)`

- 用途：Schema-first 快速注册实体、列、软删除、多态关系、索引、作用域。
- 参数：
  - `entityName: string`
  - `schema: EntitySchema`
  - `schema.columns: ColumnSchema[]`（必填）
- 返回：`EntityMetadata`
- 异常：
  - 列注册失败、索引列未注册、`morphTo` 配置非法时抛出 `Error`
  - 实体重复注册等由底层元数据注册逻辑抛错
- 副作用：
  - 写入 `MetadataStorage`
  - `schema.scopes` 存在时写入 `ScopeRegistry`
- 事务上下文：无数据库事务，仅内存元数据变更。
- 最小示例：

```ts
import { defineEntity, ColumnType } from 'ocorm'

defineEntity('User', {
  tableName: 'users',
  columns: [
    { property: 'id', name: 'id', primaryKey: true, autoIncrement: true },
    { property: 'name', name: 'name', type: ColumnType.TEXT, length: 64 }
  ],
  softDelete: true,
  indexes: [{ columns: ['name'], unique: true }]
})
```

## `ScopeRegistry` / `registerScope(s)`

- 用途：注册并复用查询作用域，供 `QueryBuilder.scope()/scopes()` 使用。
- 参数：
  - `registerScope(entityName, scopeName, scopeFunction)`
  - `registerScopes(entityName, Record<string, ScopeFunction>)`
- 返回：`void`
- 异常：无显式抛错；不存在作用域时，`QueryBuilder.scope()` 抛 `ScopeNotFoundError`。
- 副作用：写入全局单例 `ScopeRegistry`。
- 事务上下文：无。
- 最小示例：

```ts
import { registerScope, ConditionOperator } from 'ocorm'

registerScope('User', 'active', (qb) =>
  qb.where('status', ConditionOperator.EQUAL, 'active')
)
```

## `OrmContext` 事件与慢查询阈值

- 用途：注册全局事件监听器、发射慢查询事件、配置监听器错误模式。
- 参数：
  - `OrmContext.on(eventName, listener)`
  - `OrmContext.setSlowQueryThresholdMs(ms)`
  - `OrmContext.setEventListenerErrorMode('log' | 'throw')`
- 返回：`void`
- 异常：
  - 默认 `log` 模式下监听器异常仅记录日志
  - `throw` 模式下监听器异常会向上传播
- 副作用：修改全局静态事件监听器和阈值配置。
- 事务上下文：无，事件系统不绑定事务。
- 最小示例：

```ts
import { OrmContext } from 'ocorm'

OrmContext.setSlowQueryThresholdMs(500)
OrmContext.on('query:slow', (event) => {
  console.info(`${event.operation} ${event.duration}ms ${event.sql}`)
})
```
