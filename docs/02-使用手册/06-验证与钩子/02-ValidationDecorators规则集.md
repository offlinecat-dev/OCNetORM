# 02-ValidationDecorators规则集

> 状态：完成
> 适用版本：ocorm 3.x（基于当前源码）
> 最后更新：2026-03-27

## 1. 装饰器清单（真实 API）
来自 `validation/ValidationDecorators`：
- 必填与条件必填：`Required`、`RequiredIf`、`RequiredUnless`
- 字符串与格式：`Length`、`Email`、`Pattern`
- 数值：`Min`、`Max`、`Range`
- 类型/集合：`Enum`、`Date`（由 `DateRule as Date` 导出）
- 其他：`URL`、`Phone`、`Custom`、`Unique`
- 通用选项：多数支持 `{ groups?: string[] }`

## 2. 规则正例
```ts
import {
  ColumnType, Date, Email, Enum, Length, Max, Min, Pattern, Required, RequiredIf, defineEntity
} from 'ocorm'

defineEntity('Account', {
  columns: [
    { property: 'username', type: ColumnType.TEXT },
    { property: 'email', type: ColumnType.TEXT },
    { property: 'score', type: ColumnType.INTEGER },
    { property: 'code', type: ColumnType.TEXT },
    { property: 'status', type: ColumnType.TEXT },
    { property: 'createdAt', type: ColumnType.INTEGER },
    { property: 'disabledReason', type: ColumnType.TEXT, nullable: true }
  ]
})

class Account {
  @Required({ groups: ['create'] })
  @Length({ min: 3, max: 20 })
  username: string = ''

  @Email()
  email: string = ''

  @Min(0)
  @Max(100)
  score: number = 0

  @Pattern(/^[A-Z]{2}\d{4}$/)
  code: string = ''

  @Enum(['active', 'disabled'])
  status: string = 'active'

  @Date()
  createdAt: string = ''

  @RequiredIf('status', 'disabled')
  disabledReason: string = ''
}
```

```ts
import { ColumnType, Custom, Unique, defineEntity } from 'ocorm'

defineEntity('Product', {
  columns: [
    { property: 'sku', type: ColumnType.TEXT },
    { property: 'serialNo', type: ColumnType.TEXT, unique: true }
  ]
})

class Product {
  @Custom((value) => {
    if (typeof value !== 'string') {
      return 'sku 必须是字符串'
    }
    return value.startsWith('SKU-') || 'sku 必须以 SKU- 开头'
  })
  sku: string = ''

  @Unique()
  serialNo: string = ''
}
```

```ts
import { EntityValidator } from 'ocorm'

EntityValidator.validate('Account', entityData, {
  groups: ['create'],
  uniqueChecker: (entityName, propertyName, value) => {
    return !(entityName === 'Product' && propertyName === 'serialNo' && value === 'EXISTS-1')
  }
})
```

## 3. 误用示例
### 3.1 未注册实体直接挂装饰器
当前实现要求实体先注册，装饰器后执行。

```ts
class GhostEntity {
  @Required()
  name: string = ''
}
// ensureEntityRegistered 会抛 EntityNotRegisteredError
```

### 3.2 把 `Date` 当作 JavaScript 内置构造器调用
```ts
// 误用：装饰器语义中应使用 @Date()，不是 new Date() 或 @Date
class Event {
  @Date()
  startedAt: string = ''
}
```

### 3.3 `RequiredIf/RequiredUnless` 依赖字段写错
```ts
class Task {
  @RequiredIf('stauts', 'done') // 拼写错误，实际属性应为 status
  doneReason: string = ''
}
// 依赖值取不到时，条件判断偏离预期
```

## 4. 报错与定位方式
### 4.1 常见验证错误类型
```ts
import {
  ValidationError,
  RequiredValidationError,
  LengthValidationError,
  EmailValidationError,
  EntityValidationError
} from 'ocorm'
```

说明：
- `ocorm` 公共导出里已提供通用基类 `ValidationError`，以及常见的 `Required/Length/Email` 细分错误与聚合错误 `EntityValidationError`。
- 其余规则失败可统一按 `ValidationError` 处理，并通过 `error.message`、`error.name` 和业务上下文定位。

### 4.2 定位步骤
- 先看 `error.name` 与 `error.message`，定位失败字段与规则语义
- 看 `error.message` 获取用户可读信息
- 多字段失败时，`validateOrThrow` 抛 `EntityValidationError`，其 `reason` 是聚合摘要
- 优先核查字段映射：`EntityValidator` 会用 `metadata.getColumnByProperty(propertyName)?.columnName ?? propertyName`

```ts
try {
  EntityValidator.validateOrThrow('Account', entityData, { groups: ['create'] })
} catch (error) {
  // 先确认是单错还是聚合错
  // 再按 columnName / propertyName 对照实体字段
}
```

## 5. 分组规则要点
- 调用方未传 `groups`：所有规则都执行
- 规则未设置 `rule.groups`：即使调用方传了 groups，该规则仍执行
- 规则设置了 `rule.groups`：只要与目标 groups 有交集才执行

```ts
// shouldRunRule 的行为等价示意
const runWhenNoTargetGroups = true
const runWhenRuleHasNoGroups = true
const runWhenIntersectionExists = true
```

## 6. 变更记录
- 2026-03-27：完成规则集文档，补齐正例、误用、报错定位与 groups 执行语义。



