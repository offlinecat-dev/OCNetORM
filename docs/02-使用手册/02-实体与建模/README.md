# 02-实体与建模

## 何时用
需要定义实体字段、关系和默认过滤规则时。

## 怎么用
优先使用 `defineEntity`；需要类模型时再使用 `Table/Column/PrimaryKey`。关系使用 `MetadataStorage` 注册。

- [01-实体模型与元数据](./01-实体模型与元数据.md)
- [02-defineEntity与EntitySchema](./02-defineEntity与EntitySchema.md)
- [03-装饰器建模方式](./03-装饰器建模方式.md)
- [04-关系元数据](./04-关系元数据-Relation-ManyToMany-MorphTo.md)
- [05-ScopeRegistry与作用域](./05-ScopeRegistry与作用域.md)

## 核心 API 对照（已核对源码）
- 列类型：`ColumnType.TEXT | INTEGER | REAL | BLOB`
- 声明式建模：`defineEntity(entityName, schema)`
- 装饰器建模：`Table`、`Column`、`PrimaryKey`、`CreatedAt`、`UpdatedAt`、`SoftDelete`
- 关系建模：`RelationMetadata`、`ManyToManyMetadata`、`MorphToMetadata`，通过 `MetadataStorage` 注册
- 关系类型：`RelationType.ONE_TO_ONE | ONE_TO_MANY | MANY_TO_ONE | MANY_TO_MANY | MORPH_TO`

## 最小可运行模板
```ts
import { ColumnType, defineEntity } from 'ocorm'

defineEntity('Post', {
  tableName: 'posts',
  columns: [
    { property: 'id', primaryKey: true, autoIncrement: true },
    { property: 'title', type: ColumnType.TEXT, nullable: false, length: 200 },
    { property: 'score', type: ColumnType.REAL, defaultValue: 0 },
    { property: 'payload', type: ColumnType.BLOB, nullable: true }
  ],
  softDelete: true
})
```

## 失败示例与修复
失败示例（文档常见误写）：
```ts
// 错误示意（非 ocorm 公共 API）:
// @Entity()
// class User {
//   @PrimaryGeneratedColumn()
//   id!: number
// }
```

修复：`ocorm` 当前导出的是 `Table` 与 `PrimaryKey`，不是 `Entity/PrimaryGeneratedColumn`。
