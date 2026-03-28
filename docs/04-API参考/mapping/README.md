# Mapping API 契约

实现依据：`src/main/ets/mapping/*.ets`

## `DataMapper`

- 用途：在 `EntityData` 与数据库行（`ResultSetRow` / `ValuesBucket`）之间转换。
- 参数：
  - 构造：`new DataMapper(entityName)`
  - `toValuesBucket(entityData, includeAutoIncrement?)`
  - `fromResultSetRow(row)`
  - `fromResultSet(rows)`
- 返回：
  - `ValuesBucket` / `EntityData` / `EntityData[]`
- 异常：
  - 实体未注册：`EntityMappingError`
  - 非空列缺失值：`NullValueError`
  - 类型转换失败可能来自 `TypeConverter`（`TypeConversionError`）
- 副作用：
  - `toValuesBucket` 会按列定义写入默认值与类型转换后的值
- 事务上下文：无（纯映射逻辑，不访问数据库）。
- 最小示例：

```ts
import { DataMapper } from 'ocorm'

const mapper = new DataMapper('User')
const bucket = mapper.toValuesBucket(entityData)
```

## `TypeConverter.toDbValue(...)`

- 用途：将 ArkTS 值转换为数据库值（`TEXT/INTEGER/REAL/BLOB`）。
- 参数：
  - `value: ValueType`
  - `columnType: ColumnType`
  - `propertyType: string`
  - `options?: { strict?: boolean, fallbackValue?: ValueType }`
  - `columnName?: string`
- 返回：`DbValueType`
- 异常：
  - 默认严格模式下，非法转换抛 `TypeConversionError`
  - `strict=false` 时返回 fallback 或 `null`
- 副作用：无。
- 事务上下文：无。
- 最小示例：

```ts
import { TypeConverter, ColumnType } from 'ocorm'

const dbValue = TypeConverter.toDbValue(new Date(), ColumnType.INTEGER, 'Date')
```

## `TypeConverter.fromDbValue(...)`

- 用途：将数据库值还原为业务值。
- 参数：
  - `value: DbValueType`
  - `propertyType: string`
  - `columnName: string`
  - `options?: TypeConversionOptions`
- 返回：`ValueType`
- 异常：
  - 默认严格模式下类型不匹配抛 `TypeConversionError`
- 副作用：无。
- 事务上下文：无。
- 最小示例：

```ts
const value = TypeConverter.fromDbValue(1, 'boolean', 'is_active')
```

## `ViewModelMapper`

- 用途：`EntityData` 与 ViewModel 双向映射（不依赖 Reflect）。
- 参数：
  - `toViewModelWithConfig(entityData, config)`
  - `toEntityDataWithConfig(viewModel, config)`
  - `toViewModel/toEntityData`（回调简化版）
- 返回：ViewModel 或 `EntityData`
- 异常：
  - 缺少工厂函数：`EntityMappingError`
  - 缺少 reverse mapper：`EntityMappingError`
- 副作用：无。
- 事务上下文：无。
- 最小示例：

```ts
import { ViewModelMapper, ViewModelMappingConfig } from 'ocorm'

const config = new ViewModelMappingConfig('User', () => ({ id: 0, name: '' }))
  .addMapper((entity, vm) => {
    vm.id = Number(entity.getPropertyValue('id') ?? 0)
    vm.name = String(entity.getPropertyValue('name') ?? '')
  })

const vm = ViewModelMapper.toViewModelWithConfig(entityData, config)
```
