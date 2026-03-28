# defineEntity 与 EntitySchema

## 何时用
希望快速注册实体并直接开始仓储查询时。

## 怎么用
使用 `defineEntity` 声明表结构，保持 property 与列名映射一致。

```ts
import { ColumnType, defineEntity } from 'ocorm'

defineEntity('Post', {
  tableName: 'posts',
  columns: [
    { property: 'id', primaryKey: true, autoIncrement: true },
    { property: 'title', type: ColumnType.TEXT },
    { property: 'userId', name: 'user_id', type: ColumnType.INTEGER }
  ]
})
```

## 常见误用
`property` 与 `name` 写反，导致字段读写错位。
