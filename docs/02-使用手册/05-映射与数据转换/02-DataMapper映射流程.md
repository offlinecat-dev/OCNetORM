# 02-DataMapper映射流程

> 状态：完成
> 适用版本：ocorm 3.x（当前仓库实现）
> 最后更新：2026-03-27

## 1. 目标
本文说明 `DataMapper` 在当前仓库中的真实职责：
- 将 `EntityData` 转为数据库写入值。
- 将 `ResultSetRow` 转回 `EntityData`。
- 统一主键读取、新记录判断，以及映射阶段的异常语义。

## 2. 前置条件
- `new DataMapper(entityName)` 构造阶段会立即读取实体元数据；实体未注册时，构造函数直接抛 `EntityMappingError`。
- 下列示例默认 `User` 元数据已经注册，且元数据中定义了 `id`、`name`、`created_at`、`is_active` 等列。
- `DataMapper` 只按照元数据中的列清单工作，不会把 `EntityData` 或 `ResultSetRow` 里的额外字段自动映射出去。

## 3. 写入流程：`EntityData -> toValuesBucket()`
`toValuesBucket(entityData, includeAutoIncrement = false)` 的执行顺序非常固定：
1. 遍历实体元数据中的全部列。
2. 默认跳过自增主键；只有 `includeAutoIncrement = true` 才写入自增列。
3. 取值优先级是 `getProperty()` 对应的 `properties` 数组，其次才是 `hasProperty()/getPropertyValue()` 对应的 `propertyMap`。
4. 属性完全缺失时：
   - 非空列且无默认值：抛 `NullValueError`。
   - 有默认值：先用 `TypeConverter.toDbValue(...)` 转换默认值后写入。
   - 可空且无默认值：写入 `null`。
5. 属性存在时，交给 `TypeConverter.toDbValue(...)` 做类型转换。
6. 转换后的数据库值如果是 `null`，且列不可空，最终仍抛 `NullValueError`。

```ts
import { DataMapper } from 'ocorm'
import { EntityData } from 'ocorm'

const entity = new EntityData('User')
entity.addProperty('name', 'Alice', 'string')
entity.addProperty('createdAt', new Date(1710000000000), 'Date')
entity.addProperty('isActive', true, 'boolean')

const mapper = new DataMapper('User')
const bucket = mapper.toValuesBucket(entity)

const isNew = mapper.isNewRecord(entity) // true：主键缺失时视为新记录
mapper.setPrimaryKeyValue(entity, 7)
const pk = mapper.getPrimaryKeyValue(entity) // 7
```

## 4. 读取流程：`ResultSetRow -> fromResultSetRow()`
`fromResultSetRow(row)` 的行为也有明确边界：
- 它读取的是 `row.get(column.columnName)`，也就是数据库列名，不是属性名。
- 属性类型不是由 `ResultSetRow` 决定，而是由元数据列类型和命名规则推断：
  - `TEXT -> string`
  - `REAL -> number`
  - `INTEGER -> number / Date / boolean`，其中 `Date` 与 `boolean` 依赖列名、属性名、默认值和校验规则推断
- 当推断出的属性类型是 `Date` 时，`TypeConverter.fromDbValue(...)` 先返回时间戳数字，`DataMapper` 再补一次 `timestampToDate(...)`。
- 当数据库值为 `null` 且列不可空但配置了默认值时，读取阶段会直接回填默认值。

```ts
import { DataMapper } from 'ocorm'
import { ResultSetRow } from 'ocorm'

const row = new ResultSetRow()
row.set('id', 7)
row.set('name', 'Alice')
row.set('created_at', 1710000000000)
row.set('is_active', 1)

const mapper = new DataMapper('User')
const entity = mapper.fromResultSetRow(row)

const id = entity.getPropertyValue('id')
const name = entity.getPropertyValue('name')
const createdAt = entity.getPropertyValue('createdAt')
const isActive = entity.getPropertyValue('isActive')
```

