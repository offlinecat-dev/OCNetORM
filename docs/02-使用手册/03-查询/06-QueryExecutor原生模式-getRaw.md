# QueryExecutor 原生模式（getRaw）

## 何时用
结果是聚合列或自定义列集合时。

## 怎么用
使用 `getRaw` 或 `aggregate` 获取原生结果。

```ts
const rows = await new QueryExecutor(qb).getRaw()
```

## 常见误用
把原生结果当实体对象直接调用实体字段行为。
