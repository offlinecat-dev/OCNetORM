/**
 * 事务错误类
 * 用于处理事务操作相关的错误
 */

import { OrmError, ErrorContext } from './OrmError'
import {
  ERROR_TRANSACTION_NOT_STARTED,
  ERROR_TRANSACTION_ROLLBACK,
  ERROR_TRANSACTION_COMMIT_FAILED
} from './ErrorCodes'

/**
 * 事务错误基类
 */
export class TransactionError extends OrmError {
  constructor(message: string, code: string, context?: ErrorContext) {
    super(message, code, context)
    this.name = 'TransactionError'
  }
}

/**
 * 事务未启动错误
 */
export class TransactionNotStartedError extends TransactionError {
  constructor() {
    const context = new ErrorContext()
    context.operation = '事务操作'
    super('事务未启动，无法执行事务操作', ERROR_TRANSACTION_NOT_STARTED, context)
    this.name = 'TransactionNotStartedError'
  }
}

/**
 * 事务回滚错误
 */
export class TransactionRollbackError extends TransactionError {
  constructor(reason: string) {
    const context = new ErrorContext()
    context.operation = '事务回滚'
    context.details = reason
    super(`事务已回滚: ${reason}`, ERROR_TRANSACTION_ROLLBACK, context)
    this.name = 'TransactionRollbackError'
  }
}

/**
 * 事务提交失败错误
 */
export class TransactionCommitError extends TransactionError {
  constructor(reason: string) {
    const context = new ErrorContext()
    context.operation = '事务提交'
    context.details = reason
    super(`事务提交失败: ${reason}`, ERROR_TRANSACTION_COMMIT_FAILED, context)
    this.name = 'TransactionCommitError'
  }
}
