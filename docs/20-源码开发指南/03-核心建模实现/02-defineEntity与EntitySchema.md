# defineEntity 与 EntitySchema

## 1. API 入口与定位
`defineEntity(entityName: string, schema: EntitySchema): EntityMetadata`

源码：`src/main/ets/core/EntitySchema.ets`

这是“声明式注册实体”的主入口，本质是对 `registerEntity/registerColumn/registerMorphTo/registerScopes` 的一次批处理封装。

## 2. EntitySchema 真实结构
```ts
export interface EntitySchema {
  tableName?: string
  columns: Array<ColumnSchema>
  softDelete?: boolean | SoftDeleteSchema
  morphTo?: MorphToSchema | Array<MorphToSchema>
  indexes?: Array<IndexSchema>
  scopes?: Record<string, ScopeFunction>
}
```

子结构（简化）：
- `ColumnSchema`：`property/name/type/nullable/unique/defaultValue/length/primaryKey/autoIncrement`
- `SoftDeleteSchema`：`propertyName?`（默认 `deletedAt`）、`columnName?`（默认 `deleted_at`）
- `MorphToSchema`：`name/idColumn/typeColumn/typeMap?`
- `IndexSchema`：`name?/columns/unique?`

## 3. defineEntity 实际执行顺序

### 3.1 实体注册
- 未注册时：调用 `registerEntity`。
- 已注册且传了 `tableName`：仅当当前表名还是默认实体名时，允许覆盖为新表名。

### 3.2 列注册
- 逐列处理 `schema.columns`。
- 发现同属性列已存在：`continue`（跳过，不覆盖）。
- `primaryKey = true`：
  - `autoIncrement` 未传默认 `true`
  - 分别走 `registerAutoIncrementPrimaryKey` 或 `registerPrimaryKey`

### 3.3 软删除
- `softDelete` 为真值时才生效。
- 会调用 `metadata.setSoftDelete(true, columnName)`。
- 若软删属性列不存在，会自动补一列：`INTEGER + nullable=true`。

### 3.4 morphTo
- 支持单个或数组。
- `name/idColumn/typeColumn` 为空字符串直接抛错。
- 同名关系已存在时跳过重复注册。

### 3.5 索引
- `columns` 允许传属性名或列名，内部会映射成真实列名。
- 空 token 会被忽略；全部为空后会抛 `index.columns 不能为空`。
- 未注册字段会抛 `索引列未注册: xxx`。
- 未传 `name` 时自动命名：
  - 普通索引：`idx_<table>_<col...>`
  - 唯一索引：`uidx_<table>_<col...>`
  - 非 `[A-Za-z0-9_]` 会被替换为 `_`

### 3.6 scopes
- 若传入 `scopes`，最后阶段调用 `ScopeRegistry.getInstance().registerScopes(entityName, schema.scopes)`。

## 4. 可运行示例（完整）
```ts
import {
  defineEntity,
  ColumnType,
  QueryBuilder,
  ConditionOperator
} from 'ocorm'

defineEntity('User', {
  tableName: 'users',
  columns: [
    { property: 'id', primaryKey: true },
    { property: 'name', type: ColumnType.TEXT, nullable: false },
    { property: 'email', type: ColumnType.TEXT, unique: true },
    { property: 'status', type: ColumnType.INTEGER, defaultValue: 1 }
  ],
  softDelete: { propertyName: 'deletedAt', columnName: 'deleted_at' },
  indexes: [
    { columns: ['email'], unique: true },
    { name: 'idx_users_status', columns: ['status'] }
  ],
  scopes: {
    active: (qb: QueryBuilder) => qb.where('status', ConditionOperator.EQUAL, 1)
  }
})

defineEntity('Comment', {
  tableName: 'comments',
  columns: [
    { property: 'id', primaryKey: true },
    { property: 'commentableId', type: ColumnType.INTEGER },
    { property: 'commentableType', type: ColumnType.TEXT }
  ],
  morphTo: {
    name: 'commentable',
    idColumn: 'commentableId',
    typeColumn: 'commentableType',
    typeMap: { post: 'Post', user: 'User' }
  }
})
```

## 5. 边界与限制（必须知晓）
- `softDelete: false` 在当前实现中不会触发任何动作（`if (schema.softDelete)` 保护分支）。
- `defineEntity` 不是“强制覆盖器”：已有同属性列不会更新，会被跳过。
- 关系与索引都依赖此前列/实体已注册，时序错误会在启动阶段直接抛错。
- 报错信息会经过 `sanitizeErrorMessage` 脱敏后再拼接。

## 6. 从模型定义到查询使用（实战链路）
```ts
import {
  defineEntity,
  EntitySchema,
  ColumnType,
  Repository,
  QueryExecutor,
  ConditionOperator
} from 'ocorm'

const userSchema: EntitySchema = {
  tableName: 'users',
  columns: [
    { property: 'id', primaryKey: true },
    { property: 'name', type: ColumnType.TEXT, nullable: false },
    { property: 'status', type: ColumnType.INTEGER, defaultValue: 1 }
  ],
  scopes: {
    active: qb => qb.where('status', ConditionOperator.EQUAL, 1)
  }
}

defineEntity('User', userSchema)
const qb = new Repository('User').createQueryBuilder().scope('active')
const activeUsers = await new QueryExecutor(qb).get()
```

## 7. 错误建模示例 + 运行期后果
```ts
import { defineEntity, ColumnType } from 'ocorm'

defineEntity('User', {
  columns: [{ property: 'id', primaryKey: true }],
  indexes: [{ name: 'idx_users_unknown', columns: ['notExists'], unique: false }]
})

// 运行时后果：defineEntity 启动注册阶段直接抛错
// Error: 索引列未注册: notExists
```

## 8. 什么时候用 defineEntity，什么时候不用
适合：
- 初始化阶段批量注册
- 配置驱动实体定义
- 需要统一管理 scopes/indexes/morphTo

不适合：
- 运行中动态频繁增改字段（该模式更适合离线定义 + 迁移）

## 9. 源码定位
- `OCORM/src/main/ets/core/EntitySchema.ets:81`
- `OCORM/src/main/ets/core/EntitySchema.ets:102`
- `OCORM/src/main/ets/core/EntitySchema.ets:145`
- `OCORM/src/main/ets/core/EntitySchema.ets:236`
- `OCORM/src/main/ets/core/EntitySchema.ets:266`
- `OCORM/src/main/ets/core/EntitySchema.ets:279`
- `OCORM/src/main/ets/core/EntitySchema.ets:301`
- `OCORM/src/main/ets/core/EntitySchema.ets:319`
- `OCORM/src/test/Stage1Core/LocalUnit.test.ets:166`
- `OCORM/src/test/Stage1Core/LocalUnit.test.ets:196`
