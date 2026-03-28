# 01-核心入口-错误与类型API

> 状态：已完成
> 适用版本：ocorm 3.0.2
> 最后更新：2026-03-28

## 1. 覆盖范围

这一页只覆盖包级最顶层的基础入口：

- 初始化入口：`OCORMInit`
- 核心元数据 / 上下文：`MetadataStorage`、`OrmContext`、`defineEntity`
- 建模装饰器：`Table`、`Column`、`PrimaryKey`、`CreatedAt`、`UpdatedAt`、`SoftDelete`
- 基础类型：`ColumnType`、`ConditionOperator`、`RelationType`、`SortDirection`
- 错误与日志：`OrmError`、各类细分错误、`setErrorLocale()`、`Logger`

更深的建模语义看：

- [`../02-使用手册/02-实体与建模/01-实体模型与元数据.md`](../02-使用手册/02-实体与建模/01-实体模型与元数据.md)
- [`../02-使用手册/02-实体与建模/02-defineEntity与EntitySchema.md`](../02-使用手册/02-实体与建模/02-defineEntity与EntitySchema.md)
- [`../02-使用手册/11-日志与错误处理/01-错误体系分层.md`](../02-使用手册/11-日志与错误处理/01-错误体系分层.md)

## 2. 入口映射表

| 能力 | 代表导出 | 说明 |
| --- | --- | --- |
| 初始化 | `OCORMInit`, `OCORMInitOptions` | 一次性串起 `DatabaseManager.initialize()`、日志配置、自动建表或自动迁移 |
| 核心建模 | `defineEntity`, `EntitySchema`, `ColumnSchema`, `IndexSchema` | 无装饰器场景下的 schema-first 注册入口 |
| 元数据与上下文 | `MetadataStorage`, `EntityMetadata`, `RelationMetadata`, `OrmContext` | 全局元数据、全局事件、全局 hook 注册点 |
| 查询作用域 | `ScopeRegistry`, `registerScope`, `registerEntityScopes` | 复用查询片段，供 `QueryBuilder.scope()` / `scopes()` 调用 |
| 装饰器建模 | `Table`, `Column`, `PrimaryKey`, `CreatedAt`, `UpdatedAt`, `SoftDelete` | 类声明方式建模 |
| 基础类型 | `ColumnType`, `ConditionOperator`, `ValueType`, `RelationType` | 供建模、查询、仓储层共享 |
| 错误与日志 | `OrmError`, `ValidationError`, `DatabaseError`, `Logger`, `setErrorLocale` | 错误分层、日志配置、错误国际化 |

## 3. 典型导入

```ts
import {
  OCORMInit,
  defineEntity,
  EntitySchema,
  ColumnType,
  ConditionOperator,
  Table,
  Column,
  PrimaryKey,
  OrmContext,
  Logger,
  LogLevel,
  setErrorLocale,
  ValidationError
} from 'ocorm'
```

## 4. 统一初始化入口

`OCORMInit()` 适合做应用启动时的“单次初始化编排”。如果你已经确认数据库生命周期要自己接管，再直接用 `DatabaseManager` 和 `SchemaBuilder`。

```ts
import { OCORMInit, DatabaseConfig, LogLevel } from 'ocorm'

const result = await OCORMInit(context, {
  config: new DatabaseConfig('app.db'),
  autoCreateTables: true,
  enableLogger: true,
  logLevel: LogLevel.INFO
})

console.info(`initResult=${result === null ? 'skip' : 'done'}`)
```

想看初始化内部流程与边界：

- [`../20-源码开发指南/02-架构总览/03-运行时生命周期.md`](../20-源码开发指南/02-架构总览/03-运行时生命周期.md)
- [`../20-源码开发指南/04-数据库与连接层/02-DatabaseManager生命周期.md`](../20-源码开发指南/04-数据库与连接层/02-DatabaseManager生命周期.md)

## 5. `defineEntity()` 建模速查

`defineEntity()` 直接接收 `EntitySchema`，适合代码生成、配置驱动注册、测试场景快速建模。

```ts
import { defineEntity, ColumnType } from 'ocorm'

defineEntity('User', {
  tableName: 'users',
  columns: [
    { property: 'id', name: 'id', primaryKey: true, autoIncrement: true },
    { property: 'userName', name: 'user_name', type: ColumnType.TEXT, length: 64 },
    { property: 'age', name: 'age', type: ColumnType.INTEGER, nullable: true }
  ],
  softDelete: true,
  indexes: [
    { columns: ['userName'], unique: true }
  ]
})
```

