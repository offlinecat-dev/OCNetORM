# 04-聚合与分组-selectRaw-groupBy-having-aggregate

聚合表达式只在原生模式可用，实体模式禁止混用。

## `getRaw` 聚合
```ts
const rows = await new QueryExecutor(
  repo.createQueryBuilder()
    .selectRaw(['status', 'COUNT(*) AS total', 'MAX(score) AS topScore'])
    .groupBy('status')
    .having('COUNT(*) > ?', [5])
    .orderBy('status', 'ASC')
).getRaw()
```

## `aggregate` 聚合
```ts
const result = await new QueryExecutor(
  repo.createQueryBuilder()
    .selectRaw(['category', 'AVG(price) AS avgPrice'])
    .groupBy('category')
    .having('AVG(price) > ?', [100])
).aggregate()
```

## 误用示例（HAVING 非参数化）
```ts
repo.createQueryBuilder()
  .selectRaw(['status', 'COUNT(*) AS total'])
  .groupBy('status')
  .having('COUNT(*) > 10')
```

语义结果：抛 `InvalidConditionError('HAVING', 'HAVING 必须使用参数占位符')`。

## 源码定位
- `OCORM/src/main/ets/query/QueryBuilder.ets`
- `OCORM/src/main/ets/query/QueryBuilderGuards.ets`（内部守卫实现，未导出）
- `OCORM/src/main/ets/query/AggregateExecutor.ets`
- `OCORM/src/main/ets/query/QueryExecutor.ets`
