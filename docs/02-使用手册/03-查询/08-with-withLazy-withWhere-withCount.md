# with / withLazy / withWhere / withCount

## 何时用
关系加载需要过滤、延迟或计数时。

## 怎么用
按单个查询目标组合关系选项，保持语义可读。

```ts
qb.with(['posts']).withWhere('posts', (rq) => rq.where('status', '=', 'PUBLISHED'))
```

## 常见误用
同一关系叠加冲突过滤规则，导致结果不可预期。
