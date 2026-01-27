/**
 * 列装饰器
 * 用于标注实体属性，将属性映射到数据库列
 */

import { MetadataStorage } from '../core/MetadataStorage'
import { EntityNotRegisteredError } from '../errors/MetadataError'
import { ColumnMetadata } from '../core/ColumnMetadata'
import { ColumnType } from '../types/ColumnType'

/**
 * 列装饰器配置选项
 */
export class ColumnOptions {
  /** 数据库列名，可选，默认使用属性名 */
  name: string = ''
  /** 列类型，可选，默认为 TEXT */
  type: ColumnType = ColumnType.TEXT
  /** 是否允许为空，默认 true */
  nullable: boolean = true
  /** 是否唯一，默认 false */
  unique: boolean = false
  /** 默认值 */
  defaultValue: string | number | null = null
  /** TEXT 类型最大长度，0 表示无限制 */
  length: number = 0

  constructor() {
  }
}

/**
 * 装饰器列选项（支持部分字段）
 */
export interface DecoratorColumnOptions {
  name?: string
  type?: ColumnType
  nullable?: boolean
  unique?: boolean
  defaultValue?: string | number | null
  length?: number
}

/**
 * 主键装饰器选项
 */
export interface PrimaryKeyOptions {
  /** 数据库列名 */
  name?: string
  /** 是否自增，默认 true */
  autoIncrement?: boolean
}

/**
 * ArkTS 不支持 Symbol，用字符串属性名限定装饰器签名
 */
export type StringPropertyDecorator = (target: Object, propertyKey: string) => void

function ensureEntityRegistered(entityName: string): void {
  const storage = MetadataStorage.getInstance()
  if (!storage.hasEntity(entityName)) {
    throw new EntityNotRegisteredError(entityName)
  }
}

/**
 * 应用列选项（仅覆盖已定义字段）
 */
function applyColumnOptions(target: ColumnOptions, options?: DecoratorColumnOptions): ColumnOptions {
  if (!options) {
    return target
  }
  if (options.name !== undefined) {
    target.name = options.name
  }
  if (options.type !== undefined) {
    target.type = options.type
  }
  if (options.nullable !== undefined) {
    target.nullable = options.nullable
  }
  if (options.unique !== undefined) {
    target.unique = options.unique
  }
  if (options.defaultValue !== undefined) {
    target.defaultValue = options.defaultValue
  }
  if (options.length !== undefined) {
    target.length = options.length
  }
  return target
}

/**
 * 注册列元数据
 * @param entityName 实体类名
 * @param propertyName 属性名
 * @param options 列配置选项
 * @throws EntityNotRegisteredError 如果实体未注册
 */
export function registerColumn(entityName: string, propertyName: string, options?: ColumnOptions): void {
  const storage = MetadataStorage.getInstance()

  ensureEntityRegistered(entityName)
  
  // 创建列元数据
  const columnName = options && options.name ? options.name : propertyName
  const column = new ColumnMetadata(propertyName, columnName)
  
  // 设置列属性
  if (options) {
    column.setType(options.type)
    column.setNullable(options.nullable)
    column.setUnique(options.unique)
    column.setDefaultValue(options.defaultValue)
    column.setLength(options.length)
  }
  
  storage.registerColumn(entityName, column)
}

/**
 * 注册主键列
 * @param entityName 实体类名
 * @param propertyName 属性名
 * @param columnName 列名（可选）
 * @throws EntityNotRegisteredError 如果实体未注册
 */
export function registerPrimaryKey(entityName: string, propertyName: string, columnName?: string): void {
  const storage = MetadataStorage.getInstance()

  ensureEntityRegistered(entityName)
  
  // 创建主键列元数据
  const actualColumnName = columnName ? columnName : propertyName
  const column = new ColumnMetadata(propertyName, actualColumnName)
  column.setPrimaryKey(true)
  column.setType(ColumnType.INTEGER)
  column.setNullable(false)

  storage.registerColumn(entityName, column)
}

/**
 * 注册自增主键列
 * @param entityName 实体类名
 * @param propertyName 属性名
 * @param columnName 列名（可选）
 * @throws EntityNotRegisteredError 如果实体未注册
 */
