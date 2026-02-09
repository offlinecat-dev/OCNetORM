/**
 * ResultSetRow 数据结构
 * 模拟数据库查询结果的单行数据
 */

import { DbValueType } from '../types/ValueTypes'


/**
 * 结果集行数据类
 * 模拟数据库查询结果的单行数据
 */
export class ResultSetRow {
  private data: Map<string, DbValueType> = new Map()

  /**
   * 设置列值
   * @param columnName 列名
   * @param value 值
   */
  set(columnName: string, value: DbValueType): void {
    this.data.set(columnName, value)
  }

  /**
   * 获取列值
   * @param columnName 列名
   * @returns 值
   */
  get(columnName: string): DbValueType {
    const value = this.data.get(columnName)
    if (value === undefined) {
      return null
    }
    return value
  }

  /**
   * 检查是否包含列
   * @param columnName 列名
   * @returns 是否包含
   */
  has(columnName: string): boolean {
    return this.data.has(columnName)
  }

  /**
   * 获取所有列名
   * @returns 列名数组
   */
  getColumnNames(): Array<string> {
    const result: Array<string> = []
    this.data.forEach((_, key) => {
      result.push(key)
    })
    return result
  }
}
