# 03-错误国际化-ErrorLocale

> 状态：已完成
> 适用版本：ocorm 3.x（当前 3.0.2）
> 最后更新：2026-03-27

## 1. 目标
- 说明 `errors/ErrorLocale.ets` 的真实国际化入口与数据结构。
- 说明 `OrmError` 与 `ValidationError` 如何在构造阶段完成本地化，不允许把运行时行为想象成响应式切换。
- 给出正确处理、误处理、观测排障方案，避免出现“切语言了但错误消息没变”的伪问题。

## 2. 源码事实
`errors/ErrorLocale.ets` 的文件级导出如下：
- `ErrorLocale`（type）
- `ErrorTemplateContext`
- `ErrorLocaleMessageEntry`
- `ErrorLocaleMessages`
- `ErrorLocaleRegistry`
- `setErrorLocale(locale)`：切换当前语言，默认值是 `zh`。
- `getErrorLocale()`：读取当前语言。
- `registerErrorLocaleMessages(locale, messages, override?)`：注册或合并某个语言包。
- `formatErrorMessage(code, fallback, context?)`：按当前语言和模板上下文生成消息。

`errors/index.ets` 的包级再导出（`ocorm` 顶层导出）仅包含：
- `ErrorLocale`
- `ErrorLocaleMessages`
- `setErrorLocale`
- `getErrorLocale`
- `registerErrorLocaleMessages`
- `formatErrorMessage`

因此，`ErrorTemplateContext`、`ErrorLocaleMessageEntry`、`ErrorLocaleRegistry` 需要从 `errors/ErrorLocale.ets` 直接导入，`errors/index.ets` 不会转出它们。

默认注册表内置了 `zh` 与 `en` 两套文案，覆盖 `ORM001` 到 `ORM814` 的当前错误码范围。

```ts
import {
  getErrorLocale,
  setErrorLocale,
  formatErrorMessage,
  ErrorTemplateContext
} from '../src/main/ets/errors/ErrorLocale'

const context = new ErrorTemplateContext()
context.columnName = 'email'

console.info(getErrorLocale())
setErrorLocale('en')
console.info(formatErrorMessage('ORM802', 'fallback', context))
```

## 3. 生效机制
真正的关键点在 `errors/OrmError.ets`：`OrmError` 构造函数会立即调用 `formatErrorMessage(...)`，然后把结果传给 `super(localizedMessage)`。这意味着：
- 国际化是在“创建错误对象时”完成的，不是读取 `error.message` 时再动态翻译。
- 先 `setErrorLocale('en')` 再 `new RequiredValidationError(...)`，消息才会是英文。
- 错误对象一旦创建完成，后面再切语言，不会自动刷新旧对象的 `message`。

`ValidationError` 系列额外传入 `ErrorTemplateContext`，因此 `ORM803/ORM805/ORM807` 这类带 `{min}`、`{max}` 占位符的模板才能正确插值。

```ts
import { setErrorLocale } from '../src/main/ets/errors/ErrorLocale'
import {
  RequiredValidationError,
  LengthValidationError
} from 'ocorm'

setErrorLocale('en')
const requiredError = new RequiredValidationError('User', 'email')
const lengthError = new LengthValidationError('User', 'nickname', 2, 20)

console.info(requiredError.message)
console.info(lengthError.message)
```

## 4. 正确处理方式
正确做法是把语言切换放在错误对象创建之前，并在需要扩展语言时使用 `ErrorLocaleMessages` 注册额外模板。
- 切换语言后再构造错误对象。
- 新增语言优先复用错误码，不要自造另一套错误码体系。
- 自定义模板时只覆盖需要覆盖的码位，利用 `override` 控制替换策略。

