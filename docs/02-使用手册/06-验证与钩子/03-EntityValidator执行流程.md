# 03-EntityValidator执行流程

> 状态：完成
> 适用版本：ocorm 3.x（基于当前源码）
> 最后更新：2026-03-27

## 1. 目标
`EntityValidator` 的职责不是注册规则，而是消费 `验证规则存储` 中已经登记的规则，对单个实体数据做一次完整扫描，并输出 `ValidationResult` 或抛出 `ValidationError`。
它是验证链路的唯一执行入口：`validate` 用于收集错误，`validateOrThrow` 用于失败即中断。
如果你要排查“为什么某条规则没生效”或“为什么一次报了多个字段错”，应该先从这里看执行顺序。

## 2. 背景与适用范围
适用于以下场景：
- 需要解释 `EntityValidator.validate` 与 `validateOrThrow` 的行为差异
- 需要确认 `groups`、`requiredIf`、`requiredUnless`、`custom`、`unique` 的运行条件
- 需要根据 `ValidationError` / `EntityValidationError` 快速定位失败字段

不适用于以下问题：
- 规则如何声明：看 `ValidationDecorators`
- 钩子何时触发：看 `HooksProcessor`

## 3. 前置条件
- 规则已经通过 `ValidationDecorators` 注册进 `验证规则存储`
- 调用方已经准备好实体名与实体数据对象
- 如果用了 `Unique()`，调用 `validate` 或 `validateOrThrow` 时必须显式传入 `uniqueChecker`
- 如果用了分组规则，调用方必须在 `ValidationOptions.groups` 中传入目标分组

## 4. 关键概念与约束
### 4.1 两个公开入口
- `EntityValidator.validate(entityName, entityData, options)`：返回 `ValidationResult`，不会抛出字段错误
- `EntityValidator.validateOrThrow(entityName, entityData, options)`：内部先调用 `validate`，再按错误数量决定抛错方式

### 4.2 `ValidationResult` 的三个读取方式
- `isValid()`：是否无错误
- `getFirstError()`：拿第一条错误，适合快速失败 UI
- `getSummary()`：把所有 `error.message` 用 `; ` 拼接成摘要

### 4.3 单错与多错的抛出策略
- 只有 1 条错误：`validateOrThrow` 直接抛该条具体错误，例如 `RequiredValidationError`
- 大于 1 条错误：抛 `EntityValidationError`，`reason` 来自 `getSummary()`

```text
validate(entityName, entityData, options)
  -> 验证规则存储.getRules(entityName)
  -> 无规则: 返回空 ValidationResult
  -> 归一化 groups
  -> 逐字段、逐规则执行 shouldRunRule(rule, groups)
  -> 命中后进入 validateRule(...)
  -> 收集 ValidationError[]
  -> 返回 ValidationResult

validateOrThrow(...)
  -> 调用 validate(...)
  -> 0 条错误: 直接返回
  -> 1 条错误: 直接抛该错误
  -> 多条错误: 抛 EntityValidationError
```

## 5. 关键流程/规则
### 5.1 执行顺序
1. 读取当前实体的全部规则
2. 如果实体没有任何规则，立即返回空结果
3. 归一化 `options.groups`，空数组表示“不过滤分组”
4. 遍历每个属性的规则列表
5. 用 `shouldRunRule` 判断当前规则是否该运行
6. 进入 `validateRule` 的 `switch` 分支执行具体验证
7. 将失败项追加到 `ValidationResult.errors`

### 5.2 规则运行条件
- `required`：字段不存在，或者值为 `null`、`undefined`、空字符串（会 `trim`）时失败
- `requiredIf`：依赖字段值与 `expectedValue` 严格相等时，当前字段必须有值
- `requiredUnless`：依赖字段值与 `expectedValue` 不相等时，当前字段必须有值
- `length/email/min/max/range/pattern/url/phone/date/enum`：字段不存在或值为空时大多直接跳过，不会替代 `required`
- `custom`：只有字段存在且提供了 `customValidator` 才执行
- `unique`：只有字段存在且调用方传了 `uniqueChecker` 才执行

### 5.3 分组过滤语义
`shouldRunRule` 的行为非常直接：
- 调用方未传 `groups`：所有规则执行
- 规则本身未设置 `rule.groups`：即使调用方传了 `groups`，该规则仍执行
- 两边都设置了 `groups`：只要存在任意交集就执行

```ts
import { EntityValidator } from 'ocorm'

const entityData = /* 已构造的实体数据对象 */

const result = EntityValidator.validate('User', entityData, {
  groups: ['create'],
  uniqueChecker: (entityName, propertyName, value) => {
    return !(entityName === 'User' && propertyName === 'email' && value === 'used@example.com')
  }
})

if (!result.isValid()) {
  const firstError = result.getFirstError()
  const summary = result.getSummary()
  console.info(firstError?.name)
  console.info(summary)
}
```

