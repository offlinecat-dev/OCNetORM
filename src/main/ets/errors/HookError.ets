/**
 * 钩子错误类
 * 用于处理生命周期钩子执行相关的错误
 */

import { OrmError, ErrorContext } from './OrmError'
import { ERROR_HOOK_EXECUTION_FAILED } from './ErrorCodes'
import { sanitizeErrorMessage } from './ErrorSanitizer'

/**
 * 钩子执行错误
 * 当钩子函数执行时抛出异常时使用
 */
export class HookExecutionError extends OrmError {
  /**
   * 构造函数
   * @param entityName 实体名称
   * @param hookName 钩子名称（beforeSave/afterLoad/beforeDelete/...）
   * @param originalError 原始错误信息
   */
  constructor(entityName: string, hookName: string, originalError: string) {
    const sanitizedError = sanitizeErrorMessage(originalError)
    const context = new ErrorContext()
    context.entityName = entityName
    context.operation = hookName
    context.details = sanitizedError
    super(`实体 '${entityName}' 的 '${hookName}' 钩子执行失败: ${sanitizedError}`, ERROR_HOOK_EXECUTION_FAILED, context)
    this.name = 'HookExecutionError'
  }
}
