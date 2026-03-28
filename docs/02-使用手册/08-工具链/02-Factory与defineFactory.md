# Factory 与 defineFactory

`defineFactory` 用于统一构造测试数据和开发数据，避免散落的手写对象。

## 示例
```ts
import { defineFactory } from 'ocorm'

const userFactory = defineFactory('User', (faker, index) => ({
  userName: `${faker.name()}-${index}`,
  age: faker.number({ min: 18, max: 60 })
}))
```

## 设计建议
- 每个实体维护一个主 Factory
- 对边界值（空值、极大值）单独建场景 Factory
- 不在业务代码中直接依赖 faker 细节
