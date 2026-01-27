/**
 * RdbPredicates 构建器
 * 将 QueryBuilder 的条件转换为 RdbPredicates
 */

import { relationalStore } from '@kit.ArkData'
import { ConditionOperator } from '../types/ConditionOperator'
import { ValueType } from '../types/ValueTypes'
import { WhereCondition, LogicalOperator } from './WhereCondition'
import { QueryBuilder } from './QueryBuilder'
import { PredicateBuildError } from '../errors/QueryError'

/**
 * Predicates 构建结果
 */
export class PredicateBuildResult {
  /** 构建的 RdbPredicates */
  predicates: relationalStore.RdbPredicates | null = null
  /** 是否成功 */
  success: boolean = false
  /** 错误信息 */
  errorMessage: string = ''
  /** 构建描述（用于调试） */
  description: string = ''

  constructor() {
  }

  /**
   * 创建成功结果
   */
  static createSuccess(predicates: relationalStore.RdbPredicates, description: string): PredicateBuildResult {
    const result = new PredicateBuildResult()
    result.predicates = predicates
    result.success = true
    result.description = description
    return result
  }

  /**
   * 创建失败结果
   */
  static createFailure(errorMessage: string): PredicateBuildResult {
    const result = new PredicateBuildResult()
    result.success = false
    result.errorMessage = errorMessage
    return result
  }
}

/**
 * RdbPredicates 构建器
 * 负责将 QueryBuilder 的条件转换为 HarmonyOS RdbPredicates
 */
export class PredicateBuilder {
  /**
   * 从 QueryBuilder 构建 RdbPredicates
   * @param queryBuilder 查询构建器
   * @returns 构建结果
   */
  static build(queryBuilder: QueryBuilder): PredicateBuildResult {
    try {
      const tableName = queryBuilder.getTableName()
      const predicates = new relationalStore.RdbPredicates(tableName)
      const descriptions: Array<string> = []

      descriptions.push(`表名: ${tableName}`)

      // 应用 WHERE 条件（包括软删除条件）
      const conditions = queryBuilder.getAllConditions()
      for (let i = 0; i < conditions.length; i++) {
        const condition = conditions[i]

        // 处理逻辑连接符（第一个条件不需要）
        if (i > 0) {
          if (condition.logicalOperator === LogicalOperator.OR) {
            predicates.or()
            descriptions.push('OR')
          } else {
            predicates.and()
            descriptions.push('AND')
          }
        }

        // 应用条件
        const condDesc = PredicateBuilder.applyCondition(predicates, condition)
        descriptions.push(condDesc)
      }

      // 应用排序
      const orderByColumns = queryBuilder.getOrderByColumns()
      for (let i = 0; i < orderByColumns.length; i++) {
        const orderBy = orderByColumns[i]
        if (orderBy.direction === 'ASC') {
          predicates.orderByAsc(orderBy.column)
          descriptions.push(`ORDER BY ${orderBy.column} ASC`)
        } else {
          predicates.orderByDesc(orderBy.column)
          descriptions.push(`ORDER BY ${orderBy.column} DESC`)
        }
      }

      // 应用分页
      const limitValue = queryBuilder.getLimitValue()
      const offsetValue = queryBuilder.getOffsetValue()
      if (limitValue > 0) {
        predicates.limitAs(limitValue)
        descriptions.push(`LIMIT ${limitValue}`)
      }
      if (offsetValue > 0) {
        predicates.offsetAs(offsetValue)
        descriptions.push(`OFFSET ${offsetValue}`)
      }

      return PredicateBuildResult.createSuccess(predicates, descriptions.join('\n'))

    } catch (e) {
      const error = e as Error
      return PredicateBuildResult.createFailure(error.message)
    }
  }

