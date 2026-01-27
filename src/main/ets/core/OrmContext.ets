/**
 * ORM 上下文
 * 依赖注入容器，管理 ORM 核心组件的依赖关系
 * 提升可测试性和模块解耦
 */

import { MetadataStorage } from './MetadataStorage'
import { DatabaseManager } from '../database/DatabaseManager'
import { Logger } from '../logging/Logger'
import { LogLevel } from '../logging/LogLevel'

/**
 * ORM 上下文配置选项
 */
export interface OrmContextConfig {
  /** 自定义 MetadataStorage 实例（用于测试） */
  metadataStorage?: MetadataStorage
  /** 自定义 DatabaseManager 实例（用于测试） */
  databaseManager?: DatabaseManager
  /** 自定义 Logger 实例（用于测试） */
  logger?: Logger
  /** 是否启用日志 */
  enableLogging?: boolean
  /** 日志级别 */
  logLevel?: LogLevel
}

/**
 * ORM 上下文类
 * 单例模式，作为依赖注入容器管理所有核心组件
 */
export class OrmContext {
  /** 单例实例 */
  private static instance: OrmContext | null = null

  /** 元数据存储实例 */
  private metadataStorage: MetadataStorage
  /** 数据库管理器实例 */
  private databaseManager: DatabaseManager
  /** 日志记录器实例 */
  private logger: Logger
  /** 是否已配置 */
  private configured: boolean = false

  /**
   * 私有构造函数
   */
  private constructor() {
    // 默认使用各组件的单例实例
    this.metadataStorage = MetadataStorage.getInstance()
    this.databaseManager = DatabaseManager.getInstance()
    this.logger = Logger.getInstance()
  }

  /**
   * 获取 OrmContext 单例实例
   * @returns OrmContext 实例
   */
  static getInstance(): OrmContext {
    if (OrmContext.instance === null) {
      OrmContext.instance = new OrmContext()
    }
    return OrmContext.instance
  }

  /**
   * 配置 ORM 上下文
   * 允许注入自定义依赖（主要用于测试）
   * @param config 配置选项
   */
  static configure(config: OrmContextConfig): void {
    const context = OrmContext.getInstance()

    // 注入自定义依赖
    if (config.metadataStorage !== undefined) {
      context.metadataStorage = config.metadataStorage
    }

    if (config.databaseManager !== undefined) {
      context.databaseManager = config.databaseManager
    }

    if (config.logger !== undefined) {
      context.logger = config.logger
    }

    // 配置日志
    if (config.enableLogging !== undefined || config.logLevel !== undefined) {
      const enabled = config.enableLogging !== undefined ? config.enableLogging : false
      const level = config.logLevel !== undefined ? config.logLevel : LogLevel.INFO
      context.logger.configure(enabled, level)
    }

    context.configured = true
  }

  /**
   * 获取元数据存储实例
   * @returns MetadataStorage 实例
   */
  getMetadataStorage(): MetadataStorage {
    return this.metadataStorage
  }

  /**
   * 获取数据库管理器实例
   * @returns DatabaseManager 实例
   */
  getDatabaseManager(): DatabaseManager {
    return this.databaseManager
  }

  /**
   * 获取日志记录器实例
   * @returns Logger 实例
   */
  getLogger(): Logger {
    return this.logger
  }

  /**
   * 检查是否已配置
   * @returns 是否已配置
   */
  isConfigured(): boolean {
    return this.configured
  }

  /**
   * 重置上下文（主要用于测试）
   * 恢复为默认的单例依赖
   */
  reset(): void {
    this.metadataStorage = MetadataStorage.getInstance()
    this.databaseManager = DatabaseManager.getInstance()
    this.logger = Logger.getInstance()
    this.configured = false
  }

  /**
   * 重置单例实例（主要用于测试）
   */
  static resetInstance(): void {
    if (OrmContext.instance !== null) {
      OrmContext.instance.reset()
      OrmContext.instance = null
    }
  }
}
