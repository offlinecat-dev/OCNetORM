/**
 * 迁移日志管理器
 * 负责在 _migrations 表中记录迁移/自动变更信息
 */

import { relationalStore } from '@kit.ArkData'
import { ExecutionError } from '../errors/DatabaseError'

/**
 * 迁移日志记录
 */
export interface MigrationLogRecord {
  /** 迁移版本（可选，手动迁移时使用） */
  version?: number
  /** 迁移名称或描述（可选） */
  name?: string
  /** 记录类型（例如: MIGRATION/AUTO_SCHEMA） */
  type: string
  /** 迁移方向（UP/DOWN） */
  direction?: string
  /** 目标表名 */
  tableName?: string
  /** 目标列名 */
  columnName?: string
  /** 执行的 SQL */
  sql?: string
  /** 摘要信息 */
  summary?: string
  /** 是否成功 */
  success?: boolean
  /** 错误信息 */
  errorMessage?: string
  /** 创建时间（时间戳） */
  createdAt?: number
}

/**
 * 迁移日志管理器
 */
export class MigrationLogManager {
  private tableName: string

  constructor(tableName?: string) {
    this.tableName = tableName ? tableName : '_migrations'
  }

  private escapeIdentifier(identifier: string): string {
    const escaped = identifier.replace(/"/g, '""')
    return `"${escaped}"`
  }

  private sanitizeLogIdentifier(value?: string): string | null {
    if (!value) {
      return null
    }
    const trimmed = value.trim()
    if (trimmed.length === 0) {
      return null
    }
    const cleaned = trimmed.replace(/[\x00-\x1F\x7F]/g, '')
    if (cleaned.length === 0) {
      return null
    }
    return cleaned.length > 128 ? cleaned.slice(0, 128) : cleaned
  }

  getTableName(): string {
    return this.tableName
  }

  async ensureTable(store: relationalStore.RdbStore): Promise<void> {
    const escapedTableName = this.escapeIdentifier(this.tableName)
    const createSql = `CREATE TABLE IF NOT EXISTS ${escapedTableName} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      version INTEGER,
      name TEXT,
      type TEXT NOT NULL,
      direction TEXT,
      table_name TEXT,
      column_name TEXT,
      sql TEXT,
      summary TEXT,
      success INTEGER,
      error_message TEXT,
      created_at INTEGER NOT NULL
    )`

    try {
      await store.executeSql(createSql)
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      throw new ExecutionError(createSql, `创建迁移日志表失败: ${errorMessage}`)
    }
  }

  async log(store: relationalStore.RdbStore, record: MigrationLogRecord): Promise<void> {
    await this.ensureTable(store)

    const safeTableName = this.sanitizeLogIdentifier(record.tableName)
    const safeColumnName = this.sanitizeLogIdentifier(record.columnName)

    const values: relationalStore.ValuesBucket = {
      'version': record.version !== undefined ? record.version : null,
      'name': record.name !== undefined ? record.name : null,
      'type': record.type,
      'direction': record.direction !== undefined ? record.direction : null,
      'table_name': safeTableName,
      'column_name': safeColumnName,
      'sql': record.sql !== undefined ? record.sql : null,
      'summary': record.summary !== undefined ? record.summary : null,
      'success': record.success !== undefined ? (record.success ? 1 : 0) : null,
      'error_message': record.errorMessage !== undefined ? record.errorMessage : null,
      'created_at': record.createdAt !== undefined ? record.createdAt : Date.now()
    }

    try {
      await store.insert(this.tableName, values)
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      throw new ExecutionError('INSERT', `写入迁移日志失败: ${errorMessage}`)
    }
  }
}
