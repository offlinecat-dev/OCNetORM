/**
 * ValuesBucket 数据结构
 * 用于数据库插入/更新操作的键值对
 */

import { DbValueType } from '../types/ValueTypes'

/**
 * ValuesBucket 类型定义
 * 用于数据库插入/更新操作的键值对
 */
export class ValuesBucket {
  private data: Map<string, DbValueType> = new Map()

  /**
   * 设置值
   * @param key 键名
   * @param value 值
   */
  set(key: string, value: DbValueType): void {
    this.data.set(key, value)
  }

  /**
   * 获取值
   * @param key 键名
   * @returns 值
   */
  get(key: string): DbValueType {
    const value = this.data.get(key)
    if (value === undefined) {
      return null
    }
    return value
  }

  /**
   * 检查是否包含键
   * @param key 键名
   * @returns 是否包含
   */
  has(key: string): boolean {
    return this.data.has(key)
  }

  /**
   * 获取所有键
   * @returns 键数组
   */
  keys(): Array<string> {
    const result: Array<string> = []
    this.data.forEach((_, key) => {
      result.push(key)
    })
    return result
  }

  /**
   * 获取数据 Map
   * @returns 数据 Map
   */
  getData(): Map<string, DbValueType> {
    return this.data
  }
}
