# 04-ResultSetRow与ResultSetUtils

> 状态：完成
> 适用版本：ocorm 3.x（当前仓库实现）
> 最后更新：2026-03-27

## 1. 目标
本文定义 `ResultSetRow` 与 `ResultSetUtils` 的真实边界：
- `ResultSetRow` 是轻量级列值容器，不做类型推断。
- `ResultSetUtils` 负责从 `ResultSet` 读取当前行、整批行或单列值。
- 这套工具以“容错 + 记录日志 + 返回 `null/部分结果`”为主，不以抛异常为主。

## 2. ResultSetRow 的职责
`ResultSetRow` 只有 4 个公开方法：
- `set(columnName, value)`：写入列值。
- `get(columnName)`：读取列值；列不存在时返回 `null`。
- `has(columnName)`：判断列名是否存在。
- `getColumnNames()`：获取当前已写入的全部列名。

正确用法是把它当成“当前查询行的原始列快照”，而不是实体对象。

```ts
import { ResultSetRow } from 'ocorm'

const row = new ResultSetRow()
row.set('id', 7)
row.set('name', 'Alice')
row.set('avatar_blob', null)

const id = row.get('id')
const hasName = row.has('name')
const columns = row.getColumnNames()
```

## 3. ResultSetUtils 的核心方法
`ResultSetUtils` 是纯静态工具类，常用入口如下：
- `toRow(resultSet, metadata)`：把当前游标所在行转成一个 `ResultSetRow`
- `toRowArray(resultSet, metadata)`：从当前游标位置开始，循环 `goToNextRow()` 直到结束
- `getColumnValues(resultSet, columnName, metadata?)`：读取单列的全部值
- `getValueByType(resultSet, columnIndex, columnType)`：按声明类型读取单个值
- `getValueByRuntimeType(resultSet, columnIndex)`：无元数据时按运行时列类型读取
- `safeClose(resultSet)`：安全关闭结果集

```ts
import { ResultSetUtils } from 'ocorm'

// resultSet: 当前 relationalStore.ResultSet
// metadata: 当前实体的元数据
const currentRow = ResultSetUtils.toRow(resultSet, metadata)
const rows = ResultSetUtils.toRowArray(resultSet, metadata)
const ids = ResultSetUtils.getColumnValues(resultSet, 'id', metadata)
```

当有元数据时，`toRow(...)` 和 `getColumnValues(...)` 优先使用列声明类型；没有元数据时，`getColumnValues(...)` 会退回到 `getValueByRuntimeType(...)`。

```ts
import { ResultSetUtils } from 'ocorm'

// 无 metadata 时按运行时类型读取
const names = ResultSetUtils.getColumnValues(resultSet, 'name')

// 已知列索引时，可以直接按类型读取
const value = ResultSetUtils.getValueByType(resultSet, 0, 'INTEGER')
const runtimeValue = ResultSetUtils.getValueByRuntimeType(resultSet, 0)
```

## 4. 误用示例
误用 1：用 `get()` 判断列是否存在。`ResultSetRow.get(...)` 对“缺列”和“列值就是 null”都返回 `null`，必须配合 `has(...)` 区分。

```ts
import { ResultSetRow } from 'ocorm'

const row = new ResultSetRow()
row.set('nickname', null)

const nickname = row.get('nickname') // null
const missing = row.get('missing')   // 也是 null

const hasNickname = row.has('nickname') // true
const hasMissing = row.has('missing')   // false
```

误用 2：在同一个 `resultSet` 上先调用 `getColumnValues(...)`，再直接调用 `toRowArray(...)`，却期望还能读到完整结果。当前实现会持续推进游标，不会自动重置。

```ts
import { ResultSetUtils } from 'ocorm'

const ids = ResultSetUtils.getColumnValues(resultSet, 'id', metadata)
// 到这里，resultSet 通常已经被推进到尾部

const rows = ResultSetUtils.toRowArray(resultSet, metadata)
// 常见结果：rows 为空，或只包含剩余行
```

误用 3：期望 `getColumnValues(...)` 把 `null` 列值也塞进结果数组。当前实现会跳过 `isColumnNull(...) === true` 的项。

## 5. 失败与异常语义
`ResultSetUtils` 的设计不是“抛错即停”，而是“尽量继续”：
- `toRow(...)`：单列读取失败时，把该列置为 `null`，并且整行处理继续；只记录一次 warn 日志。
- `getValueByType(...)`：读取失败时直接返回 `null`。
- `toRowArray(...)`：遍历中途失败时返回已经累积的行，并记 warn 日志。
- `getColumnValues(...)`：读取失败时返回已经累积的值，并记 warn 日志。
- `getValueByRuntimeType(...)`：运行时类型读取失败时返回 `null`。
- `safeClose(...)`：关闭失败时吞掉异常，不向外抛出。

```ts
import { ResultSetUtils } from 'ocorm'

const badIndexValue = ResultSetUtils.getValueByType(resultSet, 999, 'TEXT')
// 读取失败时直接得到 null

const runtimeValue = ResultSetUtils.getValueByRuntimeType(resultSet, 999)
// 同样返回 null

ResultSetUtils.safeClose(resultSet)
ResultSetUtils.safeClose(null)
// 两次调用都不会向外抛异常
```

```ts
import { ResultSetUtils } from 'ocorm'
import { ResultSetRow } from 'ocorm'

const row: ResultSetRow = ResultSetUtils.toRow(resultSet, metadata)
const maybeNull = row.get('broken_column')
// 如果该列读取时出错，toRow(...) 会把 broken_column 写成 null
```

这里需要特别强调：`ResultSetUtils` 不会抛 `MappingError`、`TypeConversionError` 或 `EntityMappingError`。它只负责把底层读值错误吞掉并降级成 `null` 或部分结果，真正的映射异常通常在 `DataMapper` / `TypeConverter` 层才会出现。

## 6. 读取规则细节
- `toRow(...)` 使用 `resultSet.columnNames` 遍历列名，再用 `resultSet.getColumnIndex(columnName)` 找索引。
- 若元数据中找不到对应列，`toRow(...)` 默认调用 `resultSet.getString(columnIndex)`。
- `getValueByType(...)` 支持 `INTEGER / REAL / TEXT / BLOB` 及其字符串字面量。
- `getValueByRuntimeType(...)` 会检查 `resultSet.getColumnTypeSync(columnIndex)`，其中数字列若读出来是 `NaN`，会退回 `getString(...)`。
- `getColumnValues(...)` 只收集非空列值，不会把 `null` 放进返回数组。

## 7. 验收清单
- 已覆盖 `ResultSetRow.get(...)` 与 `has(...)` 的差异。
- 已覆盖 `toRow(...)`、`toRowArray(...)`、`getColumnValues(...)` 的游标推进语义。
- 已覆盖单列失败、整批遍历失败、关闭失败时的真实降级行为。
- 已明确说明 `ResultSetUtils` 不抛 `MappingError` 体系异常。

## 8. 变更记录
- 2026-03-27：补全 `ResultSetRow` / `ResultSetUtils` 用法、误用示例与失败语义。


