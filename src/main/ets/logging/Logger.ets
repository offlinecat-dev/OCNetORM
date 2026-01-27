/**
 * SQL 日志系统
 * 用于记录 SQL 执行日志和耗时统计
 *
 * 日志级别说明：
 * - ERROR (0): 仅记录错误日志
 * - INFO (1): 记录错误和基本操作日志（事务）
 * - DEBUG (2): 记录所有日志包括详细 SQL
 */

import { hilog } from '@kit.PerformanceAnalysisKit'
import { LogLevel } from './LogLevel'

/**
 * 日志类型常量
 */
const LOG_TYPE_QUERY: string = 'QUERY'
const LOG_TYPE_TRANSACTION: string = 'TRANSACTION'
const LOG_TYPE_ERROR: string = 'ERROR'
const LOG_TYPE_DEBUG: string = 'DEBUG'
const LOG_TYPE_TASKPOOL: string = 'TASKPOOL'
const LOG_TYPE_PAGINATION: string = 'PAGINATION'
const LOG_TYPE_PARALLEL_RELATION: string = 'PARALLEL_RELATION'
const LOG_TYPE_BATCH_INSERT: string = 'BATCH_INSERT'
const MAX_LOG_MESSAGE_LENGTH: number = 512
const MAX_LOG_HISTORY: number = 200

/**
 * Logger 类
 * 单例模式，用于记录 OCORM 的 SQL 执行日志
 *
 * 使用示例：
 * ```
 * const logger = Logger.getInstance()
 * logger.configure(true, LogLevel.DEBUG)
 * logger.logQuery('SELECT * FROM users', 15)
 * ```
 */
export class Logger {
  /** 单例实例 */
  private static instance: Logger | null = null
  /** 是否启用日志 */
  private enabled: boolean = false
  /** 日志级别 */
  private level: LogLevel = LogLevel.INFO
  /** hilog domain */
  private domain: number = 0x0000
  /** hilog tag */
  private tag: string = 'OCORM'
  /** 记录的日志历史（用于测试） */
  private logHistory: Array<string> = []
  /** 是否记录日志历史（用于测试） */
  private recordHistory: boolean = false

  /**
   * 私有构造函数
   */
  private constructor() {
  }

  /**
   * 获取 Logger 单例实例
   * @returns Logger 实例
   */
  static getInstance(): Logger {
    if (Logger.instance === null) {
      Logger.instance = new Logger()
    }
    return Logger.instance
  }

  /**
   * 重置单例实例（仅用于测试）
   */
  static resetInstance(): void {
    Logger.instance = null
  }

  /**
   * 配置日志系统
   * @param enabled 是否启用日志
   * @param level 日志级别
   */
  configure(enabled: boolean, level: LogLevel): void {
    this.enabled = enabled
    this.level = level
  }

  /**
   * 启用日志历史记录（用于测试）
   * @param record 是否记录
   */
  setRecordHistory(record: boolean): void {
    this.recordHistory = record
    if (!record) {
      this.logHistory = []
    }
  }

  /**
   * 获取日志历史（用于测试）
   * @returns 日志历史数组
   */
  getLogHistory(): Array<string> {
    return [...this.logHistory]
  }

  /**
   * 清空日志历史（用于测试）
   */
  clearLogHistory(): void {
    this.logHistory = []
  }

  /**
   * 检查是否启用日志
   * @returns 是否启用
   */
  isEnabled(): boolean {
    return this.enabled
  }

  /**
   * 获取当前日志级别
   * @returns 日志级别
   */
  getLevel(): LogLevel {
    return this.level
  }

  /**
   * 检查指定级别的日志是否应该被记录
   * @param requiredLevel 需要的最低日志级别
   * @returns 是否应该记录
   */
  private shouldLog(requiredLevel: LogLevel): boolean {
    return this.enabled && this.level >= requiredLevel
  }

  /**
   * 记录日志到历史（用于测试）
   * @param message 日志消息
   */
  private recordToHistory(message: string): void {
    if (this.recordHistory) {
      if (this.logHistory.length >= MAX_LOG_HISTORY) {
        this.logHistory.shift()
      }
      this.logHistory.push(message)
    }
  }

