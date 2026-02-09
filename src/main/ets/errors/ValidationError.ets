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
  ERROR_VALIDATION_EMAIL,
  ERROR_VALIDATION_MIN,
  ERROR_VALIDATION_MAX,
  ERROR_VALIDATION_RANGE,
  ERROR_VALIDATION_PATTERN,
  ERROR_VALIDATION_URL,
  ERROR_VALIDATION_PHONE,
  ERROR_VALIDATION_DATE,
  ERROR_VALIDATION_ENUM,
  ERROR_VALIDATION_CUSTOM,
  ERROR_VALIDATION_UNIQUE
} from './ErrorCodes'

export class ValidationError extends OrmError {
  constructor(message: string, code: string, context?: ErrorContext, templateContext?: ErrorTemplateContext) {
    super(message, code, context, templateContext)
    this.name = 'ValidationError'
  }
}

function createValidationContext(entityName: string, columnName: string, details: string = ''): ErrorContext {
  const context = new ErrorContext()
  context.entityName = entityName
  context.columnName = columnName
  context.operation = '数据校验'
  context.details = details
  return context
}

function createTemplateContext(columnName: string, min?: number, max?: number): ErrorTemplateContext {
  const templateContext = new ErrorTemplateContext()
  templateContext.columnName = columnName
  if (min !== undefined) {
    templateContext.min = min
  }
  if (max !== undefined) {
    templateContext.max = max
  }
  return templateContext
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

export class MinValidationError extends ValidationError {
  constructor(entityName: string, columnName: string, min: number) {
    const context = createValidationContext(entityName, columnName, `min=${min}`)
    const templateContext = createTemplateContext(columnName, min)
    super(`字段 ${columnName} 的值不能小于 ${min}`, ERROR_VALIDATION_MIN, context, templateContext)
    this.name = 'MinValidationError'
  }
}

export class MaxValidationError extends ValidationError {
  constructor(entityName: string, columnName: string, max: number) {
    const context = createValidationContext(entityName, columnName, `max=${max}`)
    const templateContext = createTemplateContext(columnName, undefined, max)
    super(`字段 ${columnName} 的值不能大于 ${max}`, ERROR_VALIDATION_MAX, context, templateContext)
    this.name = 'MaxValidationError'
  }
}

export class RangeValidationError extends ValidationError {
  constructor(entityName: string, columnName: string, min: number, max: number) {
    const context = createValidationContext(entityName, columnName, `range=${min}-${max}`)
    const templateContext = createTemplateContext(columnName, min, max)
    super(`字段 ${columnName} 的值需在 ${min} 到 ${max} 之间`, ERROR_VALIDATION_RANGE, context, templateContext)
    this.name = 'RangeValidationError'
  }
}

export class PatternValidationError extends ValidationError {
  constructor(entityName: string, columnName: string) {
    const context = createValidationContext(entityName, columnName)
    const templateContext = createTemplateContext(columnName)
    super(`字段 ${columnName} 不符合预期格式`, ERROR_VALIDATION_PATTERN, context, templateContext)
    this.name = 'PatternValidationError'
  }
}

export class UrlValidationError extends ValidationError {
  constructor(entityName: string, columnName: string) {
    const context = createValidationContext(entityName, columnName)
    const templateContext = createTemplateContext(columnName)
    super(`字段 ${columnName} 不是有效的 URL`, ERROR_VALIDATION_URL, context, templateContext)
    this.name = 'UrlValidationError'
  }
}

export class PhoneValidationError extends ValidationError {
  constructor(entityName: string, columnName: string) {
    const context = createValidationContext(entityName, columnName)
    const templateContext = createTemplateContext(columnName)
    super(`字段 ${columnName} 不是有效的手机号`, ERROR_VALIDATION_PHONE, context, templateContext)
    this.name = 'PhoneValidationError'
  }
}

export class DateValidationError extends ValidationError {
  constructor(entityName: string, columnName: string) {
    const context = createValidationContext(entityName, columnName)
    const templateContext = createTemplateContext(columnName)
    super(`字段 ${columnName} 不是有效的日期`, ERROR_VALIDATION_DATE, context, templateContext)
    this.name = 'DateValidationError'
  }
}

export class EnumValidationError extends ValidationError {
  constructor(entityName: string, columnName: string) {
    const context = createValidationContext(entityName, columnName)
    const templateContext = createTemplateContext(columnName)
    super(`字段 ${columnName} 的值不在允许范围内`, ERROR_VALIDATION_ENUM, context, templateContext)
    this.name = 'EnumValidationError'
  }
}

export class CustomValidationError extends ValidationError {
  constructor(entityName: string, columnName: string, message: string) {
    const context = createValidationContext(entityName, columnName, message)
    const templateContext = createTemplateContext(columnName)
    super(message, ERROR_VALIDATION_CUSTOM, context, templateContext)
    this.name = 'CustomValidationError'
  }
}

export class UniqueValidationError extends ValidationError {
  constructor(entityName: string, columnName: string) {
    const context = createValidationContext(entityName, columnName)
    const templateContext = createTemplateContext(columnName)
    super(`字段 ${columnName} 的值必须唯一`, ERROR_VALIDATION_UNIQUE, context, templateContext)
    this.name = 'UniqueValidationError'
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
