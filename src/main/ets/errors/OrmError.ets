/**
 * ORM 错误基类
 * 所有 ORM 相关错误的父类
 */

import { formatErrorMessage, ErrorTemplateContext } from './ErrorLocale'

/**
 * 错误上下文接口
 * 用于存储错误相关的上下文信息
 */
export class ErrorContext {
  entityName: string = ''
  columnName: string = ''
  tableName: string = ''
  operation: string = ''
  details: string = ''
}

/**
 * ORM 错误基类
 */
export class OrmError extends Error {
  /** 错误码 */
  code: string = ''
  /** 错误上下文信息 */
  context: ErrorContext = new ErrorContext()

  constructor(
    message: string,
    code: string,
    context?: ErrorContext,
    templateContext?: ErrorTemplateContext
  ) {
    const resolvedContext = templateContext ? templateContext : buildTemplateContext(context)
    const localizedMessage = formatErrorMessage(code, message, resolvedContext)
    super(localizedMessage)
    this.name = 'OrmError'
    this.code = code
    if (context) {
      this.context = context
    }
  }

  /**
   * 获取完整的错误信息
   * @returns 包含错误码和上下文的完整错误描述
   */
  getFullMessage(): string {
    let fullMessage = `[${this.code}] ${this.message}`
    if (this.context.entityName) {
      fullMessage += ` | 实体: ${this.context.entityName}`
    }
    if (this.context.columnName) {
      fullMessage += ` | 列: ${this.context.columnName}`
    }
    if (this.context.tableName) {
      fullMessage += ` | 表: ${this.context.tableName}`
    }
    if (this.context.operation) {
      fullMessage += ` | 操作: ${this.context.operation}`
    }
    if (this.context.details) {
      fullMessage += ` | 详情: ${this.context.details}`
    }
    return fullMessage
  }
}

function buildTemplateContext(context?: ErrorContext): ErrorTemplateContext | undefined {
  if (!context) {
    return undefined
  }
  const templateContext = new ErrorTemplateContext()
  templateContext.entityName = context.entityName
  templateContext.columnName = context.columnName
  templateContext.tableName = context.tableName
  templateContext.operation = context.operation
  templateContext.details = context.details
  return templateContext
}
