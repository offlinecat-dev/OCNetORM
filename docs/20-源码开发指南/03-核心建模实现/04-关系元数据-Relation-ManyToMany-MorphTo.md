# 关系元数据（Relation / ManyToMany / MorphTo）

## 1. 三种关系元数据模型

### 1.1 RelationMetadata（基础关系）
构造签名：
```ts
new RelationMetadata(type, sourceEntity, targetEntity, propertyName, inverseKey, foreignKeySide?, cascade?)
```
用于：`ONE_TO_ONE / ONE_TO_MANY / MANY_TO_ONE`。

关键字段：
- `sourceEntity`：源实体
- `targetEntity`：目标实体
- `propertyName`：关系属性名（查询路径 token）
- `inverseKey`：外键字段语义（由加载策略解释）
- `foreignKeySide`：仅 ONE_TO_ONE 语义相关（`source` 或 `target`）
- `cascade`：`boolean | { insert/update/remove }`

### 1.2 ManyToManyMetadata
构造签名：
```ts
new ManyToManyMetadata(sourceEntity, targetEntity, propertyName, joinTable, joinSourceKey, joinTargetKey)
```
扩展字段：
- `joinTable`
- `joinSourceKey`
- `joinTargetKey`

### 1.3 MorphToMetadata
构造签名：
```ts
new MorphToMetadata(sourceEntity, propertyName, idColumn, typeColumn, typeMap?)
```
扩展字段：
- `idColumn`
- `typeColumn`
- `typeMap`

方法：
- `resolveTargetEntity(typeValue)`：优先查 `typeMap[typeValue]`，否则直接返回 `typeValue`。

## 2. 注册入口（真实 API）
在 `MetadataStorage`：
- `registerRelation(sourceEntity, relation)`
- `registerManyToMany(sourceEntity, targetEntity, propertyName, joinTable, joinSourceKey, joinTargetKey)`
- `registerMorphTo(sourceEntity, propertyName, idColumn, typeColumn, typeMap?)`

可通过 `defineEntity(..., { morphTo })` 间接注册 MorphTo。

## 3. 可运行示例（含三种关系）
```ts
import {
  MetadataStorage,
  RelationMetadata,
  RelationType
} from 'ocorm'

const storage = MetadataStorage.getInstance()

storage.registerEntity('User', 'users')
storage.registerEntity('Post', 'posts')
storage.registerEntity('Tag', 'tags')
storage.registerEntity('Comment', 'comments')

storage.registerRelation(
  'User',
  new RelationMetadata(RelationType.ONE_TO_MANY, 'User', 'Post', 'posts', 'user_id')
)

storage.registerManyToMany('User', 'Tag', 'tags', 'user_tags', 'user_id', 'tag_id')

storage.registerMorphTo('Comment', 'commentable', 'commentableId', 'commentableType', {
  post: 'Post',
  user: 'User'
})
```

## 4. 关系路径规则（QueryBuilder 消费层）
关系路径相关实现位于 `QueryBuilderRelationStrategySupport`。

### 4.1 `with('a.b.c')`
- 会 `trim()` 后按 `.` 分段。
- 空段（如 `a..b`、`.a`、`a.`）直接抛 `RelationNotFoundError`。
- 非 morph 路径会逐段校验每段关系是否存在。

### 4.2 `withLazy(...)`
- 只按“当前实体 + 单段关系名”查 `getRelation(entityName, relationName)`。
- 即：`withLazy('posts')` 可用，`withLazy('posts.comments')` 在当前实现下会失败。

### 4.3 `withCount(relationPath, alias?)`
- 默认别名：`<relationPath 把 . 替换为 _> + _count`。
- 别名必须匹配：`^[A-Za-z_][A-Za-z0-9_]*$`，否则抛 `InvalidConditionError`。

### 4.4 MorphTo 路径边界
- 路径解析遇到 morphTo（`targetEntity === ''`）会直接返回空目标实体。
- 这意味着 `with('commentable.profile')` 可被注册，但后续语义依赖 RelationLoader/运行时目标实体。

## 5. 命名规则与实践建议
- `propertyName` 直接决定查询 API 的关系名（`with('propertyName')`），建议语义稳定、避免频繁改名。
- 多对多中间表字段建议显式蛇形命名（如 `user_id/tag_id`），避免后续 SQL 构建歧义。
- `withCount` 别名建议手动传入业务名，避免默认别名和已有字段冲突。

## 6. 注册时机与失败语义
- `registerRelation/registerManyToMany` 之前，源实体和（非空）目标实体必须已注册。
- `registerMorphTo` 只强校验源实体已注册；目标实体由 `typeMap`/运行时 `typeValue` 决定。
- 关系注册不自动去重；重复注册同 `propertyName` 会形成多条记录，`getRelation` 只返回第一条命中。

## 7. 从关系建模到查询（实战链路）
```ts
import {
  defineEntity,
  ColumnType,
  MetadataStorage,
  RelationMetadata,
  RelationType,
  Repository,
  QueryExecutor
} from 'ocorm'

defineEntity('User', {
  tableName: 'users',
  columns: [{ property: 'id', primaryKey: true }, { property: 'name', type: ColumnType.TEXT }]
})
defineEntity('Post', {
  tableName: 'posts',
  columns: [
    { property: 'id', primaryKey: true },
    { property: 'userId', name: 'user_id', type: ColumnType.INTEGER },
    { property: 'title', type: ColumnType.TEXT }
  ]
})

MetadataStorage.getInstance().registerRelation(
  'User',
  new RelationMetadata(RelationType.ONE_TO_MANY, 'User', 'Post', 'posts', 'user_id')
)

const qb = new Repository('User').createQueryBuilder().with('posts')
const users = await new QueryExecutor(qb).get()
```

## 8. 错误建模示例 + 运行期后果
```ts
import { MetadataStorage } from 'ocorm'

const storage = MetadataStorage.getInstance()
storage.registerEntity('User', 'users')

// 目标实体 Tag 未注册
storage.registerManyToMany('User', 'Tag', 'tags', 'user_tags', 'user_id', 'tag_id')

// 运行时后果：registerRelation 链路校验目标实体失败，抛 EntityNotRegisteredError
```

## 9. 源码定位
- `src/main/ets/core/RelationMetadata.ets:31`
- `src/main/ets/core/RelationMetadata.ets:61`
- `src/main/ets/core/ManyToManyMetadata.ets:13`
- `src/main/ets/core/ManyToManyMetadata.ets:30`
- `src/main/ets/core/MorphToMetadata.ets:9`
- `src/main/ets/core/MorphToMetadata.ets:30`
- `src/main/ets/core/MetadataStorage.ets:151`
- `src/main/ets/core/MetadataStorage.ets:243`
- `src/main/ets/core/MetadataStorage.ets:264`
- `src/main/ets/query/QueryBuilderRelationStrategySupport.ets:28`
- `src/main/ets/query/QueryBuilderRelationStrategySupport.ets:73`
- `src/main/ets/query/QueryBuilderRelationStrategySupport.ets:85`
- `src/main/ets/query/QueryBuilderRelationStrategySupport.ets:89`
- `src/test/Stage5Query/QueryBuilder.test.ets:244`
- `src/test/Stage5Query/QueryBuilder.test.ets:269`
