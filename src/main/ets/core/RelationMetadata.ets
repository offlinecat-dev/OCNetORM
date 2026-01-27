/**
 * 关系元数据类
 * 存储实体间关联关系的定义信息
 */

import { RelationType } from '../types/RelationType'

/**
 * 级联配置选项
 */
export interface CascadeOptions {
  /** 是否级联插入 */
  insert?: boolean
  /** 是否级联更新 */
  update?: boolean
  /** 是否级联删除 */
  remove?: boolean
}

/**
 * 级联设置
 * - true: 启用全部级联
 * - CascadeOptions: 按操作类型控制
 */
export type CascadeSetting = boolean | CascadeOptions

/**
 * 关系元数据类
 * 用于描述实体之间的关联关系
 */
export class RelationMetadata {
  /** 关系类型 */
  type: RelationType = RelationType.ONE_TO_MANY
  /** 源实体名称 */
  sourceEntity: string = ''
  /** 目标实体名称 */
  targetEntity: string = ''
  /** 在源实体中的属性名 */
  propertyName: string = ''
  /** 外键列名（在目标表或源表中） */
  inverseKey: string = ''
  /** 级联配置 */
  cascade: CascadeSetting | null = null
  /**
   * 外键位置（仅用于 ONE_TO_ONE 关系）
   * - 'source': 外键在源实体表中，根据源实体的外键值查询目标实体
   * - 'target': 外键在目标实体表中，根据目标实体的外键值查询源实体
   */
  foreignKeySide: string = 'source'

  /**
   * 构造函数
   * @param type 关系类型
   * @param sourceEntity 源实体名称
   * @param targetEntity 目标实体名称
   * @param propertyName 在源实体中的属性名
   * @param inverseKey 外键列名
   * @param foreignKeySide 外键位置（仅用于 ONE_TO_ONE 关系，默认 'source'）
   * @param cascade 级联配置
   */
  constructor(
    type: RelationType,
    sourceEntity: string,
    targetEntity: string,
    propertyName: string,
    inverseKey: string,
    foreignKeySide: string = 'source',
    cascade: CascadeSetting | null = null
  ) {
    this.type = type
    this.sourceEntity = sourceEntity
    this.targetEntity = targetEntity
    this.propertyName = propertyName
    this.inverseKey = inverseKey
    this.foreignKeySide = foreignKeySide
    this.cascade = cascade
  }
}
