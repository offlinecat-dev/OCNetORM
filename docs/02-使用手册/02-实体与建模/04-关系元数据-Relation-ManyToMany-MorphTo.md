# 关系元数据（Relation / ManyToMany / MorphTo）

## 何时用
业务实体之间存在一对多、多对多或多态关联时。

## 怎么用
先注册实体和列，再注册关系。关系注册入口是 `MetadataStorage`。

## 关系配置语义（已核对源码）
- `RelationMetadata(..., inverseKey, foreignKeySide?)`
- `inverseKey` 可传属性名或列名
- `foreignKeySide` 仅对 `ONE_TO_ONE` 有效，可选 `source` 或 `target`
- `registerManyToMany(..., joinTable, joinSourceKey, joinTargetKey)` 的 `join*Key` 是中间表列名
- `registerMorphTo(..., idColumn, typeColumn, typeMap?)` 的 `idColumn/typeColumn` 是源实体字段（属性名或列名）

## 最小可运行模板
```ts
import {
  ColumnType,
  MetadataStorage,
  RelationMetadata,
  RelationType,
  defineEntity
} from 'ocorm'

defineEntity('User', {
  tableName: 'users',
  columns: [
    { property: 'id', primaryKey: true, autoIncrement: true },
    { property: 'name', type: ColumnType.TEXT }
  ]
})

defineEntity('Post', {
  tableName: 'posts',
  columns: [
    { property: 'id', primaryKey: true, autoIncrement: true },
    { property: 'userId', name: 'user_id', type: ColumnType.INTEGER },
    { property: 'title', type: ColumnType.TEXT }
  ]
})

const storage = MetadataStorage.getInstance()
storage.registerRelation(
  'User',
  new RelationMetadata(RelationType.ONE_TO_MANY, 'User', 'Post', 'posts', 'userId')
)
storage.registerRelation(
  'Post',
  new RelationMetadata(RelationType.MANY_TO_ONE, 'Post', 'User', 'author', 'userId')
)
storage.registerManyToMany('User', 'Post', 'favoritePosts', 'user_favorites', 'user_id', 'post_id')
```

## 失败示例与修复
失败示例（目标实体未注册就注册关系）：
```ts
const storage = MetadataStorage.getInstance()
storage.registerRelation(
  'User',
  new RelationMetadata(RelationType.ONE_TO_MANY, 'User', 'Post', 'posts', 'userId')
) // EntityNotRegisteredError: Post
```

修复：
1. 先 `defineEntity('User', ...)` 和 `defineEntity('Post', ...)`
2. 再执行 `registerRelation/registerManyToMany/registerMorphTo`
3. 对 `ONE_TO_ONE` 明确写 `foreignKeySide: 'source' | 'target'`
