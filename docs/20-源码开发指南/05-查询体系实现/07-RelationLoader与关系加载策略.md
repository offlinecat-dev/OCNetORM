# 07-RelationLoader与关系加载策略

关系加载由 `RelationLoader` 执行，`QueryExecutor` 负责路径递归与顺序编排。

## 正确示例
```ts
const list = await new QueryExecutor(
  repo.createQueryBuilder()
    .with('posts.comments.author')
    .withWhere('posts', q => q.where('status', ConditionOperator.EQUAL, 'published'))
    .withCount('posts', 'posts_count')
).get()
```

```ts
const lazyList = await new QueryExecutor(
  repo.createQueryBuilder().withLazy('profile')
).get()
```

## 误用示例（`withLazy` 传多级路径）
```ts
repo.createQueryBuilder().withLazy('posts.comments')
```

语义结果：抛关系不存在错误（`withLazy` 仅接受一级关系名）。

## 源码定位
- `OCORM/src/main/ets/query/RelationLoader.ets`
- `OCORM/src/main/ets/query/QueryExecutorRelationSupport.ets`
- `OCORM/src/main/ets/query/RelationLoaderMorphToSupport.ets`
