/**
 * 多对多关系元数据类
 * 继承 RelationMetadata，包含中间表配置信息
 */

import { RelationMetadata } from './RelationMetadata'
import { RelationType } from '../types/RelationType'

/**
 * 多对多关系元数据
 * 用于描述实体之间的多对多关联关系
 */
export class ManyToManyMetadata extends RelationMetadata {
  /** 中间表名 */
  joinTable: string = ''
  /** 源实体在中间表的外键列名 */
  joinSourceKey: string = ''
  /** 目标实体在中间表的外键列名 */
  joinTargetKey: string = ''

  /**
   * 构造函数
   * @param sourceEntity 源实体名称
   * @param targetEntity 目标实体名称
   * @param propertyName 在源实体中的属性名
   * @param joinTable 中间表名
   * @param joinSourceKey 源实体在中间表的外键列名
   * @param joinTargetKey 目标实体在中间表的外键列名
   */
  constructor(
    sourceEntity: string,
    targetEntity: string,
    propertyName: string,
    joinTable: string,
    joinSourceKey: string,
    joinTargetKey: string
  ) {
    super(RelationType.MANY_TO_MANY, sourceEntity, targetEntity, propertyName, '')
    this.joinTable = joinTable
    this.joinSourceKey = joinSourceKey
    this.joinTargetKey = joinTargetKey
  }
}
