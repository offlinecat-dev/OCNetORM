/**
 * 装饰器模块统一导出
 */

// 实体装饰器
export { EntityOptions, registerEntity, createEntityOptions, Table } from './EntityDecorator'

// 列装饰器
export {
  ColumnOptions,
  DecoratorColumnOptions,
  PrimaryKeyOptions,
  registerColumn,
  registerPrimaryKey,
  registerAutoIncrementPrimaryKey,
  createColumnOptions,
  Column,
  PrimaryKey,
  CreatedAt,
  UpdatedAt,
  SoftDelete,
  inferColumnType
} from './ColumnDecorator'

// 验证装饰器
export { Required, Length, Email, LengthOptions } from '../validation/ValidationDecorators'
