# 06-QueryExecutor原生模式-getRaw

原生模式返回 `ResultSetRow[]`，用于报表与聚合。

## 正确示例
```ts
const rows = await new QueryExecutor(
  repo.createQueryBuilder()
    .selectRaw(['status', 'COUNT(*) AS total'])
    .groupBy('status')
    .having('COUNT(*) >= ?', [1])
    .orderBy('status', 'ASC')
).getRaw()
```

```ts
for (const row of rows) {
  const status = row.get('status')
  const total = row.get('total')
}
```

## 误用示例（期待关系预加载生效）
```ts
const rawRows = await new QueryExecutor(
  repo.createQueryBuilder()
    .with('posts')
    .selectRaw(['id'])
).getRaw()
```

语义结果：`getRaw()` 不做实体关系装配，`with/withLazy/withCount` 不会写入结果行。

## 源码定位
- `OCORM/src/main/ets/query/QueryExecutor.ets`
- `OCORM/src/main/ets/query/QueryExecutorSqlSupport.ets`
- `OCORM/src/main/ets/mapping/ResultSetRow.ets`