  /**
   * 记录查询日志
   * 仅在 DEBUG 级别记录，包含 SQL 语句和执行耗时
   * 注意：生产环境应禁用 DEBUG 级别日志，避免敏感数据泄露
   *
   * @param sql SQL 语句
   * @param duration 执行耗时（毫秒）
   */
  logQuery(sql: string, duration: number): void {
    // 查询日志仅在 DEBUG 级别记录
    if (!this.shouldLog(LogLevel.DEBUG)) {
      return
    }
    // 对 SQL 中可能的敏感值进行脱敏处理
    const sanitizedSql = this.sanitizeSql(sql)
    const message = this.formatMessage(LOG_TYPE_QUERY, `${duration}ms`, sanitizedSql)
    this.recordToHistory(message)
    hilog.info(this.domain, this.tag, message)
  }

  /**
   * 对 SQL 语句中的敏感值进行脱敏
   * 将字符串值和长数字替换为占位符
   * @param sql 原始 SQL 语句
   * @returns 脱敏后的 SQL
   */
  private sanitizeSql(sql: string): string {
    // 将引号内的字符串值替换为 [***]
    let result = sql.replace(/'[^']*'/g, "'[***]'")
    // 将超过6位的连续数字替换为 [***]（可能是手机号、身份证等）
    result = result.replace(/\b\d{7,}\b/g, '[***]')
    return result
  }

  /**
   * 记录事务日志
   * 在 INFO 及以上级别记录，包含事务操作类型
   *
   * @param action 事务操作（BEGIN/COMMIT/ROLLBACK）
   */
  logTransaction(action: string): void {
    // 事务日志在 INFO 及以上级别记录
    if (!this.shouldLog(LogLevel.INFO)) {
      return
    }
    const message = this.formatMessage(LOG_TYPE_TRANSACTION, '-', action)
    this.recordToHistory(message)
    hilog.info(this.domain, this.tag, message)
  }

  /**
   * 记录错误日志
   * 在所有级别都记录（只要启用了日志）
   *
   * @param errorMessage 错误信息
   */
  logError(errorMessage: string): void {
    // 错误日志在所有级别都记录（ERROR >= ERROR）
    if (!this.shouldLog(LogLevel.ERROR)) {
      return
    }
    const message = this.formatMessage(LOG_TYPE_ERROR, '-', errorMessage, true)
    this.recordToHistory(message)
    hilog.error(this.domain, this.tag, message)
  }

  /**
   * 记录调试日志
   * 仅在 DEBUG 级别记录
   *
   * @param debugMessage 调试信息
   */
  logDebug(debugMessage: string): void {
    // 调试日志仅在 DEBUG 级别记录
    if (!this.shouldLog(LogLevel.DEBUG)) {
      return
    }
    const message = this.formatMessage(LOG_TYPE_DEBUG, '-', debugMessage)
    this.recordToHistory(message)
    hilog.debug(this.domain, this.tag, message)
  }

  /**
   * 记录信息日志
   * 在 INFO 及以上级别记录
   *
   * @param infoMessage 信息内容
   */
  logInfo(infoMessage: string): void {
    if (!this.shouldLog(LogLevel.INFO)) {
      return
    }
    const message = this.formatMessage('INFO', '-', infoMessage)
    this.recordToHistory(message)
    hilog.info(this.domain, this.tag, message)
  }

  /**
   * 格式化日志消息
   * 格式: [OCORM][类型][耗时] 消息
   *
   * @param logType 日志类型
   * @param duration 耗时
   * @param content 消息内容
   * @returns 格式化后的消息
   */
  formatMessage(logType: string, duration: string, content: string, redactSensitive: boolean = false): string {
    const sanitized = this.sanitizeLogMessage(content, redactSensitive)
    return `[OCORM][${logType}][${duration}] ${sanitized}`
  }

