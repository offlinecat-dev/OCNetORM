# 03-TypeConverter严格与宽松模式

> 状态：完成
> 适用版本：ocorm 3.x（当前仓库实现）
> 最后更新：2026-03-27

## 1. 目标
本文说明 `TypeConverter` 的真实转换边界，重点是：
- `strict` 默认开启，只有显式传入 `strict: false` 才进入宽松模式。
- 并不是所有不匹配都会抛错，部分分支会直接返回 `null`。
- `Date`、`object`、`blob` 的语义与直觉不完全一致，必须单独记住。

## 2. 核心规则
`TypeConverter` 提供两类能力：
- 基础工具：`dateToTimestamp`、`timestampToDate`、`booleanToInt`、`intToBoolean`、`objectToJson`、`jsonToObject`
- 数据库双向转换：`toDbValue(...)` 与 `fromDbValue(...)`

严格与宽松模式只体现在 `toDbValue(...)` / `fromDbValue(...)`：
- 未传 `options`，或 `options.strict !== false`：严格模式。
- 传入 `strict: false`：宽松模式。
- `fallbackValue` 仅在宽松模式下生效。

## 3. 正确示例
基础工具方法没有隐式副作用，行为非常直接。

```ts
import { TypeConverter } from 'ocorm'

const timestamp = TypeConverter.dateToTimestamp(new Date(1710000000000))
const date = TypeConverter.timestampToDate(timestamp)

const one = TypeConverter.booleanToInt(true)   // 1
const zero = TypeConverter.booleanToInt(false) // 0
const enabled = TypeConverter.intToBoolean(1)  // true
const disabled = TypeConverter.intToBoolean(0) // false
```

`object` 相关方法只负责 JSON 序列化与反序列化，不会参与数据库列类型判断。

```ts
import { TypeConverter } from 'ocorm'
import { ColumnType } from 'ocorm'

const json = TypeConverter.objectToJson({ id: 1, name: 'Alice' })
const parsed = TypeConverter.jsonToObject(json)

const objectDbValue = TypeConverter.toDbValue(
  { id: 1, name: 'Alice' },
  ColumnType.TEXT,
  'object',
  undefined,
  'profile'
)
```

严格模式下，兼容转换会正常通过；不兼容则直接失败。

```ts
import { TypeConverter } from 'ocorm'
import { TypeConversionError } from 'ocorm'
import { ColumnType } from 'ocorm'

const age = TypeConverter.fromDbValue('18', 'number', 'age')
const createdAtTimestamp = TypeConverter.fromDbValue(1710000000000, 'Date', 'created_at')
const activeFlag = TypeConverter.toDbValue(true, ColumnType.INTEGER, 'boolean', undefined, 'is_active')

try {
  TypeConverter.fromDbValue('abc', 'number', 'age')
} catch (e) {
  if (e instanceof TypeConversionError) {
    // 严格模式下字符串无法解析成 number 时直接抛错
  }
}
```

## 4. 宽松模式
宽松模式只有一条开关：`options.strict === false`。
- `fromDbValue(...)` 宽松模式下，失败时优先返回 `fallbackValue`，否则返回 `null`。
- `toDbValue(...)` 宽松模式下，失败时走 `toDbFallback(...)`：
  - `fallbackValue` 是 `string` 或 `number`：原样返回
  - `fallbackValue` 是 `boolean`：会先转成 `0/1`
  - `fallbackValue` 是 `Uint8Array`：原样返回
  - 其他类型：返回 `null`

```ts
import { TypeConverter } from 'ocorm'
import { ColumnType } from 'ocorm'

const nullableAge = TypeConverter.fromDbValue('abc', 'number', 'age', { strict: false })
// null

const fallbackAge = TypeConverter.fromDbValue('abc', 'number', 'age', {
  strict: false,
  fallbackValue: 0
})
// 0

const fallbackDbValue = TypeConverter.toDbValue('bad-date', ColumnType.INTEGER, 'Date', {
  strict: false,
  fallbackValue: 0
}, 'created_at')
// 0
```

## 5. 误用示例
误用 1：把 `fromDbValue(..., 'Date', ...)` 当成 `Date` 构造器。当前实现不会返回 `Date`，只返回时间戳 `number`。

```ts
import { TypeConverter } from 'ocorm'

const raw = TypeConverter.fromDbValue(1710000000000, 'Date', 'created_at')
// raw 的真实值是 number，不是 Date

const date = TypeConverter.timestampToDate(raw as number)
```

误用 2：把 `fromDbValue(..., 'object', ...)` 当成自动 JSON 解析器。当前实现遇到字符串时直接返回原字符串，由调用方自行决定是否 `jsonToObject(...)`。

```ts
import { TypeConverter } from 'ocorm'

const rawObject = TypeConverter.fromDbValue('{"id":1}', 'object', 'profile')
// rawObject 的真实值是 string: '{"id":1}'

const parsed = TypeConverter.jsonToObject(rawObject as string)
```

误用 3：假设 `BLOB` 分支总会抛异常。事实不是。`toDbValue(...)` 的 `ColumnType.BLOB` 分支对不支持的类型直接返回 `null`。

```ts
import { TypeConverter } from 'ocorm'
import { ColumnType } from 'ocorm'

const blobValue = TypeConverter.toDbValue({ x: 1 }, ColumnType.BLOB, 'object', undefined, 'payload')
// 真实结果是 null，不会抛 TypeConversionError
```

## 6. 转换失败与异常语义
真正会抛 `TypeConversionError` 的路径，集中在这两组私有分支：
- `handleToDbConversionError(...)`
- `handleConversionError(...)`

```ts
import { TypeConverter } from 'ocorm'
import { TypeConversionError } from 'ocorm'
import { ColumnType } from 'ocorm'

try {
  TypeConverter.toDbValue('not-a-number', ColumnType.INTEGER, 'number', undefined, 'score')
} catch (e) {
  if (e instanceof TypeConversionError) {
    // sourceType: string
    // targetType: INTEGER(number)
    // columnName: score
  }
}

try {
  TypeConverter.fromDbValue(true, 'string', 'nickname')
} catch (e) {
  if (e instanceof TypeConversionError) {
    // boolean -> string 在严格模式下会抛错
  }
}
```

需要特别记住的失败语义：
- `value === null` 时，`toDbValue(...)` 与 `fromDbValue(...)` 都直接返回 `null`，与 strict 无关。
- `propertyType === 'Date'` 时，`toDbValue(...)` 只接受 `Date` 或有效 `number` 时间戳。
- `propertyType === 'boolean'` 时，`fromDbValue(...)` 只接受 `number`；`string` 不会自动解析为布尔值。
- `propertyType === 'object'` 时，`fromDbValue(...)` 遇到字符串会直接返回字符串，不会自动反序列化。
- `propertyType === 'Uint8Array' | 'blob' | 'BLOB'` 时，`fromDbValue(...)` 对不匹配类型直接返回 `null`，不是抛异常。
- 未知 `propertyType` 走 default 分支，只会原样返回 `string/number`，其余返回 `null`。

## 7. 验收清单
- 已覆盖 strict 默认开启、`strict: false` 才宽松的规则。
- 已覆盖 `fallbackValue` 在 `toDbValue(...)` 与 `fromDbValue(...)` 中的实际行为。
- 已明确 `Date` 返回时间戳、`object` 返回原始字符串、`BLOB` 某些分支静默返回 `null`。
- 已覆盖 `TypeConversionError` 的触发条件与不会触发的例外分支。

## 8. 变更记录
- 2026-03-27：补全 `TypeConverter` 严格/宽松模式、误用示例与异常语义。