  /**
   * 应用单个条件到 RdbPredicates
   * @param predicates RdbPredicates 实例
   * @param condition 条件
   * @returns 条件描述
   */
  private static applyCondition(predicates: relationalStore.RdbPredicates, condition: WhereCondition): string {
    const column = condition.column
    const value = condition.value

    switch (condition.operator) {
      case ConditionOperator.EQUAL:
        predicates.equalTo(column, PredicateBuilder.singleValueToPredicateValue(value))
        return `${column} = ${PredicateBuilder.singleValueToString(value)}`

      case ConditionOperator.NOT_EQUAL:
        predicates.notEqualTo(column, PredicateBuilder.singleValueToPredicateValue(value))
        return `${column} != ${PredicateBuilder.singleValueToString(value)}`

      case ConditionOperator.GREATER:
        predicates.greaterThan(column, PredicateBuilder.singleValueToPredicateValue(value))
        return `${column} > ${PredicateBuilder.singleValueToString(value)}`

      case ConditionOperator.LESS:
        predicates.lessThan(column, PredicateBuilder.singleValueToPredicateValue(value))
        return `${column} < ${PredicateBuilder.singleValueToString(value)}`

      case ConditionOperator.GREATER_EQUAL:
        predicates.greaterThanOrEqualTo(column, PredicateBuilder.singleValueToPredicateValue(value))
        return `${column} >= ${PredicateBuilder.singleValueToString(value)}`

      case ConditionOperator.LESS_EQUAL:
        predicates.lessThanOrEqualTo(column, PredicateBuilder.singleValueToPredicateValue(value))
        return `${column} <= ${PredicateBuilder.singleValueToString(value)}`

      case ConditionOperator.LIKE:
        predicates.like(column, PredicateBuilder.valueToString(value))
        return `${column} LIKE ${PredicateBuilder.singleValueToString(value)}`

      case ConditionOperator.IN:
        if (Array.isArray(value)) {
          const inValues = PredicateBuilder.toPredicateArray(value)
          predicates.in(column, inValues)
          return `${column} IN (${PredicateBuilder.arrayToString(value)})`
        }
        return `${column} IN ()`

      case ConditionOperator.NOT_IN:
        if (Array.isArray(value)) {
          const notInValues = PredicateBuilder.toPredicateArray(value)
          predicates.notIn(column, notInValues)
          return `${column} NOT IN (${PredicateBuilder.arrayToString(value)})`
        }
        return `${column} NOT IN ()`

      case ConditionOperator.BETWEEN:
        const minValue = PredicateBuilder.singleValueToPredicateValue(value)
        const maxValue = PredicateBuilder.singleValueToPredicateValue(condition.secondValue)
        predicates.between(column, minValue, maxValue)
        return `${column} BETWEEN ${PredicateBuilder.singleValueToString(value)} AND ${PredicateBuilder.singleValueToString(condition.secondValue)}`

      case ConditionOperator.IS_NULL:
        predicates.isNull(column)
        return `${column} IS NULL`

      case ConditionOperator.IS_NOT_NULL:
        predicates.isNotNull(column)
        return `${column} IS NOT NULL`

      default:
        throw new PredicateBuildError('unknown', `不支持的操作符: ${condition.operator}`)
    }
  }

  /**
   * 将单个 ValueType 转换为 RdbPredicates 支持的值类型
   * 用于非数组类型的条件值
   */
  private static singleValueToPredicateValue(value: ValueType | Array<ValueType> | null): relationalStore.ValueType {
    if (value === null) {
      return null
    }
    if (Array.isArray(value)) {
      // 如果是数组，返回 null（不应该用于单值条件）
      return null
    }
    if (typeof value === 'string') {
      return value
    }
    if (typeof value === 'number') {
      return value
    }
    if (typeof value === 'boolean') {
      return value ? 1 : 0
    }
    return null
  }

  /**
   * 将单个值转换为字符串（用于描述）
   */
  private static singleValueToString(value: ValueType | Array<ValueType> | null): string {
    if (value === null) {
      return 'NULL'
    }
    if (Array.isArray(value)) {
      return PredicateBuilder.arrayToString(value)
    }
    if (typeof value === 'string') {
      return `'${value}'`
    }
    return String(value)
  }

