/**
 * 数据库初始化示例
 * 演示如何使用 OCORM 初始化数据库
 */

import { Context } from '@kit.AbilityKit'
import { relationalStore } from '@kit.ArkData'
import {
  OCORMInit,
  OCORMInitOptions,
  DatabaseConfig,
  LogLevel
} from 'ocorm'

// 导入实体注册函数
import { registerUserEntity } from '../entity/UserEntity'

/**
 * OCORMInitOptions 实现类
 */
class InitOptions implements OCORMInitOptions {
  config: DatabaseConfig
  autoCreateTables: boolean = true

  constructor(config: DatabaseConfig) {
    this.config = config
  }
}

/**
 * 数据库初始化器
 */
export class DatabaseInitializer {
  private static instance: DatabaseInitializer | null = null
  private initialized: boolean = false

  private constructor() {}

  /**
   * 获取单例实例
   */
  static getInstance(): DatabaseInitializer {
    if (DatabaseInitializer.instance === null) {
      DatabaseInitializer.instance = new DatabaseInitializer()
    }
    return DatabaseInitializer.instance
  }

  /**
   * 初始化数据库
   * @param context 应用上下文
   */
  async initialize(context: Context): Promise<void> {
    if (this.initialized) {
      return
    }

    // 1. 注册所有实体
    this.registerEntities()

    // 2. 创建数据库配置
    const config = new DatabaseConfig(
      'app_database.db',                    // 数据库文件名
      relationalStore.SecurityLevel.S1,     // 安全级别
      false,                                // 是否加密
      true,                                 // 启用日志
      LogLevel.DEBUG                        // 日志级别
    )

    // 可选：配置查询缓存
    config.setQueryCache(true, 100, 60000)  // 启用缓存，最大100条，TTL 60秒

    // 3. 初始化 OCORM
    const options = new InitOptions(config)
    options.autoCreateTables = true

    await OCORMInit(context, options)
    this.initialized = true
  }

  /**
   * 注册所有实体
   */
  private registerEntities(): void {
    // 注册用户实体
    registerUserEntity()

    // 如果有更多实体，在此处继续注册
    // registerProductEntity()
    // registerOrderEntity()
  }

  /**
   * 检查是否已初始化
   */
  isInitialized(): boolean {
    return this.initialized
  }
}

/**
 * 快速初始化函数
 * 在 EntryAbility 的 onCreate 中调用
 * @param context 应用上下文
 */
export async function initDatabase(context: Context): Promise<void> {
  await DatabaseInitializer.getInstance().initialize(context)
}
