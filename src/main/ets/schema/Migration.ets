/**
 * 数据库迁移接口
 * 定义迁移脚本的基本结构
 */

import { relationalStore } from '@kit.ArkData'

/**
 * 迁移脚本接口
 * 每个迁移脚本必须实现此接口
 */
export interface Migration {
  /** 目标版本号，必须唯一且大于 0 */
  version: number

  /** 迁移描述，用于日志和调试 */
  description: string

  /**
   * 升级操作
   * 执行从上一版本到当前版本的数据库变更
   * @param store RdbStore 实例，用于执行 SQL 语句
   * @returns Promise<void>
   */
  up(store: relationalStore.RdbStore): Promise<void>

  /**
   * 回滚操作
   * 撤销当前版本的数据库变更，恢复到上一版本
   * @param store RdbStore 实例，用于执行 SQL 语句
   * @returns Promise<void>
   */
  down(store: relationalStore.RdbStore): Promise<void>
}

/**
 * 迁移执行结果
 */
export class MigrationResult {
  /** 迁移版本号 */
  version: number = 0

  /** 是否成功 */
  success: boolean = false

  /** 执行时间（毫秒） */
  executionTime: number = 0

  /** 错误信息（如果失败） */
  errorMessage: string = ''

  constructor(version: number, success: boolean, executionTime: number, errorMessage?: string) {
    this.version = version
    this.success = success
    this.executionTime = executionTime
    this.errorMessage = errorMessage ? errorMessage : ''
  }
}

/**
 * 迁移方向枚举
 */
export enum MigrationDirection {
  /** 升级 */
  UP = 'UP',
  /** 回滚 */
  DOWN = 'DOWN'
}
