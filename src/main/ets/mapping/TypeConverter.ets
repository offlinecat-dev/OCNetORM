/**
 * 类型转换器
 * 处理 ArkTS 类型与数据库类型之间的双向转换
 */

import { ColumnType } from '../types/ColumnType'
import { ValueType, DbValueType } from '../types/ValueTypes'
import { TypeConversionError } from '../errors/MappingError'

export interface TypeConversionOptions {
  strict?: boolean
  fallbackValue?: ValueType
}

/**
 * 类型转换器类
 * 提供 ArkTS 类型与数据库类型之间的转换方法
 */
export class TypeConverter {
  /**
   * Date 转换为时间戳（毫秒）
   * @param date Date 对象
   * @returns Unix 时间戳（毫秒）
   */
  static dateToTimestamp(date: Date): number {
    return date.getTime()
  }

  /**
   * 时间戳转换为 Date
   * @param timestamp Unix 时间戳（毫秒）
   * @returns Date 对象
   */
  static timestampToDate(timestamp: number): Date {
    return new Date(timestamp)
  }

  /**
   * boolean 转换为整数
   * @param value boolean 值
   * @returns 1 表示 true，0 表示 false
   */
  static booleanToInt(value: boolean): number {
    return value ? 1 : 0
  }

  /**
   * 整数转换为 boolean
   * @param value 整数值
   * @returns true 如果值不为 0，否则 false
   */
  static intToBoolean(value: number): boolean {
    return value !== 0
  }

  /**
   * 对象转换为 JSON 字符串
   * @param obj 要序列化的对象
   * @returns JSON 字符串
   */
  static objectToJson(obj: object): string {
    return JSON.stringify(obj)
  }

  /**
   * JSON 字符串转换为对象
   * @param json JSON 字符串
   * @returns 解析后的对象
   */
  static jsonToObject(json: string): object {
    // 使用 Map 作为通用对象容器，避免 any 类型
    const parsed: object = JSON.parse(json) as object
    return parsed
  }


  /**
   * ArkTS 值转换为数据库值
   * 根据目标列类型进行适当的转换
   * @param value ArkTS 值
   * @param columnType 目标列类型
   * @param propertyType 属性类型标识（用于特殊类型如 Date、boolean）
   * @returns 数据库值
   */
  static toDbValue(value: ValueType, columnType: ColumnType, propertyType: string): DbValueType {
    // 处理 null 值
    if (value === null) {
      return null
    }

    // 根据属性类型进行转换
    if (propertyType === 'Date') {
      if (value instanceof Date) {
        return TypeConverter.dateToTimestamp(value)
      }
      if (typeof value === 'number') {
        // Date 已经是时间戳形式
        return value
      }
    }

    if (propertyType === 'boolean' && typeof value === 'boolean') {
      return TypeConverter.booleanToInt(value)
    }

    if (propertyType === 'object') {
      if (typeof value === 'string') {
        // 对象已经序列化为 JSON 字符串
        return value
      }
      if (value !== null && typeof value === 'object') {
        return TypeConverter.objectToJson(value as object)
      }
    }

    // 根据列类型进行基本转换
    switch (columnType) {
      case ColumnType.TEXT:
        if (typeof value === 'string') {
          return value
        }
        return String(value)

      case ColumnType.INTEGER:
        if (typeof value === 'number') {
          return Math.floor(value)
        }
        if (typeof value === 'boolean') {
          return TypeConverter.booleanToInt(value)
        }
        return 0

      case ColumnType.REAL:
        if (typeof value === 'number') {
          return value
        }
        return 0

      case ColumnType.BLOB:
        // BLOB 类型：如果值已经是字符串（Base64编码），保持不变
        // 实际的 Uint8Array 处理需要在 DataMapper 层面进行
        if (typeof value === 'string') {
          return value
        }
        // 其他类型尝试转换为字符串
        if (typeof value === 'number' || typeof value === 'boolean') {
          return String(value)
        }
        return null

      default:
        return null
    }
  }

  private static handleConversionError(
    actualType: string,
    expectedType: string,
    columnName: string,
    options?: TypeConversionOptions
  ): ValueType {
    if (options?.strict === false) {
      if (options.fallbackValue !== undefined) {
        return options.fallbackValue
      }
      return null
    }
    throw new TypeConversionError(actualType, expectedType, columnName)
  }

  /**
   * 数据库值转换为 ArkTS 值
   * 根据目标属性类型进行适当的转换
   * @param value 数据库值
   * @param propertyType 目标属性类型标识
   * @param columnName 列名（用于错误报告）
   * @returns ArkTS 值
   */
  static fromDbValue(
    value: DbValueType,
    propertyType: string,
    columnName: string,
    options?: TypeConversionOptions
  ): ValueType {
    // 处理 null 值
    if (value === null) {
      return null
    }

    // 根据属性类型进行转换
    switch (propertyType) {
      case 'string':
        if (typeof value === 'string') {
          return value
        }
        if (typeof value === 'number') {
          return String(value)
        }
        return TypeConverter.handleConversionError(typeof value, 'string', columnName, options)

      case 'number':
        if (typeof value === 'number') {
          return value
        }
        if (typeof value === 'string') {
          const num = parseFloat(value)
          if (!isNaN(num)) {
            return num
          }
        }
        return TypeConverter.handleConversionError(typeof value, 'number', columnName, options)

      case 'boolean':
        if (typeof value === 'number') {
          return TypeConverter.intToBoolean(value)
        }
        return TypeConverter.handleConversionError(typeof value, 'boolean', columnName, options)

      case 'Date':
        if (typeof value === 'number') {
          // 返回时间戳，由调用方转换为 Date
          return value
        }
        return TypeConverter.handleConversionError(typeof value, 'Date', columnName, options)

      case 'object':
        if (typeof value === 'string') {
          // 返回 JSON 字符串，由调用方解析
          return value
        }
        return TypeConverter.handleConversionError(typeof value, 'object', columnName, options)

      case 'Uint8Array':
      case 'blob':
      case 'BLOB':
        // BLOB 类型：返回字符串形式（Base64）或 null
        // 注意：ValueType 不包含 Uint8Array，所以 BLOB 数据需要以字符串形式处理
        if (typeof value === 'string') {
          return value
        }
        if (value instanceof Uint8Array) {
          // 如果需要在 ValueType 中存储，可以转换为 Base64 字符串
          // 这里返回 null，因为 ValueType 不支持 Uint8Array
          // 调用方应直接从 ResultSet 获取 BLOB 数据
          return null
        }
        return null

      default:
        // 默认直接返回
        if (typeof value === 'string' || typeof value === 'number') {
          return value
        }
        return null
    }
  }
}