export function registerAutoIncrementPrimaryKey(entityName: string, propertyName: string, columnName?: string): void {
  const storage = MetadataStorage.getInstance()

  ensureEntityRegistered(entityName)
  
  // 创建自增主键列元数据
  const actualColumnName = columnName ? columnName : propertyName
  const column = new ColumnMetadata(propertyName, actualColumnName)
  column.setPrimaryKey(true)
  column.setAutoIncrement(true)
  column.setType(ColumnType.INTEGER)
  column.setNullable(false)

  storage.registerColumn(entityName, column)
}

/**
 * 创建列配置选项
 * @returns ColumnOptions 实例
 */
export function createColumnOptions(): ColumnOptions {
  return new ColumnOptions()
}

/**
 * 属性装饰器：列映射
 * @param options 列配置选项
 */
export function Column(options?: DecoratorColumnOptions): StringPropertyDecorator {
  return (target: Object, propertyKey: string) => {
    const entityName = target.constructor.name
    const propertyName = propertyKey
    const columnOptions = applyColumnOptions(createColumnOptions(), options)
    registerColumn(entityName, propertyName, columnOptions)
  }
}

/**
 * 属性装饰器：主键
 * 默认使用自增主键
 * @param options 主键选项
 */
export function PrimaryKey(options?: PrimaryKeyOptions): StringPropertyDecorator {
  return (target: Object, propertyKey: string) => {
    const entityName = target.constructor.name
    const propertyName = propertyKey
    const autoIncrement = options?.autoIncrement !== undefined ? options.autoIncrement : true
    if (autoIncrement) {
      registerAutoIncrementPrimaryKey(entityName, propertyName, options?.name)
    } else {
      registerPrimaryKey(entityName, propertyName, options?.name)
    }
  }
}

/**
 * 属性装饰器：创建时间
 * 默认列名 created_at，类型 INTEGER
 * @param options 列配置选项
 */
export function CreatedAt(options?: DecoratorColumnOptions): StringPropertyDecorator {
  return (target: Object, propertyKey: string) => {
    const entityName = target.constructor.name
    const propertyName = propertyKey
    const columnOptions = createColumnOptions()
    columnOptions.name = 'created_at'
    columnOptions.type = ColumnType.INTEGER
    columnOptions.nullable = false
    applyColumnOptions(columnOptions, options)
    registerColumn(entityName, propertyName, columnOptions)
  }
}

/**
 * 属性装饰器：更新时间
 * 默认列名 updated_at，类型 INTEGER
 * @param options 列配置选项
 */
export function UpdatedAt(options?: DecoratorColumnOptions): StringPropertyDecorator {
  return (target: Object, propertyKey: string) => {
    const entityName = target.constructor.name
    const propertyName = propertyKey
    const columnOptions = createColumnOptions()
    columnOptions.name = 'updated_at'
    columnOptions.type = ColumnType.INTEGER
    columnOptions.nullable = false
    applyColumnOptions(columnOptions, options)
    registerColumn(entityName, propertyName, columnOptions)
  }
}

/**
 * 属性装饰器：软删除时间戳
 * 默认列名 deleted_at，类型 INTEGER
 * @param options 列配置选项
 */
export function SoftDelete(options?: DecoratorColumnOptions): StringPropertyDecorator {
  return (target: Object, propertyKey: string) => {
    const entityName = target.constructor.name
    const propertyName = propertyKey
    const columnOptions = createColumnOptions()
    columnOptions.name = 'deleted_at'
    columnOptions.type = ColumnType.INTEGER
    columnOptions.nullable = true
    applyColumnOptions(columnOptions, options)
    registerColumn(entityName, propertyName, columnOptions)
    const metadata = MetadataStorage.getInstance().getEntityMetadata(entityName)
    if (metadata !== null) {
      const deletedAtColumn = columnOptions.name ? columnOptions.name : 'deleted_at'
      metadata.setSoftDelete(true, deletedAtColumn)
    }
  }
}

/**
 * 根据 ArkTS 类型推断数据库列类型
 * @param typeName 类型名称
 * @returns 对应的数据库列类型
 */
export function inferColumnType(typeName: string): ColumnType {
  switch (typeName) {
    case 'string':
      return ColumnType.TEXT
    case 'number':
      return ColumnType.REAL
    case 'boolean':
      return ColumnType.INTEGER
    case 'Date':
      return ColumnType.INTEGER
    default:
      // 对象类型序列化为 JSON 文本
      return ColumnType.TEXT
  }
}