### 5.4 规则细节里最容易忽略的点
- `pattern` 在每次测试前后都会重置 `RegExp.lastIndex`，避免全局正则状态污染
- `date` 同时接受 `Date`、`string`、`number`；只要 `new Date(value)` 可解析就通过
- `customValidator` 返回 `true` 表示通过；返回字符串会被作为 `CustomValidationError` 的 message
- `uniqueChecker` 的签名是同步函数，返回 `boolean`

## 6. 示例
### 6.1 正例：批量收集错误
```ts
import { EntityValidator } from 'ocorm'

const entityData = /* 已构造的实体数据对象 */
const result = EntityValidator.validate('Account', entityData)

if (!result.isValid()) {
  result.errors.forEach((error) => {
    console.error(error.name, error.message)
  })
}
```

### 6.2 正例：失败即中断
```ts
import { EntityValidator } from 'ocorm'

const entityData = /* 已构造的实体数据对象 */

try {
  EntityValidator.validateOrThrow('Account', entityData, {
    groups: ['update']
  })
  // 只有校验通过才继续后续流程
} catch (error) {
  console.error(error)
}
```

### 6.3 误用示例：把 `validateOrThrow` 当返回值 API
```ts
import { EntityValidator } from 'ocorm'

const entityData = /* 已构造的实体数据对象 */

// 误用：validateOrThrow 返回 void，不会给你 ValidationResult
const result = EntityValidator.validateOrThrow('Account', entityData)
// result.isValid() // 这里的调用思路就是错的
```

### 6.4 误用示例：以为 `Unique` 会自动查询唯一性
```ts
import { EntityValidator } from 'ocorm'

const entityData = /* 已构造的实体数据对象 */

// 误用：没有 uniqueChecker 时，unique 分支会直接 return
const result = EntityValidator.validate('Account', entityData)
console.info(result.isValid())

// 正确：显式注入 uniqueChecker
EntityValidator.validate('Account', entityData, {
  uniqueChecker: (_entityName, _propertyName, value) => value !== 'duplicated@example.com'
})
```

## 7. 验收与测试
最小验收应覆盖以下断言：
- 无规则实体：`validate` 返回空 `ValidationResult`
- 单一失败：`validateOrThrow` 抛具体子类错误，而不是聚合错误
- 多字段失败：`validateOrThrow` 抛 `EntityValidationError`
- 带 `groups` 调用时，未命中的规则不执行
- `RequiredIf` / `RequiredUnless` 的依赖字段变化会影响当前字段是否必填
- `Unique` 在未传 `uniqueChecker` 时不会报错，但也不会做唯一性判断

```ts
import { EntityValidator } from 'ocorm'
import { EntityValidationError } from 'ocorm'

const entityData = /* 已构造的实体数据对象 */

try {
  EntityValidator.validateOrThrow('Account', entityData)
} catch (error) {
  if (error instanceof EntityValidationError) {
    console.error('多字段失败:', error.message)
  }
}
```

## 8. 常见问题
### 8.1 为什么字段明明没填，但没有报错？
先确认挂的是不是 `Required` / `RequiredIf` / `RequiredUnless`。`Email`、`Length`、`Pattern` 这类规则对缺失字段通常直接跳过，不负责“必填”。

### 8.2 为什么只抛了 `EntityValidationError`，看不到具体规则类型？
因为 `validateOrThrow` 在多错场景会聚合成一个实体级错误。要看逐条字段错误，先改用 `validate` 读取 `result.errors`。

### 8.3 为什么错误消息里的字段名不是属性名？
`EntityValidator` 会优先使用列名；如果当前属性能映射到列，错误消息里展示的是列名而不是属性名。这是预期行为，定位时要同时对照属性名与列名。

### 8.4 报错与定位方式
定位顺序固定按下面做，不要猜：
1. 看 `result.errors.length` 或捕获到的错误类型，先判断是单错还是多错。
2. 看 `error.name`，确认是字段级 `ValidationError` 还是聚合级 `EntityValidationError`。
3. 看 `error.message`，拿到用户可读提示。
4. 如果是聚合错，再回到 `validate` 版本读取 `result.errors` 逐条拆开。
5. 如果 `Unique` 没报错但业务数据重复，优先检查调用时是否传入了 `uniqueChecker`。

```ts
import {
  ValidationError,
  EntityValidationError
} from 'ocorm'
import { EntityValidator } from 'ocorm'

const entityData = /* 已构造的实体数据对象 */

try {
  EntityValidator.validateOrThrow('Account', entityData, {
    uniqueChecker: (_entityName, _propertyName, value) => value !== 'duplicated@example.com'
  })
} catch (error) {
  if (error instanceof EntityValidationError) {
    console.error('聚合失败:', error.message)
  } else if (error instanceof ValidationError) {
    console.error('字段级失败:', error.message)
  }
}
```

## 9. 变更记录
- 2026-03-27：完成执行流程文档，补齐执行顺序、分组语义、误用示例与报错定位。



