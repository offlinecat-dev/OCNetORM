/**
 * 验证错误类
 * 用于处理实体数据校验相关的错误
 */

import { OrmError, ErrorContext } from './OrmError'
import { ErrorTemplateContext } from './ErrorLocale'
import {
  ERROR_VALIDATION_FAILED,
  ERROR_VALIDATION_REQUIRED,
  ERROR_VALIDATION_LENGTH,
  ERROR_VALIDATION_EMAIL
} from './ErrorCodes'

export class ValidationError extends OrmError {
  constructor(message: string, code: string, context?: ErrorContext, templateContext?: ErrorTemplateContext) {
    super(message, code, context, templateContext)
    this.name = 'ValidationError'
  }
}

export class RequiredValidationError extends ValidationError {
  constructor(entityName: string, columnName: string) {
    const context = new ErrorContext()
    context.entityName = entityName
    context.columnName = columnName
    context.operation = '数据校验'
    const templateContext = new ErrorTemplateContext()
    templateContext.columnName = columnName
    super(`字段 ${columnName} 为必填项`, ERROR_VALIDATION_REQUIRED, context, templateContext)
    this.name = 'RequiredValidationError'
  }
}

export class LengthValidationError extends ValidationError {
  constructor(entityName: string, columnName: string, min: number, max: number) {
    const context = new ErrorContext()
    context.entityName = entityName
    context.columnName = columnName
    context.operation = '数据校验'
    context.details = `length=${min}-${max}`
    const templateContext = new ErrorTemplateContext()
    templateContext.columnName = columnName
    templateContext.min = min
    templateContext.max = max
    super(`字段 ${columnName} 长度需在 ${min} 到 ${max} 之间`, ERROR_VALIDATION_LENGTH, context, templateContext)
    this.name = 'LengthValidationError'
  }
}

export class EmailValidationError extends ValidationError {
  constructor(entityName: string, columnName: string, value: string) {
    const context = new ErrorContext()
    context.entityName = entityName
    context.columnName = columnName
    context.operation = '数据校验'
    context.details = value
    const templateContext = new ErrorTemplateContext()
    templateContext.columnName = columnName
    super(`字段 ${columnName} 不是有效的邮箱地址`, ERROR_VALIDATION_EMAIL, context, templateContext)
    this.name = 'EmailValidationError'
  }
}

export class EntityValidationError extends ValidationError {
  constructor(entityName: string, reason: string) {
    const context = new ErrorContext()
    context.entityName = entityName
    context.operation = '数据校验'
    context.details = reason
    super(`实体 ${entityName} 验证失败: ${reason}`, ERROR_VALIDATION_FAILED, context)
    this.name = 'EntityValidationError'
  }
}
