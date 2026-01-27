/**
 * 查询缓存机制
 * 提供简单的一级缓存，减少重复查询，提升性能
 */

import { EntityData } from '../mapping/DataMapper'
import { ValueType } from '../types/ValueTypes'

/**
 * 缓存条目
 */
export class CacheEntry {
  /** 缓存的数据 */
  data: EntityData
  /** 缓存时间戳 */
  timestamp: number

  constructor(data: EntityData, timestamp: number) {
    this.data = data
    this.timestamp = timestamp
  }
}

/**
 * 缓存配置选项
 */
export interface QueryCacheConfig {
  /** 最大缓存条目数 */
  maxSize?: number
  /** 缓存生存时间（毫秒） */
  ttlMs?: number
  /** 是否启用缓存 */
  enabled?: boolean
}

/**
 * 缓存统计信息
 */
export interface CacheStatistics {
  /** 缓存命中次数 */
  hits: number
  /** 缓存未命中次数 */
  misses: number
  /** 当前缓存条目数 */
  size: number
  /** 命中率 */
  hitRate: number
}

/**
 * 查询缓存类
 * 单例模式，提供实体数据的一级缓存
 */
export class QueryCache {
  /** 单例实例 */
  private static instance: QueryCache | null = null

  /** 缓存存储 - 键格式: entityName:id */
  private cache: Map<string, CacheEntry> = new Map()
  /** 最大缓存条目数 */
  private maxSize: number = 100
  /** 缓存生存时间（毫秒），默认 1 分钟 */
  private ttlMs: number = 60000
  /** 是否启用缓存 */
  private enabled: boolean = true
  /** 缓存命中次数 */
  private hits: number = 0
  /** 缓存未命中次数 */
  private misses: number = 0

  private safeIncrement(value: number): number {
    return value < Number.MAX_SAFE_INTEGER ? value + 1 : value
  }

  private recordHit(): void {
    this.hits = this.safeIncrement(this.hits)
  }

  private recordMiss(): void {
    this.misses = this.safeIncrement(this.misses)
  }

  /**
   * 私有构造函数
   */
  private constructor() {
  }

  /**
   * 获取 QueryCache 单例实例
   * @returns QueryCache 实例
   */
  static getInstance(): QueryCache {
    if (QueryCache.instance === null) {
      QueryCache.instance = new QueryCache()
    }
    return QueryCache.instance
  }

  /**
   * 配置缓存
   * @param config 缓存配置
   */
  configure(config: QueryCacheConfig): void {
    if (config.maxSize !== undefined) {
      this.maxSize = config.maxSize
    }
    if (config.ttlMs !== undefined) {
      this.ttlMs = config.ttlMs
    }
    if (config.enabled !== undefined) {
      this.enabled = config.enabled
    }
  }

  /**
   * 生成缓存键
   * 使用特殊分隔符避免实体名或 ID 中包含分隔符时产生的键冲突
   * @param entityName 实体名称
   * @param id 实体主键值
   * @returns 缓存键
   */
  private generateKey(entityName: string, id: ValueType): string {
    // 使用 \x00 作为分隔符，该字符不会出现在正常的实体名或 ID 中
    return `${entityName}\x00${String(id)}`
  }

  /**
   * 深拷贝 EntityData 对象
   * 避免缓存数据被外部修改污染
   * @param data 原始 EntityData
   * @returns 深拷贝后的 EntityData
   */
  private deepCloneEntityData(data: EntityData): EntityData {
    const cloned = new EntityData(data.entityName)

    // 复制所有属性
    // 优先从 propertyMap 获取值（支持通过 setPropertyValue 设置的属性）
    const propertyNames = data.getPropertyNames()
    for (let i = 0; i < propertyNames.length; i++) {
      const name = propertyNames[i]
      const prop = data.getProperty(name)
      if (prop !== null) {
        // 从 properties 数组获取（包含类型信息）
        cloned.addProperty(name, prop.value, prop.propertyType)
      } else {
        // 从 propertyMap 获取（通过 setPropertyValue 设置的属性）
        const value = data.getPropertyValue(name)
        if (value !== null) {
          cloned.addProperty(name, value, typeof value)
        }
      }
    }

    // 复制临时数据
    const transientKeys = data.getTransientKeys()
    for (let i = 0; i < transientKeys.length; i++) {
      const key = transientKeys[i]
      const value = data.getTransient(key)
      cloned.setTransient(key, value)
    }

    // 复制关联数据（浅拷贝关联实体引用，避免丢失已加载的关系）
    const relatedKeys = data.getRelatedPropertyNames()
    for (let i = 0; i < relatedKeys.length; i++) {
      const key = relatedKeys[i]
      const relatedValue = data.getRelatedValue(key)
      if (!relatedValue) {
        continue
      }
      if (relatedValue.isArray) {
        cloned.setRelatedArray(key, [...relatedValue.entityArray])
      } else {
        cloned.setRelatedSingle(key, relatedValue.singleEntity)
      }
    }

    return cloned
  }

