/**
 * ResultSet 工具类
 * 提取 Repository 和 QueryExecutor 中的重复代码
 * 提供统一的 ResultSet 到 ResultSetRow 转换逻辑
 */

import { relationalStore } from '@kit.ArkData'
import { EntityMetadata } from '../core/EntityMetadata'
import { ResultSetRow } from './ResultSetRow'
import { ColumnType } from '../types/ColumnType'
import { DbValueType } from '../types/ValueTypes'

/**
 * ResultSet 工具类
 * 提供静态方法处理 ResultSet 数据转换
 */
export class ResultSetUtils {
  /**
   * 将 ResultSet 当前行转换为 ResultSetRow
   * @param resultSet 查询结果集
   * @param metadata 实体元数据
   * @returns ResultSetRow 对象
   */
  static toRow(resultSet: relationalStore.ResultSet, metadata: EntityMetadata): ResultSetRow {
    const row = new ResultSetRow()
    const columnNames = resultSet.columnNames

    for (let i = 0; i < columnNames.length; i++) {
      const columnName = columnNames[i]
      try {
        const columnIndex = resultSet.getColumnIndex(columnName)

        // 根据列类型获取值
        if (resultSet.isColumnNull(columnIndex)) {
          row.set(columnName, null)
        } else {
          // 尝试获取不同类型的值
          const columnMetadata = metadata.getColumnByName(columnName)
          if (columnMetadata !== null) {
            const value = ResultSetUtils.getValueByType(resultSet, columnIndex, columnMetadata.columnType)
            row.set(columnName, value)
          } else {
            // 默认作为字符串处理
            row.set(columnName, resultSet.getString(columnIndex))
          }
        }
      } catch (e) {
        // 忽略单个列的读取错误，继续处理其他列
        row.set(columnName, null)
      }
    }

    return row
  }

  /**
   * 根据列类型从 ResultSet 获取值
   * @param resultSet 结果集
   * @param columnIndex 列索引
   * @param columnType 列类型
   * @returns 列值
   */
  static getValueByType(
    resultSet: relationalStore.ResultSet,
    columnIndex: number,
    columnType: string
  ): DbValueType {
    try {
      switch (columnType) {
        case ColumnType.INTEGER:
        case 'INTEGER':
          // getLong 返回 number 类型
          return resultSet.getLong(columnIndex) as number
        case ColumnType.REAL:
        case 'REAL':
          return resultSet.getDouble(columnIndex)
        case ColumnType.TEXT:
        case 'TEXT':
          return resultSet.getString(columnIndex)
        case ColumnType.BLOB:
        case 'BLOB':
          return resultSet.getBlob(columnIndex)
        default:
          return resultSet.getString(columnIndex)
      }
    } catch (e) {
      // 获取值失败时返回 null
      return null
    }
  }

  /**
   * 将 ResultSet 所有行转换为 ResultSetRow 数组
   * @param resultSet 查询结果集
   * @param metadata 实体元数据
   * @returns ResultSetRow 数组
   */
  static toRowArray(resultSet: relationalStore.ResultSet, metadata: EntityMetadata): Array<ResultSetRow> {
    const rows: Array<ResultSetRow> = []

    try {
      while (resultSet.goToNextRow()) {
        rows.push(ResultSetUtils.toRow(resultSet, metadata))
      }
    } catch (e) {
      // 遍历结果集失败，返回已处理的行
    }

    return rows
  }

  /**
   * 获取 ResultSet 中指定列的所有值
   * @param resultSet 查询结果集
   * @param columnName 列名
   * @param metadata 实体元数据（可选，用于类型判断）
   * @returns 值数组
   */
  static getColumnValues(
    resultSet: relationalStore.ResultSet,
    columnName: string,
    metadata?: EntityMetadata
  ): Array<DbValueType> {
    const values: Array<DbValueType> = []

    try {
      const columnIndex = resultSet.getColumnIndex(columnName)
      const columnType = metadata ? metadata.getColumnByName(columnName)?.columnType : null

      while (resultSet.goToNextRow()) {
        if (!resultSet.isColumnNull(columnIndex)) {
          if (columnType !== null && columnType !== undefined) {
            values.push(ResultSetUtils.getValueByType(resultSet, columnIndex, columnType))
          } else {
            values.push(ResultSetUtils.getValueByRuntimeType(resultSet, columnIndex))
          }
        }
      }
    } catch (e) {
      // 忽略错误
    }

    return values
  }

  /**
   * 根据 ResultSet 类型信息读取值（无元数据场景）
   * @param resultSet 结果集
   * @param columnIndex 列索引
   * @returns 列值
   */
  static getValueByRuntimeType(
    resultSet: relationalStore.ResultSet,
    columnIndex: number
  ): DbValueType {
    try {
      if (resultSet.isColumnNull(columnIndex)) {
        return null
      }
      const columnType = resultSet.getColumnTypeSync(columnIndex)
      const readBlobValue = (): Uint8Array | null => {
        try {
          const blobValue = resultSet.getBlob(columnIndex)
          return blobValue instanceof Uint8Array ? blobValue : null
        } catch (e) {
          return null
        }
      }

      switch (columnType) {
        case relationalStore.ColumnType.INTEGER:
          const longValue = resultSet.getLong(columnIndex) as number
          if (Number.isNaN(longValue)) {
            const blobValue = readBlobValue()
            return blobValue !== null ? blobValue : resultSet.getString(columnIndex)
          }
          return longValue
        case relationalStore.ColumnType.REAL:
          const doubleValue = resultSet.getDouble(columnIndex)
          if (Number.isNaN(doubleValue)) {
            const blobValue = readBlobValue()
            return blobValue !== null ? blobValue : resultSet.getString(columnIndex)
          }
          return doubleValue
        case relationalStore.ColumnType.BLOB:
          return resultSet.getBlob(columnIndex)
        case relationalStore.ColumnType.NULL:
          return null
        case relationalStore.ColumnType.TEXT:
        default:
          const blobValue = readBlobValue()
          return blobValue !== null ? blobValue : resultSet.getString(columnIndex)
      }
    } catch (e) {
      return null
    }
  }

  /**
   * 安全关闭 ResultSet
   * @param resultSet 结果集
   */
  static safeClose(resultSet: relationalStore.ResultSet | null): void {
    if (resultSet !== null) {
      try {
        resultSet.close()
      } catch (e) {
        // 忽略关闭错误
      }
    }
  }
}
