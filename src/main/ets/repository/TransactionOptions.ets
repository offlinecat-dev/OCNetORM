/**
 * 事务选项配置
 * 支持事务隔离级别、超时和重试控制
 */

/**
 * 事务隔离级别
 * SQLite 支持的隔离级别
 */
export enum IsolationLevel {
  /** 读未提交 - 可能读取到未提交的数据 */
  READ_UNCOMMITTED = 'READ_UNCOMMITTED',
  /** 读已提交 - 只能读取已提交的数据（SQLite 默认） */
  READ_COMMITTED = 'READ_COMMITTED',
  /** 可重复读 - 同一事务内多次读取结果一致 */
  REPEATABLE_READ = 'REPEATABLE_READ',
  /** 串行化 - 最高隔离级别，完全串行执行 */
  SERIALIZABLE = 'SERIALIZABLE'
}

/**
 * 事务选项接口
 */
export interface TransactionOptionsConfig {
  /** 隔离级别 */
  isolation?: IsolationLevel
  /** 超时时间（毫秒），默认 30000（30秒） */
  timeout?: number
  /** 失败重试次数，默认 0（不重试） */
  retries?: number
  /** 重试延迟（毫秒），默认 100 */
  retryDelay?: number
  /** 是否只读事务 */
  readOnly?: boolean
}

/**
 * 事务选项类
 * 封装事务执行的配置选项
 */
export class TransactionOptions {
  /** 隔离级别 */
  isolation: IsolationLevel = IsolationLevel.READ_COMMITTED
  /** 超时时间（毫秒） */
  timeout: number = 30000
  /** 失败重试次数 */
  retries: number = 0
  /** 重试延迟（毫秒） */
  retryDelay: number = 100
  /** 是否只读事务 */
  readOnly: boolean = false

  /**
   * 创建默认事务选项
   * @returns 默认事务选项实例
   */
  static createDefault(): TransactionOptions {
    return new TransactionOptions()
  }

  /**
   * 从配置创建事务选项
   * @param config 配置对象
   * @returns 事务选项实例
   */
  static fromConfig(config: TransactionOptionsConfig): TransactionOptions {
    const options = new TransactionOptions()

    if (config.isolation !== undefined) {
      options.isolation = config.isolation
    }
    if (config.timeout !== undefined) {
      options.timeout = config.timeout
    }
    if (config.retries !== undefined) {
      options.retries = config.retries
    }
    if (config.retryDelay !== undefined) {
      options.retryDelay = config.retryDelay
    }
    if (config.readOnly !== undefined) {
      options.readOnly = config.readOnly
    }

    return options
  }

  /**
   * 创建只读事务选项
   * @returns 只读事务选项
   */
  static readOnly(): TransactionOptions {
    const options = new TransactionOptions()
    options.readOnly = true
    return options
  }

  /**
   * 创建带重试的事务选项
   * @param retries 重试次数
   * @param retryDelay 重试延迟（毫秒）
   * @returns 带重试的事务选项
   */
  static withRetry(retries: number, retryDelay: number = 100): TransactionOptions {
    const options = new TransactionOptions()
    options.retries = retries
    options.retryDelay = retryDelay
    return options
  }

  /**
   * 创建带超时的事务选项
   * @param timeout 超时时间（毫秒）
   * @returns 带超时的事务选项
   */
  static withTimeout(timeout: number): TransactionOptions {
    const options = new TransactionOptions()
    options.timeout = timeout
    return options
  }

  /**
   * 创建串行化隔离级别的事务选项
   * @returns 串行化事务选项
   */
  static serializable(): TransactionOptions {
    const options = new TransactionOptions()
    options.isolation = IsolationLevel.SERIALIZABLE
    return options
  }
}
