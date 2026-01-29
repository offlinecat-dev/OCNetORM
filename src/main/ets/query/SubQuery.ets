/**
 * 子查询构建器
 * 用于构建深层关联过滤条件
 */

import { ConditionOperator } from '../types/ConditionOperator'
import { ValueType } from '../types/ValueTypes'
import { WhereCondition, LogicalOperator } from './WhereCondition'
import { SubQueryError } from '../errors/QueryError'

/**
 * 子查询构建器类
 * 支持在关联实体上添加过滤条件
 */
export class SubQuery {
  /** 关联关系名称 */
  private relationName: string = ''

  /** 过滤条件列表 */
  private conditions: Array<WhereCondition> = []

  /**
   * 构造函数
   * @param relationName 关联关系名称
   */
  constructor(relationName: string) {
    this.relationName = relationName
  }

  /**
   * 添加过滤条件
   * @param column 列名
   * @param operator 操作符
   * @param value 值
   * @returns 当前实例（支持链式调用）
   */
  where(column: string, operator: ConditionOperator, value: ValueType): SubQuery {
    const condition = new WhereCondition()
    condition.column = column
    condition.operator = operator
    condition.value = value
    condition.logicalOperator = LogicalOperator.AND
    this.conditions.push(condition)
    return this
  }

  /**
   * 添加 AND 过滤条件
   * @param column 列名
   * @param operator 操作符
   * @param value 值
   * @returns 当前实例（支持链式调用）
   */
  andWhere(column: string, operator: ConditionOperator, value: ValueType): SubQuery {
    const condition = new WhereCondition()
    condition.column = column
    condition.operator = operator
    condition.value = value
    condition.logicalOperator = LogicalOperator.AND
    this.conditions.push(condition)
    return this
  }

  /**
   * 添加 OR 过滤条件
   * @param column 列名
   * @param operator 操作符
   * @param value 值
   * @returns 当前实例（支持链式调用）
   */
  orWhere(column: string, operator: ConditionOperator, value: ValueType): SubQuery {
    const condition = new WhereCondition()
    condition.column = column
    condition.operator = operator
    condition.value = value
    condition.logicalOperator = LogicalOperator.OR
    this.conditions.push(condition)
    return this
  }

  /**
   * 添加 IN 条件
   * @param column 列名
   * @param values 值数组
   * @returns 当前实例（支持链式调用）
   */
  whereIn(column: string, values: Array<ValueType>): SubQuery {
    if (values.length === 0) {
      throw new SubQueryError('IN 条件不能为空')
    }
    const condition = WhereCondition.inValues(column, values)
    condition.logicalOperator = LogicalOperator.AND
    this.conditions.push(condition)
    return this
  }

  /**
   * 添加 IS NULL 条件
   * @param column 列名
   * @returns 当前实例（支持链式调用）
   */
  whereNull(column: string): SubQuery {
    const condition = WhereCondition.isNull(column)
    condition.logicalOperator = LogicalOperator.AND
    this.conditions.push(condition)
    return this
  }

  /**
   * 添加 IS NOT NULL 条件
   * @param column 列名
   * @returns 当前实例（支持链式调用）
   */
  whereNotNull(column: string): SubQuery {
    const condition = WhereCondition.isNotNull(column)
    condition.logicalOperator = LogicalOperator.AND
    this.conditions.push(condition)
    return this
  }

  /**
   * 添加 BETWEEN 条件
   * @param column 列名
   * @param min 最小值
   * @param max 最大值
   * @returns 当前实例（支持链式调用）
   */
  whereBetween(column: string, min: ValueType, max: ValueType): SubQuery {
    const condition = WhereCondition.between(column, min, max)
    condition.logicalOperator = LogicalOperator.AND
    this.conditions.push(condition)
    return this
  }

  /**
   * 添加 LIKE 条件
   * @param column 列名
   * @param pattern 匹配模式
   * @returns 当前实例（支持链式调用）
   */
  whereLike(column: string, pattern: string): SubQuery {
    const condition = WhereCondition.like(column, pattern)
    condition.logicalOperator = LogicalOperator.AND
    this.conditions.push(condition)
    return this
  }

  /**
   * 获取所有过滤条件
   * @returns 条件数组
   */
  getConditions(): Array<WhereCondition> {
    return this.conditions
  }

  /**
   * 获取关联关系名称
   * @returns 关联关系名称
   */
  getRelationName(): string {
    return this.relationName
  }

  /**
   * 检查是否有过滤条件
   * @returns 是否有条件
   */
  hasConditions(): boolean {
    return this.conditions.length > 0
  }

  /**
   * 获取条件描述（用于调试）
   * @returns 条件描述字符串
   */
  getDescription(): string {
    if (this.conditions.length === 0) {
      return `SubQuery(${this.relationName}): 无条件`
    }

    const conditionStrs: Array<string> = []
    for (let i = 0; i < this.conditions.length; i++) {
      const cond = this.conditions[i]
      if (i > 0) {
        conditionStrs.push(cond.logicalOperator + ' ' + cond.toString())
      } else {
        conditionStrs.push(cond.toString())
      }
    }
    return `SubQuery(${this.relationName}): ${conditionStrs.join(' ')}`
  }
}

/**
 * 子查询回调函数类型
 */
export type SubQueryCallback = (subQuery: SubQuery) => void
