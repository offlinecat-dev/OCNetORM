# RelationLoader 与关系加载策略

## 何时用
需要预加载关联数据并避免 N+1 查询时。

## 怎么用
在主查询声明 `with` 和 `withCount`。

```ts
qb.with(['posts']).withCount('posts', 'postsCount')
```

## 常见误用
循环中逐条查询关系导致性能退化。
