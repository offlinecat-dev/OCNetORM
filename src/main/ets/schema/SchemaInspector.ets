/**
 * Schema 检查器
 * 负责从数据库读取当前表结构信息
 */

import { relationalStore } from '@kit.ArkData'
import { ExecutionError } from '../errors/DatabaseError'

/**
 * 列信息
 */
export interface ColumnInfo {
  name: string
  type: string
  notNull: boolean
  defaultValue: string | null
  primaryKey: boolean
}

/**
 * 表信息
 */
export interface TableInfo {
  name: string
  columns: Array<ColumnInfo>
}

/**
 * Schema 检查器
 */
export class SchemaInspector {
  /**
   * 转义 SQL 标识符
   */
  private escapeIdentifier(identifier: string): string {
    const escaped = identifier.replace(/"/g, '""')
    return `"${escaped}"`
  }

  /**
   * 获取当前数据库所有表名
   */
  async getExistingTables(store: relationalStore.RdbStore): Promise<Array<string>> {
    const sql = "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
    let resultSet: relationalStore.ResultSet | null = null
    const tables: Array<string> = []

    try {
      resultSet = await store.querySql(sql)
      while (resultSet.goToNextRow()) {
        const nameIndex = resultSet.getColumnIndex('name')
        if (nameIndex >= 0 && !resultSet.isColumnNull(nameIndex)) {
          tables.push(resultSet.getString(nameIndex))
        }
      }
      return tables
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      throw new ExecutionError(sql, `读取数据库表信息失败: ${errorMessage}`)
    } finally {
      this.closeResultSetSafely(resultSet)
    }
  }

  /**
   * 获取指定表的列信息
   */
  async getTableInfo(store: relationalStore.RdbStore, tableName: string): Promise<TableInfo> {
    const escapedTable = this.escapeIdentifier(tableName)
    const sql = `PRAGMA table_info(${escapedTable})`
    let resultSet: relationalStore.ResultSet | null = null
    const columns: Array<ColumnInfo> = []

    try {
      resultSet = await store.querySql(sql)
      while (resultSet.goToNextRow()) {
        const nameIndex = resultSet.getColumnIndex('name')
        const typeIndex = resultSet.getColumnIndex('type')
        const notNullIndex = resultSet.getColumnIndex('notnull')
        const defaultIndex = resultSet.getColumnIndex('dflt_value')
        const pkIndex = resultSet.getColumnIndex('pk')

        const name = nameIndex >= 0 && !resultSet.isColumnNull(nameIndex)
          ? resultSet.getString(nameIndex)
          : ''
        const type = typeIndex >= 0 && !resultSet.isColumnNull(typeIndex)
          ? resultSet.getString(typeIndex)
          : ''
        const notNull = notNullIndex >= 0 && !resultSet.isColumnNull(notNullIndex)
          ? resultSet.getLong(notNullIndex) === 1
          : false
        const defaultValue = defaultIndex >= 0 && !resultSet.isColumnNull(defaultIndex)
          ? resultSet.getString(defaultIndex)
          : null
        const primaryKey = pkIndex >= 0 && !resultSet.isColumnNull(pkIndex)
          ? resultSet.getLong(pkIndex) === 1
          : false

        if (name) {
          columns.push({
            name,
            type,
            notNull,
            defaultValue,
            primaryKey
          })
        }
      }

      return { name: tableName, columns }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      throw new ExecutionError(sql, `读取表结构失败: ${errorMessage}`)
    } finally {
      this.closeResultSetSafely(resultSet)
    }
  }

  private closeResultSetSafely(resultSet: relationalStore.ResultSet | null): void {
    if (resultSet === null) {
      return
    }
    try {
      resultSet.close()
    } catch (e) {
      // 忽略关闭异常，避免影响主流程
    }
  }
}
