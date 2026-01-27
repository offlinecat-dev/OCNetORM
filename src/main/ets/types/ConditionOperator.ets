/**
 * 查询条件操作符枚举
 * 定义 QueryBuilder 支持的所有条件操作符
 */

export enum ConditionOperator {
  /** 等于 */
  EQUAL = '=',
  /** 不等于 */
  NOT_EQUAL = '!=',
  /** 大于 */
  GREATER = '>',
  /** 小于 */
  LESS = '<',
  /** 大于等于 */
  GREATER_EQUAL = '>=',
  /** 小于等于 */
  LESS_EQUAL = '<=',
  /** 模糊匹配 */
  LIKE = 'LIKE',
  /** 在集合中 */
  IN = 'IN',
  /** 不在集合中 */
  NOT_IN = 'NOT IN',
  /** 在范围内 */
  BETWEEN = 'BETWEEN',
  /** 为空 */
  IS_NULL = 'IS NULL',
  /** 不为空 */
  IS_NOT_NULL = 'IS NOT NULL'
}
