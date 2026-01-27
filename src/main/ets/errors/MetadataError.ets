/**
 * 元数据错误类
 * 用于处理实体注册、列定义等元数据相关的错误
 */

import { OrmError, ErrorContext } from './OrmError'
import {
  ERROR_ENTITY_NOT_REGISTERED,
  ERROR_DUPLICATE_ENTITY,
  ERROR_INVALID_COLUMN_TYPE,
  ERROR_COLUMN_NOT_FOUND,
  ERROR_PRIMARY_KEY_NOT_DEFINED
} from './ErrorCodes'

/**
 * 元数据错误基类
 */
export class MetadataError extends OrmError {
  constructor(message: string, code: string, context?: ErrorContext) {
    super(message, code, context)
    this.name = 'MetadataError'
  }
}

/**
 * 实体未注册错误
 */
export class EntityNotRegisteredError extends MetadataError {
  constructor(entityName: string) {
    const context = new ErrorContext()
    context.entityName = entityName
    context.operation = '获取元数据'
    super(`实体 "${entityName}" 未注册`, ERROR_ENTITY_NOT_REGISTERED, context)
    this.name = 'EntityNotRegisteredError'
  }
}

/**
 * 重复注册实体错误
 */
export class DuplicateEntityError extends MetadataError {
  constructor(entityName: string) {
    const context = new ErrorContext()
    context.entityName = entityName
    context.operation = '注册实体'
    super(`实体 "${entityName}" 已存在，不能重复注册`, ERROR_DUPLICATE_ENTITY, context)
    this.name = 'DuplicateEntityError'
  }
}

/**
 * 无效列类型错误
 */
export class InvalidColumnTypeError extends MetadataError {
  constructor(entityName: string, columnName: string, invalidType: string) {
    const context = new ErrorContext()
    context.entityName = entityName
    context.columnName = columnName
    context.details = `无效类型: ${invalidType}`
    super(`列 "${columnName}" 的类型 "${invalidType}" 不受支持`, ERROR_INVALID_COLUMN_TYPE, context)
    this.name = 'InvalidColumnTypeError'
  }
}

/**
 * 列未找到错误
 */
export class ColumnNotFoundError extends MetadataError {
  constructor(entityName: string, columnName: string) {
    const context = new ErrorContext()
    context.entityName = entityName
    context.columnName = columnName
    context.operation = '查找列'
    super(`在实体 "${entityName}" 中未找到列 "${columnName}"`, ERROR_COLUMN_NOT_FOUND, context)
    this.name = 'ColumnNotFoundError'
  }
}

/**
 * 主键未定义错误
 */
export class PrimaryKeyNotDefinedError extends MetadataError {
  constructor(entityName: string) {
    const context = new ErrorContext()
    context.entityName = entityName
    context.operation = '获取主键'
    super(`实体 "${entityName}" 未定义主键`, ERROR_PRIMARY_KEY_NOT_DEFINED, context)
    this.name = 'PrimaryKeyNotDefinedError'
  }
}
