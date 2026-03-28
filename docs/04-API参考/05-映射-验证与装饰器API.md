# 05-映射-验证与装饰器API

## 何时使用
- 需要把数据库行映射为实体：`EntityData`、`DataMapper`、`ResultSetRow`
- 需要声明式验证：`Required/Length/Email/...` + `EntityValidator`
- 需要声明实体和列元数据：`Table/Column/PrimaryKey/...`

## 最小示例
```ts
import {
  Column,
  ColumnType,
  Email,
  EntityValidator,
  Length,
  PrimaryKey,
  Required,
  Table
} from 'ocorm'

@Table('users')
class User {
  @PrimaryKey({ autoIncrement: true })
  id: number = 0

  @Column({ type: ColumnType.TEXT })
  @Required()
  @Length({ min: 2, max: 20 })
  name: string = ''

  @Column({ type: ColumnType.TEXT })
  @Email()
  email: string = ''
}

const result = EntityValidator.validate('User', entityData)
if (!result.isValid()) {
  console.error(result.getSummary())
}
```

## 行为契约
- 验证执行入口：`EntityValidator.validate/validateOrThrow`
- 多字段失败时：`validateOrThrow` 抛 `EntityValidationError`
- 装饰器注册要求：实体需已注册，装饰器元数据才能正确挂载
- 映射失败时：统一走 `MappingError` 系列

## 常见误用
- 误用不存在的聚合导出：`ValidationDecorators`（当前公共 API 不导出该符号）
- 未注册实体就先执行装饰器/校验
- 只加 `Email/Length` 但没有 `Required`，导致空值被跳过

## 源码对齐路径
- `src/main/ets/decorators/index.ets`
- `src/main/ets/validation/index.ets`
- `src/main/ets/mapping/index.ets`
- `Index.ets`
