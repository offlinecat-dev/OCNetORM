# ScopeRegistry 与作用域

## 何时用
需要复用统一过滤规则（如软删除、租户过滤）时。

## 怎么用
把可复用过滤逻辑注册成作用域，并在查询中启用。

```ts
import { ScopeRegistry } from 'ocorm'

ScopeRegistry.register('User', 'activeOnly', (qb) => qb.whereNull('deleted_at'))
```

## 常见误用
把作用域逻辑散落在页面层，导致行为不一致。
