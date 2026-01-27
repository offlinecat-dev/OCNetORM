/**
 * 映射错误类
 * 用于处理类型转换、实体映射等相关的错误
 */

import { OrmError, ErrorContext } from './OrmError'
import {
  ERROR_TYPE_CONVERSION_FAILED,
  ERROR_NULL_VALUE_NOT_ALLOWED,
  ERROR_MAPPING_FAILED,
  ERROR_TYPE_MISMATCH
} from './ErrorCodes'

/**
 * 映射错误基类
 */
export class MappingError extends OrmError {
  constructor(message: string, code: string, context?: ErrorContext) {
    super(message, code, context)
    this.name = 'MappingError'
  }
}

/**
 * 类型转换失败错误
 */
export class TypeConversionError extends MappingError {
  constructor(sourceType: string, targetType: string, columnName: string) {
    const context = new ErrorContext()
    context.columnName = columnName
    context.operation = '类型转换'
    context.details = `从 ${sourceType} 转换到 ${targetType}`
    super(`类型转换失败: 无法将 ${sourceType} 转换为 ${targetType}`, ERROR_TYPE_CONVERSION_FAILED, context)
    this.name = 'TypeConversionError'
  }
}

/**
 * 非空值为 null 错误
 */
export class NullValueError extends MappingError {
  constructor(entityName: string, columnName: string) {
    const context = new ErrorContext()
    context.entityName = entityName
    context.columnName = columnName
    context.operation = '值映射'
    super(`列 "${columnName}" 不允许为空值`, ERROR_NULL_VALUE_NOT_ALLOWED, context)
    this.name = 'NullValueError'
  }
}

/**
 * 实体映射失败错误
 */
export class EntityMappingError extends MappingError {
  constructor(entityName: string, reason: string) {
    const context = new ErrorContext()
    context.entityName = entityName
    context.operation = '实体映射'
    context.details = reason
    super(`实体 "${entityName}" 映射失败: ${reason}`, ERROR_MAPPING_FAILED, context)
    this.name = 'EntityMappingError'
  }
}

/**
 * 类型不匹配错误
 * 当 TypedEntityData 的泛型类型与实际值类型不匹配时抛出
 */
export class TypeMismatchError extends MappingError {
  /**
   * 构造函数
   * @param expected 期望的类型
   * @param actual 实际的类型
   */
  constructor(expected: string, actual: string) {
    const context = new ErrorContext()
    context.operation = '类型检查'
    context.details = `期望类型: ${expected}，实际类型: ${actual}`
    super(`类型不匹配: 期望 '${expected}'，实际 '${actual}'`, ERROR_TYPE_MISMATCH, context)
    this.name = 'TypeMismatchError'
  }
}
