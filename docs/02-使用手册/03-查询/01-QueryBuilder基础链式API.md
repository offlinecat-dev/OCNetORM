# QueryBuilder 基础链式 API

## 何时用
需要组合 where、orderBy、limit、paginate 条件时。

## 怎么用
围绕一个 QueryBuilder 实例链式添加条件。

```ts
const qb = repo.createQueryBuilder()
  .where('age', '>=', 18)
  .orderBy('userName', 'ASC')
  .paginate(1, 20)
```

## 常见误用
在多个异步流程共享同一个可变 QueryBuilder 实例。
