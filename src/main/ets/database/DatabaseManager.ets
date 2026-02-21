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
  private static instance: DatabaseManager = new DatabaseManager()
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
  /** 查询超时（毫秒），0 表示禁用 */
  private queryTimeoutMs: number = 0
  /** 最大并发查询数，0 表示不限制 */
  private maxConcurrentQueries: number = 0
  /** 当前已占用的查询槽位 */
  private activeQuerySlots: number = 0
  /** 等待查询槽位的队列 */
  private pendingQueryResolvers: Array<() => void> = []

  /**
   * 私有构造函数，防止外部实例化
   */
  private constructor() {
  }

  /**
   * 获取单例实例
   * @returns DatabaseManager 实例
   */
  static getInstance(): DatabaseManager {
    return DatabaseManager.instance
  }

  private getLogger(): Logger {
    return Logger.getInstance()
  }

  /**
   * 初始化数据库
   * 创建或打开 RdbStore 实例
   * @param context 应用上下文
   * @param config 数据库配置
   * @returns Promise<void>
   */
  async initialize(context: Context, config: DatabaseConfig): Promise<void> {
    const previousConfig = this.config
    this.handleQueryCacheForConfigChange(previousConfig, config)

    // 如果已经初始化且连接参数一致，重用连接并刷新运行时配置
    if (this.initialized && this.store !== null && this.config !== null) {
      const sameConnection = this.isSameConnectionConfig(this.config, config)
      if (sameConnection) {
        this.config = config
        this.applyRuntimeConfig(config)
        return
      }
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

      // 应用运行时配置（缓存/健康检查等）
      this.applyRuntimeConfig(config)
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

    const currentStore = this.store
    if (currentStore !== null) {
      try {
        await currentStore.close()
      } catch (e) {
        const errorMessage = e instanceof Error ? e.message : String(e)
        this.getLogger().logError(`关闭数据库连接失败: ${errorMessage}`)
      }
    }

    this.store = null
    this.initialized = false
    this.healthy = false
    this.activeQuerySlots = 0
    this.releaseAllWaitingQueries()
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
          this.getLogger().logError('数据库连接健康检查失败')
        } else if (isHealthy && !this.healthy) {
          this.healthy = true
          this.getLogger().logInfo('数据库连接已恢复')
        }
      } catch (e) {
        if (this.healthy) {
          this.healthy = false
          const errorMessage = e instanceof Error ? e.message : String(e)
          this.getLogger().logError(`数据库健康检查异常: ${errorMessage}`)
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
      // 使用轻量查询进行健康检查，避免依赖特定表
      const result = await this.store.querySql('SELECT 1')
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

  getQueryTimeoutMs(): number {
    return this.queryTimeoutMs
  }

  getMaxConcurrentQueries(): number {
    return this.maxConcurrentQueries
  }

  getActiveQuerySlots(): number {
    return this.activeQuerySlots
  }

  async acquireQuerySlot(): Promise<void> {
    if (this.maxConcurrentQueries <= 0) {
      return
    }
    while (this.maxConcurrentQueries > 0 && this.activeQuerySlots >= this.maxConcurrentQueries) {
      await new Promise<void>((resolve) => {
        this.pendingQueryResolvers.push(resolve)
      })
    }
    if (this.maxConcurrentQueries <= 0) {
      return
    }
    this.activeQuerySlots++
  }

  releaseQuerySlot(): void {
    if (this.activeQuerySlots > 0) {
      this.activeQuerySlots--
    }
    if (this.maxConcurrentQueries <= 0) {
      this.releaseAllWaitingQueries()
      return
    }
    this.resolveWaitingQuery()
  }

  /**
   * 重置单例实例（仅用于测试）
   */
  static resetInstance(): void {
    const current = DatabaseManager.instance
    current.stopHealthCheck()
    current.releaseAllWaitingQueries()
    current.store = null
    current.config = null
    current.initialized = false
    current.healthy = false
    current.queryTimeoutMs = 0
    current.maxConcurrentQueries = 0
    current.activeQuerySlots = 0
    DatabaseManager.instance = new DatabaseManager()
  }

  /**
   * 获取查询缓存实例
   * @returns QueryCache 实例
   */
  getQueryCache(): QueryCache {
    return QueryCache.getInstance()
  }

  private resolveWaitingQuery(): void {
    if (this.pendingQueryResolvers.length === 0) {
      return
    }
    if (this.maxConcurrentQueries > 0 && this.activeQuerySlots >= this.maxConcurrentQueries) {
      return
    }
    const resolver = this.pendingQueryResolvers.shift()
    if (resolver !== undefined) {
      resolver()
    }
  }

  private releaseAllWaitingQueries(): void {
    while (this.pendingQueryResolvers.length > 0) {
      const resolver = this.pendingQueryResolvers.shift()
      if (resolver !== undefined) {
        resolver()
      }
    }
  }

  private isSameConnectionConfig(current: DatabaseConfig, next: DatabaseConfig): boolean {
    return current.name === next.name &&
      current.securityLevel === next.securityLevel &&
      current.encrypt === next.encrypt
  }

  private handleQueryCacheForConfigChange(
    previousConfig: DatabaseConfig | null,
    nextConfig: DatabaseConfig
  ): void {
    if (previousConfig === null) {
      return
    }
    if (this.isSameConnectionConfig(previousConfig, nextConfig)) {
      return
    }
    QueryCache.getInstance().clear()
  }

  private applyRuntimeConfig(config: DatabaseConfig): void {
    this.getLogger().configure(config.enableLogger, config.loggerLevel)

    const queryCache = QueryCache.getInstance()
    queryCache.setNamespace(config.name)

    if (config.enableQueryCache) {
      queryCache.configure({
        enabled: true,
        maxSize: config.queryCacheMaxSize,
        ttlMs: config.queryCacheTtlMs
      })
    } else {
      queryCache.configure({
        enabled: false
      })
    }

    this.queryTimeoutMs = config.queryTimeoutMs > 0 ? config.queryTimeoutMs : 0
    this.maxConcurrentQueries = config.maxConcurrentQueries > 0 ? config.maxConcurrentQueries : 0
    if (this.maxConcurrentQueries === 0) {
      this.releaseAllWaitingQueries()
    } else {
      this.resolveWaitingQuery()
    }

    if (config.healthCheckIntervalMs > 0) {
      this.startHealthCheck(config.healthCheckIntervalMs)
    } else {
      this.stopHealthCheck()
    }
  }
}
