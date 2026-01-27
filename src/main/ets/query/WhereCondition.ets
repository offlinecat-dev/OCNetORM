/**
 * 查询条件类
 * 表示单个 WHERE 条件
 */

import { ConditionOperator } from '../types/ConditionOperator'
import { ValueType } from '../types/ValueTypes'

/**
 * 逻辑连接符
 * 用于连接多个条件
 */
export enum LogicalOperator {
  /** 与 */
  AND = 'AND',
  /** 或 */
  OR = 'OR'
}

/**
 * WHERE 条件类
 * 存储单个查询条件的所有信息
 */
export class WhereCondition {
  /** 列名 */
  column: string = ''

  /** 条件操作符 */
  operator: ConditionOperator = ConditionOperator.EQUAL

  /** 条件值（用于大多数操作符） */
  value: ValueType | Array<ValueType> | null = null

  /** 第二个值（用于 BETWEEN 操作符） */
  secondValue: ValueType | null = null

  /** 逻辑连接符（用于连接多个条件） */
  logicalOperator: LogicalOperator = LogicalOperator.AND

  /**
   * 创建等于条件
   * @param column 列名
   * @param value 值
   * @returns WhereCondition 实例
   */
  static equal(column: string, value: ValueType): WhereCondition {
    const condition = new WhereCondition()
    condition.column = column
    condition.operator = ConditionOperator.EQUAL
    condition.value = value
    return condition
  }

  /**
   * 创建不等于条件
   * @param column 列名
   * @param value 值
   * @returns WhereCondition 实例
   */
  static notEqual(column: string, value: ValueType): WhereCondition {
    const condition = new WhereCondition()
    condition.column = column
    condition.operator = ConditionOperator.NOT_EQUAL
    condition.value = value
    return condition
  }

  /**
   * 创建大于条件
   * @param column 列名
   * @param value 值
   * @returns WhereCondition 实例
   */
  static greaterThan(column: string, value: ValueType): WhereCondition {
    const condition = new WhereCondition()
    condition.column = column
    condition.operator = ConditionOperator.GREATER
    condition.value = value
    return condition
  }

  /**
   * 创建小于条件
   * @param column 列名
   * @param value 值
   * @returns WhereCondition 实例
   */
  static lessThan(column: string, value: ValueType): WhereCondition {
    const condition = new WhereCondition()
    condition.column = column
    condition.operator = ConditionOperator.LESS
    condition.value = value
    return condition
  }

  /**
   * 创建大于等于条件
   * @param column 列名
   * @param value 值
   * @returns WhereCondition 实例
   */
  static greaterOrEqual(column: string, value: ValueType): WhereCondition {
    const condition = new WhereCondition()
    condition.column = column
    condition.operator = ConditionOperator.GREATER_EQUAL
    condition.value = value
    return condition
  }

  /**
   * 创建小于等于条件
   * @param column 列名
   * @param value 值
   * @returns WhereCondition 实例
   */
  static lessOrEqual(column: string, value: ValueType): WhereCondition {
    const condition = new WhereCondition()
    condition.column = column
    condition.operator = ConditionOperator.LESS_EQUAL
    condition.value = value
    return condition
  }

  /**
   * 创建 LIKE 条件
   * @param column 列名
   * @param pattern 匹配模式
   * @returns WhereCondition 实例
   */
  static like(column: string, pattern: string): WhereCondition {
    const condition = new WhereCondition()
    condition.column = column
    condition.operator = ConditionOperator.LIKE
    condition.value = pattern
    return condition
  }

  /**
   * 创建 IN 条件
   * @param column 列名
   * @param values 值数组
   * @returns WhereCondition 实例
   */
  static inValues(column: string, values: Array<ValueType>): WhereCondition {
    const condition = new WhereCondition()
    condition.column = column
    condition.operator = ConditionOperator.IN
    condition.value = values
    return condition
  }

  /**
   * 创建 NOT IN 条件
   * @param column 列名
   * @param values 值数组
   * @returns WhereCondition 实例
   */
  static notInValues(column: string, values: Array<ValueType>): WhereCondition {
    const condition = new WhereCondition()
    condition.column = column
    condition.operator = ConditionOperator.NOT_IN
    condition.value = values
    return condition
  }

  /**
   * 创建 BETWEEN 条件
   * @param column 列名
   * @param min 最小值
   * @param max 最大值
   * @returns WhereCondition 实例
   */
  static between(column: string, min: ValueType, max: ValueType): WhereCondition {
    const condition = new WhereCondition()
    condition.column = column
    condition.operator = ConditionOperator.BETWEEN
    condition.value = min
    condition.secondValue = max
    return condition
  }

  /**
   * 创建 IS NULL 条件
   * @param column 列名
   * @returns WhereCondition 实例
   */
  static isNull(column: string): WhereCondition {
    const condition = new WhereCondition()
    condition.column = column
    condition.operator = ConditionOperator.IS_NULL
    condition.value = null
    return condition
  }

  /**
   * 创建 IS NOT NULL 条件
   * @param column 列名
   * @returns WhereCondition 实例
   */
  static isNotNull(column: string): WhereCondition {
    const condition = new WhereCondition()
    condition.column = column
    condition.operator = ConditionOperator.IS_NOT_NULL
    condition.value = null
    return condition
  }

  /**
   * 设置逻辑连接符为 AND
   * @returns 当前实例
   */
  and(): WhereCondition {
    this.logicalOperator = LogicalOperator.AND
    return this
  }

  /**
   * 设置逻辑连接符为 OR
   * @returns 当前实例
   */
  or(): WhereCondition {
    this.logicalOperator = LogicalOperator.OR
    return this
  }

  /**
   * 获取条件的字符串表示（用于调试）
   * @returns 条件描述字符串
   */
  toString(): string {
    let valueStr: string
    if (this.value === null) {
      valueStr = 'NULL'
    } else if (Array.isArray(this.value)) {
      const arr = this.value as Array<ValueType>
      const strArr: Array<string> = []
      for (let i = 0; i < arr.length; i++) {
        const v = arr[i]
        if (v === null) {
          strArr.push('NULL')
        } else {
          strArr.push(String(v))
        }
      }
      valueStr = '[' + strArr.join(', ') + ']'
    } else {
      valueStr = String(this.value)
    }

    if (this.operator === ConditionOperator.BETWEEN) {
      const secondStr = this.secondValue === null ? 'NULL' : String(this.secondValue)
      return `${this.column} ${this.operator} ${valueStr} AND ${secondStr}`
    }

    return `${this.column} ${this.operator} ${valueStr}`
  }
}