  private sanitizeLogMessage(content: string, redactSensitive: boolean): string {
    let sanitized = content.replace(/[\x00-\x1F\x7F]/g, ' ')
    if (redactSensitive) {
      sanitized = sanitized.replace(/'[^']*'/g, "'[***]'")
      sanitized = sanitized.replace(/\"[^\"]*\"/g, '"[***]"')
      sanitized = sanitized.replace(/\b\d{7,}\b/g, '[***]')
    }
    if (sanitized.length > MAX_LOG_MESSAGE_LENGTH) {
      return `${sanitized.slice(0, MAX_LOG_MESSAGE_LENGTH)}...`
    }
    return sanitized
  }

  /**
   * 记录 TaskPool 任务执行日志
   * 仅在 DEBUG 级别记录，包含任务执行耗时和数据量
   *
   * @param taskName 任务名称
   * @param duration 执行耗时（毫秒）
   * @param dataCount 处理的数据量
   * @param usedTaskPool 是否使用了 TaskPool（false 表示降级到主线程）
   */
  logTaskPool(taskName: string, duration: number, dataCount: number, usedTaskPool: boolean): void {
    // TaskPool 日志仅在 DEBUG 级别记录
    if (!this.shouldLog(LogLevel.DEBUG)) {
      return
    }
    const threadInfo = usedTaskPool ? 'TaskPool' : '主线程(降级)'
    const content = `${taskName} - 数据量: ${dataCount}, 线程: ${threadInfo}`
    const message = this.formatMessage(LOG_TYPE_TASKPOOL, `${duration}ms`, content)
    this.recordToHistory(message)
    hilog.info(this.domain, this.tag, message)
  }

  /**
   * 记录分页查询日志
   * 仅在 DEBUG 级别记录，包含页码、每页数量和总数
   *
   * @param page 当前页码
   * @param pageSize 每页数量
   * @param total 总记录数
   * @param duration 查询耗时（毫秒）
   */
  logPagination(page: number, pageSize: number, total: number, duration: number): void {
    // 分页日志仅在 DEBUG 级别记录
    if (!this.shouldLog(LogLevel.DEBUG)) {
      return
    }
    const totalPages = pageSize > 0 ? Math.ceil(total / pageSize) : 0
    const content = `页码: ${page}/${totalPages}, 每页: ${pageSize}, 总数: ${total}`
    const message = this.formatMessage(LOG_TYPE_PAGINATION, `${duration}ms`, content)
    this.recordToHistory(message)
    hilog.info(this.domain, this.tag, message)
  }

  /**
   * 记录并行关联加载日志
   * 仅在 DEBUG 级别记录，包含关联数量和总耗时
   *
   * @param relationNames 加载的关联名称数组
   * @param duration 总耗时（毫秒）
   * @param successCount 成功加载的关联数量
   */
  logParallelRelation(relationNames: Array<string>, duration: number, successCount: number): void {
    // 并行关联日志仅在 DEBUG 级别记录
    if (!this.shouldLog(LogLevel.DEBUG)) {
      return
    }
    const totalCount = relationNames.length
    const relationsStr = relationNames.join(', ')
    const content = `关联: [${relationsStr}], 成功: ${successCount}/${totalCount}`
    const message = this.formatMessage(LOG_TYPE_PARALLEL_RELATION, `${duration}ms`, content)
    this.recordToHistory(message)
    hilog.info(this.domain, this.tag, message)
  }

  /**
   * 记录批量插入日志
   * 仅在 DEBUG 级别记录，包含数据量和耗时
   *
   * @param tableName 表名
   * @param totalCount 总数据量
   * @param insertedCount 成功插入数量
   * @param duration 执行耗时（毫秒）
   * @param useTransaction 是否使用事务
   */
  logBatchInsert(tableName: string, totalCount: number, insertedCount: number, duration: number, useTransaction: boolean): void {
    // 批量插入日志仅在 DEBUG 级别记录
    if (!this.shouldLog(LogLevel.DEBUG)) {
      return
    }
    const transactionInfo = useTransaction ? '事务模式' : '非事务模式'
    const content = `表: ${tableName}, 插入: ${insertedCount}/${totalCount}, 模式: ${transactionInfo}`
    const message = this.formatMessage(LOG_TYPE_BATCH_INSERT, `${duration}ms`, content)
    this.recordToHistory(message)
    hilog.info(this.domain, this.tag, message)
  }
}
