/**
 * 关系类型枚举
 * 定义实体间的关联关系类型
 */

export enum RelationType {
  /** 一对一关系 */
  ONE_TO_ONE = 'ONE_TO_ONE',
  /** 一对多关系 */
  ONE_TO_MANY = 'ONE_TO_MANY',
  /** 多对一关系 */
  MANY_TO_ONE = 'MANY_TO_ONE',
  /** 多对多关系 */
  MANY_TO_MANY = 'MANY_TO_MANY'
}