  /**
   * 获取缓存数据
   * @param entityName 实体名称
   * @param id 实体主键值
   * @returns 缓存的实体数据（深拷贝），如果未命中返回 null
   */
  get(entityName: string, id: ValueType): EntityData | null {
    if (!this.enabled) {
      return null
    }

    const key = this.generateKey(entityName, id)
    const entry = this.cache.get(key)

    if (entry !== undefined) {
      // 检查是否过期
      const now = Date.now()
      if (now - entry.timestamp < this.ttlMs) {
        this.recordHit()
        // 返回深拷贝，避免调用方修改污染缓存
        return this.deepCloneEntityData(entry.data)
      } else {
        // 缓存已过期，删除
        this.cache.delete(key)
      }
    }

    this.recordMiss()
    return null
  }

  /**
   * 设置缓存数据
   * @param entityName 实体名称
   * @param id 实体主键值
   * @param data 实体数据
   */
  set(entityName: string, id: ValueType, data: EntityData): void {
    if (!this.enabled) {
      return
    }

    // 检查是否需要驱逐旧数据
    if (this.cache.size >= this.maxSize) {
      this.evictOldest()
    }

    const key = this.generateKey(entityName, id)
    // 存储深拷贝，避免原数据被外部修改影响缓存
    this.cache.set(key, new CacheEntry(this.deepCloneEntityData(data), Date.now()))
  }

  /**
   * 驱逐最旧的缓存条目
   */
  private evictOldest(): void {
    let oldestKey: string | null = null
    let oldestTime: number = Number.MAX_SAFE_INTEGER

    this.cache.forEach((entry: CacheEntry, key: string) => {
      if (entry.timestamp < oldestTime) {
        oldestTime = entry.timestamp
        oldestKey = key
      }
    })

    if (oldestKey !== null) {
      this.cache.delete(oldestKey)
    }
  }

  /**
   * 使指定实体的所有缓存失效
   * @param entityName 实体名称
   */
  invalidateEntity(entityName: string): void {
    const prefix = `${entityName}\x00`
    const keysToDelete: Array<string> = []

    this.cache.forEach((_: CacheEntry, key: string) => {
      if (key.startsWith(prefix)) {
        keysToDelete.push(key)
      }
    })

    for (let i = 0; i < keysToDelete.length; i++) {
      this.cache.delete(keysToDelete[i])
    }
  }

  /**
   * 使指定实体的单条记录缓存失效
   * @param entityName 实体名称
   * @param id 实体主键值
   */
  invalidate(entityName: string, id: ValueType): void {
    const key = this.generateKey(entityName, id)
    this.cache.delete(key)
  }

  /**
   * 清空所有缓存
   */
  clear(): void {
    this.cache.clear()
    this.hits = 0
    this.misses = 0
  }

  /**
   * 获取缓存统计信息
   * @returns 缓存统计
   */
  getStatistics(): CacheStatistics {
    const total = this.hits + this.misses
    const hitRate = total > 0 ? this.hits / total : 0

    return {
      hits: this.hits,
      misses: this.misses,
      size: this.cache.size,
      hitRate: hitRate
    }
  }

  /**
   * 检查缓存是否启用
   * @returns 是否启用
   */
  isEnabled(): boolean {
    return this.enabled
  }

  /**
   * 启用缓存
   */
  enable(): void {
    this.enabled = true
  }

  /**
   * 禁用缓存
   */
  disable(): void {
    this.enabled = false
  }

  /**
   * 获取当前缓存大小
   * @returns 缓存条目数
   */
  getSize(): number {
    return this.cache.size
  }

  /**
   * 重置单例实例（主要用于测试）
   */
  static resetInstance(): void {
    if (QueryCache.instance !== null) {
      QueryCache.instance.clear()
      QueryCache.instance = null
    }
  }
}
