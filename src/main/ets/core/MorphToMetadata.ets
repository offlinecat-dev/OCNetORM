/**
 * 多态单值关系元数据
 * 用于描述 sourceEntity 通过 idColumn + typeColumn 关联到动态目标实体
 */

import { RelationMetadata } from './RelationMetadata'
import { RelationType } from '../types/RelationType'

export class MorphToMetadata extends RelationMetadata {
  /** 多态 ID 字段（源实体上的外键值字段） */
  idColumn: string = ''
  /** 多态类型字段（源实体上的类型字段） */
  typeColumn: string = ''
  /** 类型值到实体名映射（可选） */
  typeMap: Record<string, string> = {}

  constructor(
    sourceEntity: string,
    propertyName: string,
    idColumn: string,
    typeColumn: string,
    typeMap: Record<string, string> = {}
  ) {
    super(RelationType.MORPH_TO, sourceEntity, '', propertyName, idColumn)
    this.idColumn = idColumn
    this.typeColumn = typeColumn
    this.typeMap = typeMap
  }

  resolveTargetEntity(typeValue: string): string {
    const mappedEntity = this.typeMap[typeValue]
    if (mappedEntity !== undefined && mappedEntity.length > 0) {
      return mappedEntity
    }
    return typeValue
  }
}
