/**
 * OCORM 统一初始化入口
 * 简化 DatabaseManager + SchemaBuilder 的初始化流程
 */

import { Context } from '@kit.AbilityKit'
import { DatabaseManager, DatabaseManagerAdapter } from '../database/DatabaseManager'
import { DatabaseConfig } from '../database/DatabaseConfig'
import { Logger } from '../logging/Logger'
import { LogLevel } from '../logging/LogLevel'
import { SchemaBuilder, CreateAllTablesResult } from '../schema/SchemaBuilder'
import {
  AutoMigrationOptions,
  MigrationManager,
  SchemaMigrationExecutionResult
} from '../schema/MigrationManager'

/**
 * OCORM 初始化选项
 */
export interface OCORMInitOptions {
  /** 数据库配置 */
  config: DatabaseConfig
  /** 自定义 DatabaseManager（用于测试） */
  databaseManager?: DatabaseManagerAdapter
  /** 是否自动创建表，默认 true */
  autoCreateTables?: boolean
  /** 是否启用自动迁移（默认 false） */
  autoMigrate?: boolean
  /** 自动迁移选项 */
  autoMigrationOptions?: AutoMigrationOptions
  /** 自定义 MigrationManager */
  migrationManager?: MigrationManager
  /** 是否启用日志（默认使用 DatabaseConfig.enableLogger） */
  enableLogger?: boolean
  /** 日志级别（默认使用 DatabaseConfig.loggerLevel） */
  logLevel?: LogLevel
  /** 自定义 SchemaBuilder */
  schemaBuilder?: SchemaBuilder
}

/**
 * 统一初始化入口
 * @param context 应用上下文
 * @param options 初始化选项
 * @returns 建表结果，如果未执行建表返回 null
 */
export async function OCORMInit(
  context: Context,
  options: OCORMInitOptions
): Promise<CreateAllTablesResult | SchemaMigrationExecutionResult | null> {
  const databaseManager = options.databaseManager ? options.databaseManager : DatabaseManager.getInstance()
  await databaseManager.initialize(context, options.config)

  const enableLogger = options.enableLogger !== undefined
    ? options.enableLogger
    : options.config.enableLogger
  const logLevel = options.logLevel !== undefined
    ? options.logLevel
    : options.config.loggerLevel

  Logger.getInstance().configure(enableLogger, logLevel)

  if (options.autoMigrate === true) {
    const manager = options.migrationManager ? options.migrationManager : new MigrationManager()
    return await manager.autoMigrateWithManager(options.autoMigrationOptions)
  }

  if (options.autoCreateTables === false) {
    return null
  }

  const builder = options.schemaBuilder ? options.schemaBuilder : new SchemaBuilder()
  return await builder.createAllTablesWithManager()
}
