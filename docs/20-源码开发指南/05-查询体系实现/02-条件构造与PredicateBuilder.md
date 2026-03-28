# 02-条件构造与PredicateBuilder

`PredicateBuilder` 将 QueryBuilder 条件转换为 `RdbPredicates`，供执行器复用。

## 典型条件组合
```ts
const qb = repo.createQueryBuilder()
  .where('status', ConditionOperator.EQUAL, 'active')
  .orWhere('score', ConditionOperator.GREATER, 90)
  .whereBetween('createdAt', 1700000000000, 1800000000000)
  .whereLike('nickname', 'A%')
  .whereNotNull('email')
```

```ts
const list = await new QueryExecutor(
  qb.orderBy('createdAt', 'DESC').limit(20).offset(0)
).get()
```

## 误用示例（IN 传空数组）
```ts
repo.createQueryBuilder().whereIn('id', [])
```

语义结果：抛 `InvalidConditionError('id', 'IN 条件不能为空')`（由 `QueryBuilder.whereIn` 入参校验触发）。

## 源码定位
- `src/main/ets/query/QueryBuilder.ets`
- `src/main/ets/query/PredicateBuilder.ets`
- `src/main/ets/types/ConditionOperator.ets`
