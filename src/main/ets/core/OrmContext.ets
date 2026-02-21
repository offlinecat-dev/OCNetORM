/**
 * ORM 上下文
 * 依赖注入容器，管理 ORM 核心组件的依赖关系
 * 提升可测试性和模块解耦
 */

import { MetadataStorage } from './MetadataStorage'
import { DatabaseManager } from '../database/DatabaseManager'
import { Logger } from '../logging/Logger'
import { LogLevel } from '../logging/LogLevel'
import { HooksProcessor } from './HooksProcessor'
import { HookName, GlobalHookCallback } from '../types/EntityHooks'
import { sanitizeSqlPreview } from '../errors/ErrorSanitizer'

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
  /** 慢查询阈值（毫秒），默认 1000 */
  slowQueryThresholdMs?: number
}

export class OrmEvent {
  eventName: string = ''
  timestamp: number = 0
  entityName: string = ''
  operation: string = ''
  sql: string = ''
  duration: number = 0
  threshold: number = 0
  idText: string = ''
  affectedRows: number = 0
  isNew: boolean = false
  softDelete: boolean = false
  force: boolean = false

  constructor(eventName: string) {
    this.eventName = eventName
    this.timestamp = Date.now()
  }
}

export type OrmEventListener = (event: OrmEvent) => void | Promise<void>

/**
 * ORM 上下文类
 * 单例模式，作为依赖注入容器管理所有核心组件
 */
export class OrmContext {
  /** 单例实例 */
  private static instance: OrmContext | null = null
  /** 全局事件监听器 */
  private static eventListeners: Map<string, Array<OrmEventListener>> = new Map()
  /** 慢查询阈值（毫秒） */
  private static slowQueryThresholdMs: number = 1000

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
    if (config.slowQueryThresholdMs !== undefined) {
      OrmContext.setSlowQueryThresholdMs(config.slowQueryThresholdMs)
    }

    context.configured = true
  }

  static registerGlobalHook(hookName: HookName, callback: GlobalHookCallback): void {
    HooksProcessor.getInstance().registerGlobalHook(hookName, callback)
  }

  static clearGlobalHooks(hookName?: HookName): void {
    HooksProcessor.getInstance().clearGlobalHooks(hookName)
  }

  static setSlowQueryThresholdMs(thresholdMs: number): void {
    OrmContext.slowQueryThresholdMs = thresholdMs >= 0 ? Math.floor(thresholdMs) : 1000
  }

  static getSlowQueryThresholdMs(): number {
    return OrmContext.slowQueryThresholdMs
  }

  static on(eventName: string, listener: OrmEventListener): void {
    const normalized = eventName.trim()
    if (normalized.length === 0) {
      return
    }
    let listeners = OrmContext.eventListeners.get(normalized)
    if (listeners === undefined) {
      listeners = []
      OrmContext.eventListeners.set(normalized, listeners)
    }
    listeners.push(listener)
  }

  static off(eventName: string, listener: OrmEventListener): void {
    const listeners = OrmContext.eventListeners.get(eventName.trim())
    if (listeners === undefined) {
      return
    }
    for (let i = listeners.length - 1; i >= 0; i--) {
      if (listeners[i] === listener) {
        listeners.splice(i, 1)
      }
    }
  }

  static once(eventName: string, listener: OrmEventListener): void {
    const onceListener: OrmEventListener = async (event) => {
      OrmContext.off(eventName, onceListener)
      await listener(event)
    }
    OrmContext.on(eventName, onceListener)
  }

  static clearEventListeners(eventName?: string): void {
    if (eventName !== undefined) {
      OrmContext.eventListeners.delete(eventName.trim())
      return
    }
    OrmContext.eventListeners.clear()
  }

  static async emit(eventName: string, event?: OrmEvent): Promise<void> {
    const normalized = eventName.trim()
    if (normalized.length === 0) {
      return
    }
    const listeners = OrmContext.eventListeners.get(normalized)
    if (listeners === undefined || listeners.length === 0) {
      return
    }
    const payload = event !== undefined ? event : new OrmEvent(normalized)
    if (payload.eventName.length === 0) {
      payload.eventName = normalized
    }
    if (payload.timestamp <= 0) {
      payload.timestamp = Date.now()
    }
    const snapshot = listeners.slice()
    for (let i = 0; i < snapshot.length; i++) {
      try {
        const result = snapshot[i](payload)
        if (result instanceof Promise) {
          await result
        }
      } catch (e) {
        const message = e instanceof Error ? e.message : String(e)
        Logger.getInstance().logError(`事件监听器执行失败: ${normalized}, ${message}`)
      }
    }
  }

  static async emitSlowQuery(
    operation: string,
    sql: string,
    duration: number,
    entityName: string = ''
  ): Promise<void> {
    if (duration <= OrmContext.slowQueryThresholdMs) {
      return
    }
    const event = new OrmEvent('query:slow')
    event.operation = operation
    event.sql = sanitizeSqlPreview(sql)
    event.duration = duration
    event.threshold = OrmContext.slowQueryThresholdMs
    event.entityName = entityName
    await OrmContext.emit('query:slow', event)
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
    OrmContext.clearGlobalHooks()
    OrmContext.clearEventListeners()
    OrmContext.slowQueryThresholdMs = 1000
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