这一路径的完整规则和失败语义，回到：

- [`../02-使用手册/02-实体与建模/02-defineEntity与EntitySchema.md`](../02-使用手册/02-实体与建模/02-defineEntity与EntitySchema.md)
- [`../02-使用手册/07-Schema与迁移/07-Unique索引映射规则.md`](../02-使用手册/07-Schema与迁移/07-Unique索引映射规则.md)

## 6. 装饰器建模速查

类声明方式更适合业务实体长期维护。装饰器和 `defineEntity()` 最终都汇入统一元数据存储，不要双重注册同一实体。

```ts
import {
  Table,
  Column,
  PrimaryKey,
  CreatedAt,
  UpdatedAt,
  SoftDelete,
  ColumnType
} from 'ocorm'

@Table('users')
export class User {
  @PrimaryKey('id')
  id: number = 0

  @Column({ name: 'user_name', type: ColumnType.TEXT, unique: true })
  userName: string = ''

  @CreatedAt('created_at')
  createdAt: number = 0

  @UpdatedAt('updated_at')
  updatedAt: number = 0

  @SoftDelete('deleted_at')
  deletedAt: number | null = null
}
```

装饰器参数、类型推断和约束说明看：

- [`../02-使用手册/02-实体与建模/03-装饰器建模方式.md`](../02-使用手册/02-实体与建模/03-装饰器建模方式.md)
- [`../02-使用手册/06-验证与钩子/02-ValidationDecorators规则集.md`](../02-使用手册/06-验证与钩子/02-ValidationDecorators规则集.md)

## 7. `OrmContext`、`Logger`、错误国际化

`OrmContext` 是全局事件与 hook 协调点；`Logger` 负责 SQL、事务、批量写入等日志；错误国际化由 `setErrorLocale()` / `registerErrorLocaleMessages()` 控制。

```ts
import {
  OrmContext,
  Logger,
  LogLevel,
  setErrorLocale,
  registerErrorLocaleMessages
} from 'ocorm'

Logger.getInstance().configure(true, LogLevel.DEBUG)
setErrorLocale('en')
registerErrorLocaleMessages('en', {
  ORM999: 'Custom error for {entityName}'
}, true)

OrmContext.on('slow-query', async (event) => {
  Logger.getInstance().logWarn(`slow-query: ${JSON.stringify(event)}`)
})
```

错误分层建议：

- 参数或语义违规优先抛 `ValidationError`、`QueryError`、`TransactionError`
- 数据库底层执行失败统一落 `DatabaseError` / `ExecutionError`
- 不要在业务层吞掉 `OrmError` 后重新包成无上下文的 `Error`

## 8. 基础类型速记

| 类型 | 典型值 |
| --- | --- |
| `ColumnType` | `TEXT`, `INTEGER`, `REAL`, `BLOB` |
| `ConditionOperator` | `EQUAL`, `NOT_EQUAL`, `GREATER`, `LESS`, `LIKE`, `IN`, `BETWEEN`, `IS_NULL` |
| `RelationType` | 关系元数据层使用，供一对一、一对多、多对多、多态关系声明 |
| `ValueType` | 仓储、查询、映射层共享的值类型 |
| `SortDirection` | 排序方向，供 `orderBy()` 使用 |

```ts
import { ConditionOperator, QueryBuilder } from 'ocorm'

const qb = new QueryBuilder('User')
  .where('age', ConditionOperator.GREATER_EQUAL, 18)
  .whereLike('user_name', 'A%')
```

## 9. 深入阅读

- 建模：[`../02-使用手册/02-实体与建模/01-实体模型与元数据.md`](../02-使用手册/02-实体与建模/01-实体模型与元数据.md)、[`../02-使用手册/02-实体与建模/03-装饰器建模方式.md`](../02-使用手册/02-实体与建模/03-装饰器建模方式.md)
- 错误与日志：[`../02-使用手册/11-日志与错误处理/01-错误体系分层.md`](../02-使用手册/11-日志与错误处理/01-错误体系分层.md)、[`../02-使用手册/11-日志与错误处理/05-日志级别与慢查询事件.md`](../02-使用手册/11-日志与错误处理/05-日志级别与慢查询事件.md)
- API 继续下钻：[`02-查询-关系与缓存API.md`](./02-查询-关系与缓存API.md)、[`03-仓储-事务与原生SQLAPI.md`](./03-仓储-事务与原生SQLAPI.md)

## 10. 变更记录

- 2026-03-28：补齐核心入口、建模、错误与基础类型速查。