  /**
   * 将值转换为字符串（用于 LIKE 条件）
   */
  private static valueToString(value: ValueType | Array<ValueType> | null): string {
    if (value === null) {
      return ''
    }
    if (Array.isArray(value)) {
      return ''
    }
    if (typeof value === 'string') {
      return value
    }
    return String(value)
  }

  /**
   * 将 ValueType 数组转换为 RdbPredicates 支持的数组
   */
  private static toPredicateArray(values: Array<ValueType>): Array<relationalStore.ValueType> {
    const result: Array<relationalStore.ValueType> = []
    for (let i = 0; i < values.length; i++) {
      const v = values[i]
      if (v === null) {
        result.push(null)
      } else if (typeof v === 'string') {
        result.push(v)
      } else if (typeof v === 'number') {
        result.push(v)
      } else if (typeof v === 'boolean') {
        result.push(v ? 1 : 0)
      } else {
        result.push(null)
      }
    }
    return result
  }

  /**
   * 将数组转换为字符串（用于描述）
   */
  private static arrayToString(values: Array<ValueType>): string {
    const strs: Array<string> = []
    for (let i = 0; i < values.length; i++) {
      strs.push(PredicateBuilder.valueToString(values[i]))
    }
    return strs.join(', ')
  }

  /**
   * 获取条件操作符的描述
   * @param operator 操作符
   * @returns 描述字符串
   */
  static getOperatorDescription(operator: ConditionOperator): string {
    switch (operator) {
      case ConditionOperator.EQUAL:
        return 'equalTo()'
      case ConditionOperator.NOT_EQUAL:
        return 'notEqualTo()'
      case ConditionOperator.GREATER:
        return 'greaterThan()'
      case ConditionOperator.LESS:
        return 'lessThan()'
      case ConditionOperator.GREATER_EQUAL:
        return 'greaterThanOrEqualTo()'
      case ConditionOperator.LESS_EQUAL:
        return 'lessThanOrEqualTo()'
      case ConditionOperator.LIKE:
        return 'like()'
      case ConditionOperator.IN:
        return 'in()'
      case ConditionOperator.NOT_IN:
        return 'notIn()'
      case ConditionOperator.BETWEEN:
        return 'between()'
      case ConditionOperator.IS_NULL:
        return 'isNull()'
      case ConditionOperator.IS_NOT_NULL:
        return 'isNotNull()'
      default:
        return '未知操作符'
    }
  }

  /**
   * 从 QueryBuilder 构建 RdbPredicates（不包含分页参数）
   * 用于分页查询时获取总数
   * @param queryBuilder 查询构建器
   * @returns 构建结果
   */
  static buildWithoutPagination(queryBuilder: QueryBuilder): PredicateBuildResult {
    try {
      const tableName = queryBuilder.getTableName()
      const predicates = new relationalStore.RdbPredicates(tableName)
      const descriptions: Array<string> = []

      descriptions.push(`表名: ${tableName}`)

      // 应用 WHERE 条件（包括软删除条件）
      const conditions = queryBuilder.getAllConditions()
      for (let i = 0; i < conditions.length; i++) {
        const condition = conditions[i]

        // 处理逻辑连接符（第一个条件不需要）
        if (i > 0) {
          if (condition.logicalOperator === LogicalOperator.OR) {
            predicates.or()
            descriptions.push('OR')
          } else {
            predicates.and()
            descriptions.push('AND')
          }
        }

        // 应用条件
        const condDesc = PredicateBuilder.applyCondition(predicates, condition)
        descriptions.push(condDesc)
      }

      // 不应用排序和分页，只用于 COUNT 查询

      return PredicateBuildResult.createSuccess(predicates, descriptions.join('\n'))

    } catch (e) {
      const error = e as Error
      return PredicateBuildResult.createFailure(error.message)
    }
  }
}
