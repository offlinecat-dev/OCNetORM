# 05-映射-验证与装饰器API

何时用：实体映射、字段验证、生命周期钩子。

怎么用：
```ts
import { EntityData, ValidationDecorators } from 'ocorm'
```

常见误用：未注册实体元数据直接使用验证装饰器。

