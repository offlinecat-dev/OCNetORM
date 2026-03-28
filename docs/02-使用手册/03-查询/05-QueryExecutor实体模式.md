# QueryExecutor 实体模式

## 何时用
查询结果需要返回实体数据结构时。

## 怎么用
使用 `get/getOne/getPaginated/count` 等实体模式方法。

```ts
const page = await new QueryExecutor(qb.paginate(1, 20)).getPaginated()
```

## 常见误用
实体模式下使用原生聚合表达式。
