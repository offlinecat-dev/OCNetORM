# 06-映射-验证与装饰器API

> 状态：已完成
> 适用版本：ocorm 3.0.2
> 最后更新：2026-03-28
> 对照源码：`src/main/ets/mapping/*`、`src/main/ets/validation/*`、`src/main/ets/core/HooksProcessor.ets`、`src/main/ets/decorators/index.ets`

## 1. 覆盖范围

这页覆盖三类支撑能力：

- 映射：`DataMapper`、`ResultSetUtils`、`ViewModelMapper`
- 验证：`ValidationMetadataStorage`、`EntityValidator`、验证装饰器
- 钩子：`HooksProcessor`、全局 hook 注册

深入章节看：

- [`../07-映射与数据转换/02-DataMapper映射流程.md`](../07-映射与数据转换/02-DataMapper映射流程.md)
- [`../08-验证与钩子/03-EntityValidator执行流程.md`](../08-验证与钩子/03-EntityValidator执行流程.md)
- [`../08-验证与钩子/04-HooksProcessor生命周期钩子.md`](../08-验证与钩子/04-HooksProcessor生命周期钩子.md)

## 2. API 快表

| 类/能力 | 代表方法 | 说明 |
| --- | --- | --- |
| `DataMapper` | `toValuesBucket()`、`fromResultSetRow()`、`fromResultSet()` | 实体数据与数据库值之间转换 |
| `DataMapper` | `getPrimaryKeyValue()`、`setPrimaryKeyValue()`、`isNewRecord()` | 主键判断与回填 |
| `ResultSetUtils` | `toRow()`、`toRowArray()`、`safeClose()` | `ResultSet` 转 `ResultSetRow` |
| `ViewModelMapper` | `toPropertyMap()`、`fromPropertyMap()` | ViewModel / 属性图转换 |
| `ValidationMetadataStorage` | `registerRule()`、`getRules()`、`getRulesForProperty()` | 验证规则注册表 |
| `EntityValidator` | `validate()`、`validateOrThrow()` | 执行实体校验 |
| 验证装饰器 | `Required`、`Length`、`Email`、`Min`、`Max`、`Range`、`Pattern`、`Enum` 等 | 类声明式校验 |
| `HooksProcessor` | `registerGlobalHook()`、`clearGlobalHooks()` | 全局生命周期钩子 |

## 3. `DataMapper` 速查

```ts
import { DataMapper } from 'ocorm'

const mapper = new DataMapper('User')
const bucket = mapper.toValuesBucket(user, false)
const entity = mapper.fromResultSetRow(row)
const entities = mapper.fromResultSet(rows)

console.info(mapper.getPrimaryKeyValue(entity))
console.info(mapper.isNewRecord(entity))
```

适用边界：

- 需要仓储内部行为，优先 `Repository`
- 需要独立验证映射、做工具链或测试桩，直接用 `DataMapper`

## 4. `ResultSetUtils` 与原始行模式

`getRaw()` 最终拿到的是 `ResultSetRow[]`。如果你手工接触 `ResultSet`，必须自己负责关闭，`ResultSetUtils.safeClose()` 就是收口点。

```ts
import { DatabaseManager, ResultSetUtils } from 'ocorm'

const store = DatabaseManager.getInstance().getStore()
const resultSet = await store.querySql('SELECT id, user_name FROM users')

try {
  const rows = ResultSetUtils.toRowArray(resultSet, metadata)
  console.info(JSON.stringify(rows))
} finally {
  ResultSetUtils.safeClose(resultSet)
}
```

这块的失败语义和“数据库已关闭”类问题，直接回：

- [`../16-排障与FAQ/02-数据库关闭类问题排查.md`](../16-排障与FAQ/02-数据库关闭类问题排查.md)

## 5. 声明式验证

```ts
import {
  Table,
  Column,
  ColumnType,
  Required,
  Length,
  Email,
  Min,
  Max
} from 'ocorm'

@Table('users')
class User {
  @Column({ name: 'user_name', type: ColumnType.TEXT })
  @Required()
  @Length({ min: 2, max: 32 })
  userName: string = ''

  @Column({ name: 'email', type: ColumnType.TEXT })
  @Email()
  email: string = ''

  @Column({ name: 'age', type: ColumnType.INTEGER, nullable: true })
  @Min(18)
  @Max(120)
  age: number | null = null
}
```

规则注册中心和装饰器最终会汇入 `ValidationMetadataStorage`。

```ts
import {
  EntityValidator,
  ValidationMetadataStorage,
  ValidationError
} from 'ocorm'

const storage = ValidationMetadataStorage.getInstance()
console.info(storage.getRules('User').size)

const result = EntityValidator.validate('User', user)
if (!result.isValid()) {
  throw new ValidationError(result.getSummary())
}
```

## 6. 手工注册规则与抛错路径

```ts
import {
  EntityValidator,
  ValidationMetadataStorage
} from 'ocorm'

ValidationMetadataStorage.getInstance().registerRule('User', 'status', {
  type: 'enum',
  message: 'status invalid',
  options: { values: ['active', 'disabled'] }
})

EntityValidator.validateOrThrow('User', user)
```

规则来源可以混用，但不要把同一条业务规则既写装饰器又手工注册两遍，否则错误信息会重复。

## 7. HooksProcessor 与全局 hook

```ts
import { HooksProcessor, OrmContext } from 'ocorm'

HooksProcessor.getInstance().registerGlobalHook('beforeSave', async (entityName, entityData) => {
  console.info(`beforeSave: ${entityName}`)
})

OrmContext.registerGlobalHook('afterLoad', async (entityName, entityData) => {
  console.info(`afterLoad: ${entityName}`)
})
```

使用原则：

- 实体生命周期逻辑集中在 hook，不要散在每个仓储调用前后
- hook 里只做轻量逻辑，重 I/O 会直接放大保存和查询时延
- 调试顺序与异常传播，看：[`../08-验证与钩子/05-验证与钩子协同顺序.md`](../08-验证与钩子/05-验证与钩子协同顺序.md)

## 8. ViewModel 映射

```ts
import { ViewModelMapper } from 'ocorm'

const propertyMap = ViewModelMapper.toPropertyMap(user)
const rebuilt = ViewModelMapper.fromPropertyMap('User', propertyMap)

console.info(propertyMap.size)
console.info(JSON.stringify(rebuilt))
```

这类 API 适合做表单层、展示层转换；持久化前仍然要回到实体验证和仓储保存链路。

## 9. 继续下钻

- 仓储与事务：[`03-仓储-事务与原生SQLAPI.md`](./03-仓储-事务与原生SQLAPI.md)
- 深度章节：[`../07-映射与数据转换/02-DataMapper映射流程.md`](../07-映射与数据转换/02-DataMapper映射流程.md)、[`../08-验证与钩子/05-验证与钩子协同顺序.md`](../08-验证与钩子/05-验证与钩子协同顺序.md)

## 10. 变更记录

- 2026-03-28：补齐映射、验证、装饰器与 hook API 速查。
