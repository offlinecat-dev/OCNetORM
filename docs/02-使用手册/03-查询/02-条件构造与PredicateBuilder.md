# 条件构造与 PredicateBuilder

## 何时用
存在复杂条件组合（AND/OR）时。

## 怎么用
使用条件 API 和参数绑定，避免拼接用户输入。

```ts
qb.where('status', '=', 'ACTIVE').orWhere('status', '=', 'PENDING')
```

## 常见误用
把用户输入直接拼接到条件字符串。
