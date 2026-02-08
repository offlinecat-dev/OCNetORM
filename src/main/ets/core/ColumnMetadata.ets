/**
 * 列元数据类
 * 存储单个属性到数据库列的映射信息
 */

import { ColumnType } from '../types/ColumnType'

/**
 * 列元数据
 * 记录实体属性与数据库列之间的映射关系及约束信息
 */
export class ColumnMetadata {
  /** ArkTS 属性名 */
  propertyName: string = ''

  /** 数据库列名 */
  columnName: string = ''

  /** 数据库列类型 */
  columnType: ColumnType = ColumnType.TEXT

  /** 是否为主键 */
  isPrimaryKey: boolean = false

  /** 是否自增 */
  isAutoIncrement: boolean = false

  /** 是否允许为空 */
  isNullable: boolean = true

  /** 是否唯一 */
  isUnique: boolean = false

  /** 默认值 */
  defaultValue: string | number | boolean | null = null

  /** TEXT 类型最大长度，0 表示无限制 */
  length: number = 0

  /**
   * 构造函数
   * @param propertyName ArkTS 属性名
   * @param columnName 数据库列名（可选，默认使用属性名）
   */
  constructor(propertyName: string, columnName?: string) {
    this.propertyName = propertyName
    this.columnName = columnName ? columnName : propertyName
  }

  /**
   * 设置列类型
   * @param type 列类型
   * @returns 当前实例，支持链式调用
   */
  setType(type: ColumnType): ColumnMetadata {
    this.columnType = type
    return this
  }

  /**
   * 设置为主键
   * @param isPrimary 是否为主键
   * @returns 当前实例，支持链式调用
   */
  setPrimaryKey(isPrimary: boolean): ColumnMetadata {
    this.isPrimaryKey = isPrimary
    return this
  }

  /**
   * 设置自增
   * @param isAuto 是否自增
   * @returns 当前实例，支持链式调用
   */
  setAutoIncrement(isAuto: boolean): ColumnMetadata {
    this.isAutoIncrement = isAuto
    return this
  }

  /**
   * 设置是否允许为空
   * @param nullable 是否允许为空
   * @returns 当前实例，支持链式调用
   */
  setNullable(nullable: boolean): ColumnMetadata {
    this.isNullable = nullable
    return this
  }

  /**
   * 设置是否唯一
   * @param unique 是否唯一
   * @returns 当前实例，支持链式调用
   */
  setUnique(unique: boolean): ColumnMetadata {
    this.isUnique = unique
    return this
  }

  /**
   * 设置默认值
   * @param value 默认值
   * @returns 当前实例，支持链式调用
   */
  setDefaultValue(value: string | number | boolean | null): ColumnMetadata {
    this.defaultValue = value
    return this
  }

  /**
   * 设置 TEXT 类型最大长度
   * @param len 最大长度
   * @returns 当前实例，支持链式调用
   */
  setLength(len: number): ColumnMetadata {
    this.length = len
    return this
  }

  /**
   * 创建列元数据的副本
   * @returns 新的 ColumnMetadata 实例
   */
  clone(): ColumnMetadata {
    const copy = new ColumnMetadata(this.propertyName, this.columnName)
    copy.columnType = this.columnType
    copy.isPrimaryKey = this.isPrimaryKey
    copy.isAutoIncrement = this.isAutoIncrement
    copy.isNullable = this.isNullable
    copy.isUnique = this.isUnique
    copy.defaultValue = this.defaultValue
    copy.length = this.length
    return copy
  }
}
