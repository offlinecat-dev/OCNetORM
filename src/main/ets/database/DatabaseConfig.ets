/**
 * 数据库配置接口
 * 定义数据库初始化所需的配置参数
 */

import { relationalStore } from '@kit.ArkData'
import { LogLevel } from '../logging/LogLevel'
import { PoolConfig } from './pool/PoolConfig'

export interface ConnectionPoolOptions {
  enabled?: boolean
  minSize?: number
  maxSize?: number
  acquireTimeoutMs?: number
  idleTimeoutMs?: number
  healthCheckIntervalMs?: number
}

export type PooledWriteGuardMode = 'global' | 'off'

/**
 * 数据库配置类
 * 用于配置数据库连接参数和日志设置
 */
export class DatabaseConfig {
  /** 数据库名称 */
  name: string = ''
  /** 安全级别 */
  securityLevel: relationalStore.SecurityLevel = relationalStore.SecurityLevel.S1
  /** 是否加密 */
  encrypt: boolean = true
  /** 是否启用日志 */
  enableLogger: boolean = false
  /** 日志级别 */
  loggerLevel: LogLevel = LogLevel.INFO
  /** 健康检查间隔（毫秒），0 表示禁用，默认禁用 */
  healthCheckIntervalMs: number = 0
  /** 启用查询缓存 */
  enableQueryCache: boolean = false
  /** 查询缓存最大条目数 */
  queryCacheMaxSize: number = 100
  /** 查询缓存 TTL（毫秒） */
  queryCacheTtlMs: number = 60000
  /** 查询超时（毫秒），0 表示禁用 */
  queryTimeoutMs: number = 0
  /** 最大并发查询数，0 表示不限制 */
  maxConcurrentQueries: number = 0
  /** 关联加载 IN 条件单批上限 */
  relationInClauseLimit: number = 500
  /** 关联加载并发上限（0 或 1 表示串行） */
  relationLoadConcurrency: number = 1
  /** 连接池配置 */
  connectionPool: PoolConfig = new PoolConfig()
  /** 连接池下未绑定事务写入保护模式 */
  pooledWriteGuardMode: PooledWriteGuardMode = 'off'

  constructor(
    name: string,
    securityLevel?: relationalStore.SecurityLevel,
    encrypt?: boolean,
    enableLogger?: boolean,
    loggerLevel?: LogLevel
  ) {
    this.name = name
    if (securityLevel !== undefined) {
      this.securityLevel = securityLevel
    }
    if (encrypt !== undefined) {
      this.encrypt = encrypt
    }
    if (enableLogger !== undefined) {
      this.enableLogger = enableLogger
    }
    if (loggerLevel !== undefined) {
      this.loggerLevel = loggerLevel
    }
  }

  /**
   * 设置健康检查间隔
   * @param intervalMs 间隔时间（毫秒），0 表示禁用
   * @returns this（支持链式调用）
   */
  setHealthCheckInterval(intervalMs: number): DatabaseConfig {
    this.healthCheckIntervalMs = intervalMs
    return this
  }

  /**
   * 配置查询缓存
   * @param enabled 是否启用
   * @param maxSize 最大条目数
   * @param ttlMs 缓存 TTL（毫秒）
   * @returns this（支持链式调用）
   */
  setQueryCache(enabled: boolean, maxSize?: number, ttlMs?: number): DatabaseConfig {
    this.enableQueryCache = enabled
    if (maxSize !== undefined) {
      this.queryCacheMaxSize = maxSize
    }
    if (ttlMs !== undefined) {
      this.queryCacheTtlMs = ttlMs
    }
    return this
  }

  setQueryTimeout(timeoutMs: number): DatabaseConfig {
    this.queryTimeoutMs = timeoutMs > 0 ? Math.floor(timeoutMs) : 0
    return this
  }

  setMaxConcurrentQueries(limit: number): DatabaseConfig {
    this.maxConcurrentQueries = limit > 0 ? Math.floor(limit) : 0
    return this
  }

  setRelationInClauseLimit(limit: number): DatabaseConfig {
    this.relationInClauseLimit = limit > 0 ? Math.floor(limit) : 1
    return this
  }

  setRelationLoadConcurrency(limit: number): DatabaseConfig {
    this.relationLoadConcurrency = limit > 0 ? Math.floor(limit) : 1
    return this
  }

  setConnectionPool(options: ConnectionPoolOptions): DatabaseConfig {
    const pool = this.connectionPool.clone()
    if (options.enabled !== undefined) {
      pool.enabled = options.enabled
    }
    if (options.minSize !== undefined) {
      pool.minSize = this.normalizePoolNumber(options.minSize, pool.minSize)
    }
    if (options.maxSize !== undefined) {
      pool.maxSize = this.normalizePoolNumber(options.maxSize, pool.maxSize)
    }
    if (options.acquireTimeoutMs !== undefined) {
      pool.acquireTimeoutMs = this.normalizePoolNumber(options.acquireTimeoutMs, pool.acquireTimeoutMs)
    }
    if (options.idleTimeoutMs !== undefined) {
      pool.idleTimeoutMs = this.normalizePoolNumber(options.idleTimeoutMs, pool.idleTimeoutMs)
    }
    if (options.healthCheckIntervalMs !== undefined) {
      pool.healthCheckIntervalMs = this.normalizePoolNumber(
        options.healthCheckIntervalMs,
        pool.healthCheckIntervalMs
      )
    }
    this.connectionPool = pool.normalize()
    return this
  }

  private normalizePoolNumber(input: number, fallback: number): number {
    if (!Number.isFinite(input)) {
      return fallback
    }
    return Math.floor(input)
  }

  setPooledWriteGuardMode(mode: PooledWriteGuardMode): DatabaseConfig {
    this.pooledWriteGuardMode = mode
    return this
  }
}
