# 05-关系加载与withCount

本章只关注关系 DSL：`with`、`withLazy`、`withWhere`、`withCount`。

## 正确示例
```ts
const qb = repo.createQueryBuilder()
  .with('posts.comments')
  .withWhere('posts', q => {
    q.where('status', ConditionOperator.EQUAL, 'published')
      .orderBy('createdAt', 'DESC')
      .limit(5)
  })
  .withCount('posts.comments', 'comments_count')
  .withLazy('profile')
```

```ts
const data = await new QueryExecutor(qb).get()
```

## 误用示例（`withWhere` 回调抛异常）
```ts
repo.createQueryBuilder().withWhere('posts', () => {
  throw new Error('callback failed')
})
```

语义结果：抛 `InvalidConditionError('withWhere', '关联过滤回调执行失败: callback failed')`。

## 源码定位
