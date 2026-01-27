/**
 * 数据库错误类
 * 用于处理数据库连接、SQL 执行等相关的错误
 */

import { OrmError, ErrorContext } from './OrmError'
import {
  ERROR_DATABASE_CONNECTION_FAILED,
  ERROR_SQL_EXECUTION_FAILED,
  ERROR_DATABASE_NOT_INITIALIZED
} from './ErrorCodes'

/**
 * 数据库错误基类
 */
export class DatabaseError extends OrmError {
  constructor(message: string, code: string, context?: ErrorContext) {
    super(message, code, context)
    this.name = 'DatabaseError'
  }
}

/**
 * 数据库连接失败错误
 */
export class ConnectionError extends DatabaseError {
  constructor(dbName: string, reason: string) {
    const context = new ErrorContext()
    context.tableName = dbName
    context.operation = '数据库连接'
    context.details = reason
    super(`数据库 "${dbName}" 连接失败: ${reason}`, ERROR_DATABASE_CONNECTION_FAILED, context)
    this.name = 'ConnectionError'
  }
}

/**
 * SQL 执行失败错误
 */
export class ExecutionError extends DatabaseError {
  constructor(sql: string, reason: string) {
    const context = new ErrorContext()
    context.operation = 'SQL 执行'
    context.details = `SQL: ${sql.substring(0, 100)}... | 原因: ${reason}`
    super(`SQL 执行失败: ${reason}`, ERROR_SQL_EXECUTION_FAILED, context)
    this.name = 'ExecutionError'
  }
}

/**
 * 数据库未初始化错误
 */
export class DatabaseNotInitializedError extends DatabaseError {
  constructor() {
    const context = new ErrorContext()
    context.operation = '获取数据库实例'
    super('数据库未初始化，请先调用 initialize() 方法', ERROR_DATABASE_NOT_INITIALIZED, context)
    this.name = 'DatabaseNotInitializedError'
  }
}
