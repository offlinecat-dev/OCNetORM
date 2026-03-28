# DatabaseConfig 配置

## 何时用
需要控制缓存、查询超时和并发行为时。

## 怎么用
从最小配置开始，再根据业务负载逐步调优。

```ts
import { DatabaseConfig } from 'ocorm'

const config = new DatabaseConfig('app.db')
  .setQueryCache(true, 200, 60000)
  .setQueryTimeout(1500)
  .setMaxConcurrentQueries(4)
```

## 常见误用
一次性开启过高并发参数而不验证设备资源。
