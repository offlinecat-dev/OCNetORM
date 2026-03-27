# 10-QueryCache机制与失效策略

`QueryCache` 是实体级缓存，不是严格 LRU。

## 正确示例
```ts
const cache = QueryCache.getInstance()
cache.configure({ maxSize: 200, ttlMs: 60000, enabled: true })
cache.setNamespace('main_db')
```

```ts
const hit = cache.get('User', 1)
cache.invalidate('User', 1)
cache.invalidateEntity('Post')
const stats = cache.getStatistics()
```

## 误用示例（把它当 LRU）
```ts
cache.set('User', 1, userA)
cache.set('User', 2, userB)
// 高频读取 id=1
cache.get('User', 1)
cache.get('User', 1)
// 新写入触发淘汰时，不保证保留 id=1
```

语义结果：淘汰按最早写入时间，不按最近访问时间。

## 源码定位
- `OCORM/src/main/ets/query/QueryCache.ets`
- `OCORM/src/main/ets/repository/Repository.ets`
- `OCORM/src/main/ets/query/QueryExecutor.ets`
