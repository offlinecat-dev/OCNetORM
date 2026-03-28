# 子查询（whereExists / SubQuery）

## 何时用
按关联存在性过滤主查询结果时。

## 怎么用
使用 `whereExists` 构建子查询并保持参数化。

```ts
qb.whereExists((sub) => sub.from('posts').whereRaw('posts.user_id = users.id'))
```

## 常见误用
子查询别名和主查询别名不一致导致语义错误。
