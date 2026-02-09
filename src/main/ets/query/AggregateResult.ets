/**
 * 聚合查询结果类
 * 用于存储 GROUP BY 查询的结果
 */

import { ValueType } from '../types/ValueTypes'

/**
 * 聚合结果行
 * 存储单行聚合查询结果
 */
export class AggregateRow {
  /** 数据存储 */
  private data: Map<string, ValueType> = new Map()

  /**
   * 设置列值
   * @param key 列名或别名
   * @param value 值
   */
  set(key: string, value: ValueType): void {
    this.data.set(key, value)
  }

  /**
   * 获取列值
   * @param key 列名或别名
   * @returns 值，不存在返回 null
   */
  get(key: string): ValueType {
    const value = this.data.get(key)
    return value !== undefined ? value : null
  }

  /**
   * 获取数值类型的列值
   * @param key 列名或别名
   * @returns 数值，不存在或无法转换返回 0
   */
  getNumber(key: string): number {
    const value = this.get(key)
    if (value === null) {
      return 0
    }
    if (typeof value === 'number') {
      return value
    }
    const num = Number(value)
    return isNaN(num) ? 0 : num
  }

  /**
   * 获取字符串类型的列值
   * @param key 列名或别名
   * @returns 字符串，不存在返回空字符串
   */
  getString(key: string): string {
    const value = this.get(key)
    if (value === null) {
      return ''
    }
    return String(value)
  }

  /**
   * 检查是否包含指定列
   * @param key 列名或别名
   * @returns 是否包含
   */
  has(key: string): boolean {
    return this.data.has(key)
  }

  /**
   * 获取所有列名
   * @returns 列名数组
   */
  keys(): Array<string> {
    const result: Array<string> = []
    this.data.forEach((_, key) => {
      result.push(key)
    })
    return result
  }

  /**
   * 转换为普通对象
   * @returns 键值对对象
   */
  toObject(): Record<string, ValueType> {
    const obj: Record<string, ValueType> = {}
    this.data.forEach((value, key) => {
      obj[key] = value
    })
    return obj
  }
}

/**
 * 聚合查询结果集
 * 存储 GROUP BY 查询的所有结果行
 */
export class AggregateResult {
  /** 结果行数组 */
  private rows: Array<AggregateRow> = []

  /**
   * 添加结果行
   * @param row 聚合结果行
   */
  addRow(row: AggregateRow): void {
    this.rows.push(row)
  }

  /**
   * 获取所有结果行
   * @returns 结果行数组
   */
  getRows(): Array<AggregateRow> {
    return this.rows
  }

  /**
   * 获取指定索引的结果行
   * @param index 索引
   * @returns 结果行，索引越界返回 null
   */
  getRow(index: number): AggregateRow | null {
    if (index < 0 || index >= this.rows.length) {
      return null
    }
    return this.rows[index]
  }

  /**
   * 获取结果行数量
   * @returns 行数
   */
  count(): number {
    return this.rows.length
  }

  /**
   * 检查结果是否为空
   * @returns 是否为空
   */
  isEmpty(): boolean {
    return this.rows.length === 0
  }

  /**
   * 转换为对象数组
   * @returns 对象数组
   */
  toArray(): Array<Record<string, ValueType>> {
    const result: Array<Record<string, ValueType>> = []
    for (let i = 0; i < this.rows.length; i++) {
      result.push(this.rows[i].toObject())
    }
    return result
  }

  /**
   * 创建空结果
   * @returns 空的聚合结果
   */
  static empty(): AggregateResult {
    return new AggregateResult()
  }
}
