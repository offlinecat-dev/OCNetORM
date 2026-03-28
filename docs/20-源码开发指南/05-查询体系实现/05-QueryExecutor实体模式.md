# 05-QueryExecutor实体模式

实体模式返回 `EntityData` / `PaginatedResult`，适合业务读模型。

## 正确示例
```ts
const qb = repo.createQueryBuilder()
  .where('deletedAt', ConditionOperator.IS_NULL, null)
  .with('profile')
  .withCount('posts', 'posts_count')
  .orderBy('createdAt', 'DESC')
  .paginate(1, 20)

const executor = new QueryExecutor(qb)
const list = await executor.get()
const one = await executor.getOne()
const total = await executor.count()
```

```ts
await new QueryExecutor(
  repo.createQueryBuilder().where('status', ConditionOperator.EQUAL, 'active')
).chunk(100, async (batch, page) => {
  // 批处理
})
```

## 误用示例（实体模式使用 selectRaw）
```ts
await new QueryExecutor(
  repo.createQueryBuilder().selectRaw(['COUNT(*) AS total'])
).count()
```

语义结果：抛 `ExecutionError('COUNT', '实体查询不支持 selectRaw/groupBy/having，请使用 getRaw() 或 aggregate()')`。

## 源码定位
- `src/main/ets/query/QueryExecutor.ets`
- `src/main/ets/query/QueryExecutorRelationSupport.ets`
- `src/main/ets/query/QueryExecutorSubQueryPreparationSupport.ets`
