/**
 * 数据库管理器
 * 单例模式管理 RdbStore 实例的生命周期
 */

import { relationalStore } from '@kit.ArkData'
import { Context } from '@kit.AbilityKit'
import { DatabaseConfig } from './DatabaseConfig'
import {
  ConnectionError,
  DatabaseNotInitializedError
} from '../errors/DatabaseError'
import { QueryCache } from '../query/QueryCache'
import { Logger } from '../logging/Logger'

/**
 * 数据库管理器适配接口（用于测试注入）
 */
export interface DatabaseManagerAdapter {
  /**
   * 初始化数据库连接
   */
  initialize(context: Context, config: DatabaseConfig): Promise<void>
}

/**
 * 数据库管理器单例类
 * 负责数据库连接的创建、获取和关闭
 */
export class DatabaseManager implements DatabaseManagerAdapter {
  /** 单例实例 */
  private static instance: DatabaseManager | null = null
  /** RdbStore 实例 */
  private store: relationalStore.RdbStore | null = null
  /** 数据库配置 */
  private config: DatabaseConfig | null = null
  /** 是否已初始化 */
  private initialized: boolean = false
  /** 健康检查定时器 ID */
  private healthCheckIntervalId: number = 0
  /** 连接是否健康 */
  private healthy: boolean = false
  /** 日志记录器 */
  private logger: Logger

  /**
   * 私有构造函数，防止外部实例化
   */
  private constructor() {
    this.logger = Logger.getInstance()
  }

  /**
   * 获取单例实例
   * @returns DatabaseManager 实例
   */
  static getInstance(): DatabaseManager {
    if (DatabaseManager.instance === null) {
      DatabaseManager.instance = new DatabaseManager()
    }
    return DatabaseManager.instance
  }

  /**
   * 初始化数据库
   * 创建或打开 RdbStore 实例
   * @param context 应用上下文
   * @param config 数据库配置
   * @returns Promise<void>
   */
  async initialize(context: Context, config: DatabaseConfig): Promise<void> {
    // 如果已经初始化且配置相同，直接返回
    if (this.initialized && this.config !== null && this.config.name === config.name) {
      return
    }

    // 如果已有连接但配置不同，先关闭
    if (this.store !== null) {
      await this.close()
    }

    this.config = config

    // 构建 RdbStore 配置
    const storeConfig: relationalStore.StoreConfig = {
      name: config.name,
      securityLevel: config.securityLevel,
      encrypt: config.encrypt
    }

    try {
      // 创建或打开数据库
      this.store = await relationalStore.getRdbStore(context, storeConfig)
      this.initialized = true
      this.healthy = true

      // 配置查询缓存
      if (config.enableQueryCache) {
        QueryCache.getInstance().configure({
          enabled: true,
          maxSize: config.queryCacheMaxSize,
          ttlMs: config.queryCacheTtlMs
        })
      } else {
        QueryCache.getInstance().configure({
          enabled: false
        })
      }

      // 启动健康检查
      if (config.healthCheckIntervalMs > 0) {
        this.startHealthCheck(config.healthCheckIntervalMs)
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      throw new ConnectionError(config.name, errorMessage)
    }
  }

  /**
   * 获取 RdbStore 实例
   * @returns RdbStore 实例
   * @throws DatabaseNotInitializedError 如果数据库未初始化
   */
  getStore(): relationalStore.RdbStore {
    if (!this.initialized || this.store === null) {
      throw new DatabaseNotInitializedError()
    }
    return this.store
  }

  /**
   * 关闭数据库连接
   * @returns Promise<void>
   */
  async close(): Promise<void> {
    // 停止健康检查
    this.stopHealthCheck()

    if (this.store !== null) {
      // RdbStore 没有显式的 close 方法，设置为 null 让 GC 回收
      this.store = null
      this.initialized = false
      this.healthy = false
    }
  }

  /**
   * 启动健康检查
   * @param intervalMs 检查间隔（毫秒）
   */
  private startHealthCheck(intervalMs: number): void {
    // 停止现有的健康检查
    this.stopHealthCheck()

    this.healthCheckIntervalId = setInterval(async () => {
      try {
        const isHealthy = await this.ping()
        if (!isHealthy && this.healthy) {
          this.healthy = false
          this.logger.logError('数据库连接健康检查失败')
        } else if (isHealthy && !this.healthy) {
          this.healthy = true
          this.logger.logInfo('数据库连接已恢复')
        }
      } catch (e) {
        if (this.healthy) {
          this.healthy = false
          const errorMessage = e instanceof Error ? e.message : String(e)
          this.logger.logError(`数据库健康检查异常: ${errorMessage}`)
        }
      }
    }, intervalMs)
  }

  /**
   * 停止健康检查
   */
  private stopHealthCheck(): void {
    if (this.healthCheckIntervalId !== 0) {
      clearInterval(this.healthCheckIntervalId)
      this.healthCheckIntervalId = 0
    }
  }

  /**
   * 执行连接健康检查
   * @returns Promise<boolean> 连接是否健康
   */
  async ping(): Promise<boolean> {
    if (!this.initialized || this.store === null) {
      return false
    }

    try {
      // 使用 ORM 版本表进行健康检查（该表在迁移管理器初始化时创建）
      const predicates = new relationalStore.RdbPredicates('_orm_version')
      predicates.limitAs(1)
      const result = await this.store.query(predicates)
      result.close()
      return true
    } catch (e) {
      return false
    }
  }

  /**
   * 检查连接是否健康
   * @returns 是否健康
   */
  isHealthy(): boolean {
    return this.healthy
  }

  /**
   * 检查数据库是否已初始化
   * @returns 是否已初始化
   */
  isInitialized(): boolean {
    return this.initialized
  }

  /**
   * 获取当前数据库配置
   * @returns 数据库配置，如果未初始化返回 null
   */
  getConfig(): DatabaseConfig | null {
    return this.config
  }

  /**
   * 重置单例实例（仅用于测试）
   */
  static resetInstance(): void {
    if (DatabaseManager.instance !== null) {
      DatabaseManager.instance.stopHealthCheck()
      DatabaseManager.instance.store = null
      DatabaseManager.instance.config = null
      DatabaseManager.instance.initialized = false
      DatabaseManager.instance.healthy = false
      DatabaseManager.instance = null
    }
  }

  /**
   * 获取查询缓存实例
   * @returns QueryCache 实例
   */
  getQueryCache(): QueryCache {
    return QueryCache.getInstance()
  }
}
