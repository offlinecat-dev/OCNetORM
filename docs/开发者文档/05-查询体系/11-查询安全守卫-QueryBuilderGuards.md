# 11-查询安全守卫-QueryBuilderGuards

守卫层负责在 QueryBuilder 阶段拦截危险输入。`QueryBuilderGuards` 属于内部实现，不是 `ocorm` 的公共导出 API。

## 正确用法（通过 QueryBuilder 公共 API 触发守卫）
```ts
const qb = repo.createQueryBuilder()
  .selectRaw(['status', 'COUNT(*) AS total'])
  .groupBy('status')
  .having('COUNT(*) > ?', [5])

const rows = await new QueryExecutor(qb).getRaw()
```

## 误用示例 1（非法排序方向）
```ts
repo.createQueryBuilder().orderBy('id', 'DOWN' as never)
```

语义结果：抛 `InvalidConditionError('ORDER BY', '非法排序方向: DOWN')`。

## 误用示例 2（selectRaw 危险 token）
```ts
repo.createQueryBuilder().selectRaw(['name;DROP TABLE users'])
```

语义结果：抛 `InvalidConditionError('selectRaw', 'selectRaw 包含危险 SQL 片段')`。

## 误用示例 3（HAVING 占位符不匹配）
```ts
repo.createQueryBuilder()
  .selectRaw(['status', 'COUNT(*) AS total'])
  .groupBy('status')
  .having('COUNT(*) > ? AND AVG(score) > ?', [10])
```

语义结果：抛 `InvalidConditionError('HAVING', 'HAVING 占位符数量与参数数量不一致')`。

## 源码定位
- `OCORM/src/main/ets/query/QueryBuilder.ets`（公共入口）
- `OCORM/src/main/ets/query/QueryBuilderGuards.ets`（内部守卫实现，未导出）