`fromResultSet(rows)` 只是对 `fromResultSetRow(row)` 的简单循环包装，不额外增加转换逻辑。

## 5. 误用示例
最常见的误用是把 `DataMapper` 当成“无元数据的通用映射器”。这不成立。构造函数就会拦截。

```ts
import { DataMapper } from 'ocorm'
import { EntityMappingError } from 'ocorm'

try {
  new DataMapper('NotRegisteredEntity')
} catch (e) {
  if (e instanceof EntityMappingError) {
    // e.message: 实体 "NotRegisteredEntity" 映射失败: 实体未注册
  }
}
```

另一个常见误判是认为读取 `Date` 列时可以直接接受字符串时间。当前实现不会自动解析 ISO 字符串；`Date` 列只接受数值时间戳。

## 6. 转换失败与异常语义
`DataMapper` 本身不做“温和降级”，大部分失败都直接交给 `MappingError` 体系。

```ts
import { DataMapper } from 'ocorm'
import { EntityData } from 'ocorm'
import { NullValueError, TypeConversionError } from 'ocorm'

const mapper = new DataMapper('User')

const invalid = new EntityData('User')
invalid.addProperty('name', 'Alice', 'string')
invalid.addProperty('createdAt', 'not-a-timestamp', 'Date')

try {
  mapper.toValuesBucket(invalid)
} catch (e) {
  if (e instanceof TypeConversionError) {
    // Date 属性写入数据库时只接受 Date 或 number 时间戳
  }
}

const missingRequired = new EntityData('User')
try {
  mapper.toValuesBucket(missingRequired)
} catch (e) {
  if (e instanceof NullValueError) {
    // 非空列缺失且没有默认值时抛出
  }
}
```

```ts
import { DataMapper } from 'ocorm'
import { ResultSetRow } from 'ocorm'
import { TypeConversionError } from 'ocorm'

const row = new ResultSetRow()
row.set('created_at', '2026-03-27T12:00:00Z')

try {
  new DataMapper('User').fromResultSetRow(row)
} catch (e) {
  if (e instanceof TypeConversionError) {
    // Date 属性从数据库反向映射时只接受 number 时间戳
  }
}
```

实际语义需要特别记住这 4 条：
- `new DataMapper(entityName)`：实体未注册时抛 `EntityMappingError`。
- `toValuesBucket(...)`：字段缺失或转换后为 `null` 且列不可空时抛 `NullValueError`。
- `toValuesBucket(...)` / `fromResultSetRow(...)`：类型不兼容时抛 `TypeConversionError`。
- `fromResultSetRow(...)`：当数据库值为 `null`、列不可空、且默认值也为 `null` 时，不会补抛 `NullValueError`；当前实现会把该属性以 `null` 写入 `EntityData`。

## 7. 主键与新记录判定
- `getPrimaryKeyValue(entityData)`：优先从 `properties` 读主键，找不到再回退到 `getPropertyValue()`。
- `setPrimaryKeyValue(entityData, value)`：有主键列定义时会同步更新 `properties` 与 `propertyMap`；没有主键列定义时抛 `EntityMappingError`。
- `isNewRecord(entityData)`：主键为 `null` 或数字 `0` 时返回 `true`，其他情况返回 `false`。

## 8. 验收清单
- 已验证 `toValuesBucket()` 的取值优先级与默认值补齐逻辑。
- 已覆盖 `EntityMappingError`、`NullValueError`、`TypeConversionError` 的触发路径。
- 已注明 `fromResultSetRow()` 对 `Date` 的真实行为是“时间戳 -> Date”，不是“字符串 -> Date”。
- 已注明读取阶段对“非空但读到 null”并不会再次补抛 `NullValueError`。

## 9. 变更记录
- 2026-03-27：补全 `DataMapper` 映射流程、误用示例与异常语义。



