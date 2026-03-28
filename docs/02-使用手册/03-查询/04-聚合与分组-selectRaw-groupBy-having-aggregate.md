# 聚合与分组（selectRaw / groupBy / having / aggregate）

## 何时用
需要统计报表、分组计数、求和与平均值时。

## 怎么用
聚合查询使用原生模式入口并严格参数化。

```ts
const rows = await new QueryExecutor(
  repo.createQueryBuilder()
    .selectRaw(['status', 'COUNT(*) AS total'])
    .groupBy('status')
    .having('COUNT(*) > ?', [1])
).getRaw()
```

## 常见误用
在 `get()` 实体模式中混用 `selectRaw/groupBy/having`。
