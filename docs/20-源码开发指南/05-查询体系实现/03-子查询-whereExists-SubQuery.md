# 03-子查询-whereExists-SubQuery

`whereExists` 用于“按关联是否存在且满足条件”过滤主实体。

## 正确示例
```ts
const qb = repo.createQueryBuilder()
  .whereExists('posts', sub => {
    sub.where('status', ConditionOperator.EQUAL, 'published')
      .where('viewCount', ConditionOperator.GREATER_EQUAL, 100)
  })
  .orderBy('id', 'DESC')
```

```ts
const data = await new QueryExecutor(qb).get()
const page = await new QueryExecutor(qb.clone().paginate(1, 20)).getPaginated()
```

## 误用示例（关系名不存在）
```ts
repo.createQueryBuilder().whereExists('invalidRelation', () => {})
```

语义结果：抛 `RelationNotFoundError(entityName, 'invalidRelation')`。

## 源码定位
- `src/main/ets/query/QueryBuilder.ets`
- `src/main/ets/query/SubQuery.ets`
- `src/main/ets/query/QueryExecutorSubQueryPreparationSupport.ets`
- `src/main/ets/query/SubQueryRelationExecutor.ets`
