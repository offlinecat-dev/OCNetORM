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
import { StorePool } from './pool/StorePool'
import { StoreLease } from './pool/StoreLease'
import { PoolMetrics } from './pool/PoolMetrics'
import { QuerySlotGate } from './manager/QuerySlotGate'
import { StorePoolFactory } from './manager/StorePoolFactory'

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
 * DatabaseManager 测试桥接状态
 */
export interface DatabaseManagerTestingState {
  store: relationalStore.RdbStore | null
  storePool: StorePool | null
  config: DatabaseConfig | null
  initialized: boolean
  healthy: boolean
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
  /** 可选连接池实例 */
  private storePool: StorePool | null = null
  /** 数据库配置 */
  private config: DatabaseConfig | null = null
  /** 是否已初始化 */
  private initialized: boolean = false
  /** 健康检查定时器 ID */
  private healthCheckIntervalId: number = 0
  /** 连接是否健康 */
  private healthy: boolean = false
  /** 查询并发控制 */
  private querySlotGate: QuerySlotGate = new QuerySlotGate()

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
      const samePool = this.isSamePoolConfig(this.config, config)
      if (sameConnection && samePool) {
        this.config = config
        this.applyRuntimeConfig(config)
        return
      }
    }

    // 如果已有连接但配置不同，先关闭
    if (this.store !== null || this.storePool !== null) {
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
      // 创建主连接，保持旧 getStore() 行为兼容
      this.store = await relationalStore.getRdbStore(context, storeConfig)
      await this.setupPool(context, config, storeConfig)
      this.initialized = true
      this.healthy = true

      // 应用运行时配置（缓存/健康检查等）
      this.applyRuntimeConfig(config)
    } catch (error) {
      await this.close()
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

  async acquireStoreLease(timeoutMs?: number): Promise<StoreLease> {
    if (this.storePool !== null) {
      return await this.storePool.acquire(timeoutMs)
    }
    let store: relationalStore.RdbStore
    try {
      store = this.getStore()
    } catch (e) {
      if (e instanceof Error) {
        throw e
      }
      throw new Error(String(e))
    }
    return new StoreLease('singleton-store', store, null)
  }

  releaseStoreLease(lease: StoreLease): void {
    if (this.storePool === null) {
      return
    }
    this.storePool.release(lease)
  }

  async withStoreLease<T>(
    fn: (lease: StoreLease) => Promise<T>,
    timeoutMs?: number
  ): Promise<T> {
    if (this.storePool !== null) {
      return await this.storePool.withLease(fn, timeoutMs)
    }
    const lease = await this.acquireStoreLease(timeoutMs)
    try {
      return await fn(lease)
    } finally {
      lease.release()
    }
  }

  getPoolMetrics(): PoolMetrics | null {
    if (this.storePool === null) {
      return null
    }
    return this.storePool.metrics()
  }

  isPoolEnabled(): boolean {
    return this.storePool !== null
  }

  /**
   * 关闭数据库连接
   * @returns Promise<void>
   */
  async close(): Promise<void> {
    // 停止健康检查
    this.stopHealthCheck()

    const currentPool = this.storePool
    if (currentPool !== null) {
      try {
        await currentPool.close()
      } catch (e) {
        const errorMessage = e instanceof Error ? e.message : String(e)
        this.getLogger().logError(`关闭连接池失败: ${errorMessage}`)
      }
      this.storePool = null
    }

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
    this.querySlotGate.reset()
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
    return this.querySlotGate.getQueryTimeoutMs()
  }

  getMaxConcurrentQueries(): number {
    return this.querySlotGate.getMaxConcurrentQueries()
  }

  getActiveQuerySlots(): number {
    return this.querySlotGate.getActiveQuerySlots()
  }

  async acquireQuerySlot(): Promise<void> {
    await this.querySlotGate.acquire()
  }

  releaseQuerySlot(): void {
    this.querySlotGate.release()
  }

  /**
   * 获取内部状态（测试桥接）
   */
  getTestingState(): DatabaseManagerTestingState {
    return {
      store: this.store,
      storePool: this.storePool,
      config: this.config,
      initialized: this.initialized,
      healthy: this.healthy
    }
  }

  /**
   * 写入内部状态（测试桥接）
   */
  setTestingState(state: DatabaseManagerTestingState): void {
    this.store = state.store
    this.storePool = state.storePool
    this.config = state.config
    this.initialized = state.initialized
    this.healthy = state.healthy
  }

  /**
   * 应用运行时配置（测试桥接）
   */
  applyRuntimeConfigForTesting(config: DatabaseConfig): void {
    this.config = config
    this.applyRuntimeConfig(config)
  }

  /**
   * 重置单例实例（测试桥接）
   */
  static resetInstanceForTesting(): void {
    const current = DatabaseManager.instance
    current.stopHealthCheck()
    current.querySlotGate.reset()

    const currentPool = current.storePool
    if (currentPool !== null) {
      currentPool.close().catch(() => {
      })
    }

    current.store = null
    current.storePool = null
    current.config = null
    current.initialized = false
    current.healthy = false
    DatabaseManager.instance = new DatabaseManager()
  }

  /**
   * 获取查询缓存实例
   * @returns QueryCache 实例
   */
  getQueryCache(): QueryCache {
    return QueryCache.getInstance()
  }

  private isSameConnectionConfig(current: DatabaseConfig, next: DatabaseConfig): boolean {
    return current.name === next.name &&
      current.securityLevel === next.securityLevel &&
      current.encrypt === next.encrypt
  }

  private isSamePoolConfig(current: DatabaseConfig, next: DatabaseConfig): boolean {
    return StorePoolFactory.isSamePoolConfig(current, next)
  }

  private async setupPool(
    context: Context,
    config: DatabaseConfig,
    storeConfig: relationalStore.StoreConfig
  ): Promise<void> {
    this.storePool = await StorePoolFactory.createPool(context, config, storeConfig)
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

    this.querySlotGate.configure(config)

    if (config.healthCheckIntervalMs > 0) {
      this.startHealthCheck(config.healthCheckIntervalMs)
    } else {
      this.stopHealthCheck()
    }
  }
}
