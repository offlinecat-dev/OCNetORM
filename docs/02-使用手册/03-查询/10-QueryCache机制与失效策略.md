# QueryCache 机制与失效策略

## 何时用
读多写少场景希望减少重复查询时。

## 怎么用
开启缓存并配置合理 TTL，写入后主动或策略化失效。

```ts
const config = new DatabaseConfig('app.db').setQueryCache(true, 200, 60000)
```

## 常见误用
高写入场景使用过长缓存 TTL 导致旧数据读取。