```ts
import {
  setErrorLocale,
  registerErrorLocaleMessages,
  ErrorLocaleMessages
} from '../src/main/ets/errors/ErrorLocale'
import { HookExecutionError } from 'ocorm'

const jaMessages = new ErrorLocaleMessages()
jaMessages.add('ORM601', 'エンティティ "{entityName}" のフック "{operation}" の実行に失敗しました: {details}')
registerErrorLocaleMessages('ja', jaMessages, true)

setErrorLocale('ja')
const error = new HookExecutionError('User', 'beforeSave', 'timeout while loading profile')
console.info(error.message)
```

## 5. 误处理示例
以下行为都不成立：
- 先创建错误，再切语言，期待旧对象的 `message` 自动变化。
- 只注册 `message`，却不给模板所需的 `ErrorTemplateContext` 字段。
- 在业务层直接拼英文/中文字符串，绕过 `ErrorCodes + ErrorLocale`。

```ts
import { setErrorLocale } from '../src/main/ets/errors/ErrorLocale'
import { RequiredValidationError } from 'ocorm'

const error = new RequiredValidationError('User', 'email')
setErrorLocale('en')

// 反例：这里不会变成英文，因为 message 在构造时已经定型
console.info(error.message)
```

## 6. 观测与排障方式
国际化问题排查不要猜。按这个顺序看：
1. 先调用 `getErrorLocale()`，确认当前线程/流程里实际语言值。
2. 再确认错误对象是不是在切换语言之前就已经创建。
3. 若是自定义语言包问题，检查 `registerErrorLocaleMessages(..., override)` 是否覆盖成功。
4. 若模板变量空白，检查 `ErrorTemplateContext` 是否真的填了对应字段。

```ts
import {
  getErrorLocale,
  ErrorLocaleMessages,
  registerErrorLocaleMessages,
  formatErrorMessage,
  ErrorTemplateContext
} from '../src/main/ets/errors/ErrorLocale'

const messages = new ErrorLocaleMessages()
messages.add('ORM803', 'Field {columnName} length must be between {min} and {max}')
registerErrorLocaleMessages('en-debug', messages, true)

const context = new ErrorTemplateContext()
context.columnName = 'nickname'
context.min = 2
context.max = 20

console.info(getErrorLocale())
console.info(formatErrorMessage('ORM803', 'fallback', context))
```

## 7. 与日志和上下文的关系
- `OrmError.message` 是本地化后的展示文本。
- `OrmError.context` 仍然保留结构化字段，适合日志和排障。
- `getFullMessage()` 会把本地化后的 `message` 与 `code/context` 拼接在一起，适合进入 `Logger.logError()`。

```ts
import { setErrorLocale } from '../src/main/ets/errors/ErrorLocale'
import { Logger } from 'ocorm'
import { LogLevel } from 'ocorm'
import { PredicateBuildError } from 'ocorm'

const logger = Logger.getInstance()
logger.configure(true, LogLevel.INFO)

setErrorLocale('en')
const error = new PredicateBuildError('User', 'missing indexed column')
logger.logError(error.getFullMessage())
```

## 8. 代码评审检查项
- 是否先切语言，后创建错误对象。
- 是否复用 `ErrorCodes` 而不是手写非标准错误码。
- 是否给模板需要的 `columnName/min/max/details` 等变量提供了 `ErrorTemplateContext`。
- 是否把国际化展示和结构化排障信息同时保留。

## 9. 常见问题
### 9.1 为什么 `CustomValidationError` 在某些语言下看起来不像模板翻译
因为它把调用方提供的 `message` 直接作为 fallback 文本传进 `ValidationError`。如果没有为 `ORM813` 注册覆盖模板，最终看到的就是调用方的原始文案。

### 9.2 `registerErrorLocaleMessages(..., false)` 有什么意义
它表示只补缺，不覆盖已有模板。适合给现有 `zh/en` 语言包补少量缺失码位，而不是整体替换。

## 10. 变更记录
- 2026-03-27：补全 ErrorLocale 入口、构造期本地化机制、注册策略、误处理与排障说明。

