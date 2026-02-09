/**
 * 查询错误类
 * 用于处理查询构建、条件表达式等相关的错误
 */

import { OrmError, ErrorContext } from './OrmError'
import {
  ERROR_INVALID_CONDITION,
  ERROR_PREDICATE_BUILD_FAILED,
  ERROR_INVALID_OPERATOR,
  ERROR_SUB_QUERY
} from './ErrorCodes'
import { sanitizeErrorMessage } from './ErrorSanitizer'

/**
 * 查询错误基类
 */
export class QueryError extends OrmError {
  constructor(message: string, code: string, context?: ErrorContext) {
    super(message, code, context)
    this.name = 'QueryError'
  }
}

/**
 * 无效条件错误
 */
export class InvalidConditionError extends QueryError {
  constructor(columnName: string, reason: string) {
    const sanitizedReason = sanitizeErrorMessage(reason)
    const context = new ErrorContext()
    context.columnName = columnName
    context.operation = '构建查询条件'
    context.details = sanitizedReason
    super(`查询条件无效: ${sanitizedReason}`, ERROR_INVALID_CONDITION, context)
    this.name = 'InvalidConditionError'
  }
}

/**
 * Predicates 构建失败错误
 */
export class PredicateBuildError extends QueryError {
  constructor(entityName: string, reason: string) {
    const sanitizedReason = sanitizeErrorMessage(reason)
    const context = new ErrorContext()
    context.entityName = entityName
    context.operation = '构建 RdbPredicates'
    context.details = sanitizedReason
    super(`构建 RdbPredicates 失败: ${sanitizedReason}`, ERROR_PREDICATE_BUILD_FAILED, context)
    this.name = 'PredicateBuildError'
  }
}

/**
 * 无效操作符错误
 */
export class InvalidOperatorError extends QueryError {
  constructor(operator: string) {
    const context = new ErrorContext()
    context.operation = '解析操作符'
    context.details = `无效操作符: ${operator}`
    super(`不支持的查询操作符: ${operator}`, ERROR_INVALID_OPERATOR, context)
    this.name = 'InvalidOperatorError'
  }
}

/**
 * 子查询错误
 * 当子查询构建失败时抛出
 */
export class SubQueryError extends QueryError {
  /**
   * 构造函数
   * @param message 错误消息
   */
  constructor(message: string) {
    const sanitizedMessage = sanitizeErrorMessage(message)
    const context = new ErrorContext()
    context.operation = '构建子查询'
    context.details = sanitizedMessage
    super(`子查询构建失败: ${sanitizedMessage}`, ERROR_SUB_QUERY, context)
    this.name = 'SubQueryError'
  }
}

/**
 * 作用域未找到错误
 * 当使用未注册的查询作用域时抛出
 */
export class ScopeNotFoundError extends QueryError {
  /**
   * 构造函数
   * @param entityName 实体名称
   * @param scopeName 作用域名称
   */
  constructor(entityName: string, scopeName: string) {
    const context = new ErrorContext()
    context.entityName = entityName
    context.operation = '应用查询作用域'
    context.details = `作用域 '${scopeName}' 未在实体 '${entityName}' 中注册`
    super(`查询作用域未找到: ${scopeName}`, ERROR_SUB_QUERY, context)
    this.name = 'ScopeNotFoundError'
  }
}
