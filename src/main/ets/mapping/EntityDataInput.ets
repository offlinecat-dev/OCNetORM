/**
 * 实体数据输入类
 * 用于 EntityData.from() 方法的输入参数
 * 提供一种简洁的方式来构建实体数据
 */

import { ValueType } from '../types/ValueTypes'

/**
 * 实体数据输入类
 * 用于存储键值对，作为 EntityData.from() 的输入
 */
export class EntityDataInput {
  /** 数据存储 */
  private data: Map<string, ValueType> = new Map()

  /**
   * 设置值
   * @param key 键名（对应实体属性名）
   * @param value 值
   */
  set(key: string, value: ValueType): void {
    this.data.set(key, value)
  }

  /**
   * 获取值
   * @param key 键名
   * @returns 值，如果不存在返回 null
   */
  get(key: string): ValueType {
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
   * 获取键值对数量
   * @returns 数量
   */
  size(): number {
    return this.data.size
  }

  /**
   * 清空所有数据
   */
  clear(): void {
    this.data.clear()
  }

  /**
   * 删除指定键
   * @param key 键名
   */
  remove(key: string): void {
    this.data.delete(key)
  }

  /**
   * 创建 EntityDataInput 实例的便捷方法
   * @returns 新的 EntityDataInput 实例
   */
  static create(): EntityDataInput {
    return new EntityDataInput()
  }
}
