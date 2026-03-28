# Validation API 契约

实现依据：`src/main/ets/validation/*.ets`

## 验证装饰器（`Required/Length/Email/...`）

- 用途：为实体属性注册验证规则元数据。
- 参数：
  - 常用：`Required`, `Length`, `Email`, `Min`, `Max`, `Range`, `Pattern`, `Enum`
  - 条件规则：`RequiredIf`, `RequiredUnless`
  - 自定义规则：`Custom`, `Unique`
  - 日期规则导出名为 `Date`（内部实现 `DateRule`）
- 返回：属性装饰器函数
- 异常：
  - 实体未注册时抛 `EntityNotRegisteredError`
- 副作用：规则写入全局 `ValidationMetadataStorage`。
- 事务上下文：无。
- 最小示例：

```ts
import { Table, Column, Required, Length, Email } from 'ocorm'

@Table('users')
class User {
  @Column({ name: 'name' })
  @Required()
  @Length({ min: 2, max: 32 })
  name: string = ''

  @Column({ name: 'email' })
  @Email()
  email: string = ''
}
```

## `ValidationMetadataStorage`

- 用途：管理实体验证规则。
- 参数：
  - `registerRule(entityName, propertyName, rule)`
  - `getRules(entityName)`
  - `getRulesForProperty(entityName, propertyName)`
  - `clear()`
- 返回：
  - 注册接口返回 `void`
  - 查询接口返回规则集合
- 异常：
  - 注册时若实体未注册抛 `EntityNotRegisteredError`
- 副作用：更新全局规则存储。
- 事务上下文：无。
- 最小示例：

```ts
import { ValidationMetadataStorage } from 'ocorm'

const storage = ValidationMetadataStorage.getInstance()
const rules = storage.getRules('User')
```

## `EntityValidator.validate(entityName, entityData, options?)`

- 用途：执行规则校验并返回汇总结果，不抛异常。
- 参数：
  - `entityName: string`
  - `entityData: EntityData`
  - `options.groups?: string[]`
  - `options.uniqueChecker?: (entityName, propertyName, value, entityData) => boolean`
- 返回：`ValidationResult`
  - `isValid()`
  - `errors: ValidationError[]`
  - `getSummary()`
- 异常：无（错误写入 `ValidationResult`）。
- 副作用：无。
- 事务上下文：无。
- 最小示例：

```ts
import { EntityValidator } from 'ocorm'

const result = EntityValidator.validate('User', entityData, {
  groups: ['create'],
  uniqueChecker: () => true
})
```

## `EntityValidator.validateOrThrow(...)`

- 用途：校验失败时直接抛错。
- 参数：与 `validate` 一致。
- 返回：`void`
- 异常：
  - 单个错误时抛对应 `ValidationError` 子类
  - 多个错误时抛 `EntityValidationError`（消息为汇总）
- 副作用：无。
- 事务上下文：无。
- 最小示例：

```ts
import { EntityValidator } from 'ocorm'

EntityValidator.validateOrThrow('User', entityData)
```
