# 01-QueryBuilder基础链式API

`QueryBuilder` 负责声明，不执行 SQL。执行需交给 `QueryExecutor`。

## 最小链式查询
```ts
const qb = repo.createQueryBuilder()
  .where('age', ConditionOperator.GREATER_EQUAL, 18)
  .andWhere('status', ConditionOperator.EQUAL, 'active')
  .orderBy('createdAt', 'DESC')
  .paginate(2, 10)
  .with('profile')
```

```ts
const sql = qb.toSQL()
const desc = qb.getQueryDescription()
const first = await new QueryExecutor(qb.clone()).getOne()
```

## 误用示例（非法排序方向）
```ts
repo.createQueryBuilder().orderBy('id', 'DOWN' as never)
```

语义结果：抛 `InvalidConditionError('ORDER BY', '非法排序方向: DOWN')`。

## 源码定位
- `src/main/ets/query/QueryBuilder.ets`
- `src/main/ets/query/QueryBuilderGuards.ets`（内部守卫实现，未导出）
- `src/main/ets/query/QueryExecutor.ets`
