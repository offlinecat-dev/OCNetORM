/**
 * 元数据存储单例
 * 全局管理所有实体的元数据信息
 */

import { EntityMetadata } from './EntityMetadata'
import { ColumnMetadata } from './ColumnMetadata'
import { RelationMetadata } from './RelationMetadata'
import { ManyToManyMetadata } from './ManyToManyMetadata'
import { MorphToMetadata } from './MorphToMetadata'
import { DuplicateEntityError, EntityNotRegisteredError } from '../errors/MetadataError'
import { RelationNotFoundError } from '../errors/RelationError'
import { RelationType } from '../types/RelationType'

/**
 * 元数据存储
 * 单例模式，存储所有已注册实体的元数据
 */
export class MetadataStorage {
  /** 单例实例 */
  private static instance: MetadataStorage = new MetadataStorage()

  /** 实体元数据映射表，键为实体类名 */
  private entities: Map<string, EntityMetadata> = new Map()

  /** 实例到实体名的映射，用于通过实例查找元数据 */
  private instanceEntityMap: Map<string, string> = new Map()

  /** 关联关系映射表，键为源实体名，值为该实体的所有关联关系数组 */
  private relations: Map<string, Array<RelationMetadata>> = new Map()

  /**
   * 私有构造函数，防止外部实例化
   */
  private constructor() {
  }

  /**
   * 获取单例实例
   * @returns MetadataStorage 实例
   */
  static getInstance(): MetadataStorage {
    return MetadataStorage.instance
  }

  /**
   * 注册实体元数据
   * @param entityName 实体类名
   * @param tableName 数据库表名（可选，默认使用实体类名）
   * @throws DuplicateEntityError 如果实体已注册
   */
  registerEntity(entityName: string, tableName?: string): void {
    if (this.entities.has(entityName)) {
      throw new DuplicateEntityError(entityName)
    }
    const actualTableName = tableName ? tableName : entityName
    const metadata = new EntityMetadata(entityName, actualTableName)
    this.entities.set(entityName, metadata)
  }

  /**
   * 注册列元数据
   * @param entityName 实体类名
   * @param column 列元数据
   * @throws EntityNotRegisteredError 如果实体未注册
   */
  registerColumn(entityName: string, column: ColumnMetadata): void {
    const metadata = this.getEntityOrThrow(entityName)
    metadata.addColumn(column)
  }

  /**
   * 获取实体元数据
   * @param entityName 实体类名
   * @returns 实体元数据，如果不存在返回 null
   */
  getEntityMetadata(entityName: string): EntityMetadata | null {
    const metadata = this.entities.get(entityName)
    if (metadata) {
      return metadata
    }
    return null
  }

  /**
   * 获取所有已注册的实体元数据
   * @returns 实体元数据数组
   */
  getAllEntities(): Array<EntityMetadata> {
    const result: Array<EntityMetadata> = []
    this.entities.forEach((value: EntityMetadata) => {
      result.push(value)
    })
    return result
  }

  /**
   * 检查实体是否已注册
   * @param entityName 实体类名
   * @returns 是否已注册
   */
  hasEntity(entityName: string): boolean {
    return this.entities.has(entityName)
  }

  private getEntityOrThrow(entityName: string): EntityMetadata {
    const metadata = this.entities.get(entityName)
    if (!metadata) {
      throw new EntityNotRegisteredError(entityName)
    }
    return metadata
  }

  /**
   * 注册实例与实体名的映射关系
   * 用于通过实例获取元数据
   * @param instanceId 实例标识符
   * @param entityName 实体类名
   */
  registerInstanceMapping(instanceId: string, entityName: string): void {
    this.getEntityOrThrow(entityName)
    this.instanceEntityMap.set(instanceId, entityName)
  }

  /**
   * 通过实例标识符获取元数据
   * @param instanceId 实例标识符
   * @returns 实体元数据，如果不存在返回 null
   */
  getMetadataByInstanceId(instanceId: string): EntityMetadata | null {
    const entityName = this.instanceEntityMap.get(instanceId)
    if (entityName) {
      return this.getEntityMetadata(entityName)
    }
    return null
  }

  /**
   * 获取已注册实体数量
   * @returns 实体数量
   */
  getEntityCount(): number {
    return this.entities.size
  }

  /**
   * 注册关联关系
   * @param sourceEntity 源实体名称
   * @param relation 关联关系元数据
   */
  registerRelation(sourceEntity: string, relation: RelationMetadata): void {
    this.getEntityOrThrow(sourceEntity)
    if (relation.targetEntity) {
      this.getEntityOrThrow(relation.targetEntity)
    }
    let entityRelations = this.relations.get(sourceEntity)
    if (!entityRelations) {
      entityRelations = []
      this.relations.set(sourceEntity, entityRelations)
    }
    entityRelations.push(relation)
  }

  /**
   * 获取实体的所有关联关系
   * @param entityName 实体名称
   * @returns 关联关系数组，如果没有则返回空数组
   */
  getRelations(entityName: string): Array<RelationMetadata> {
    const entityRelations = this.relations.get(entityName)
    if (entityRelations) {
      return entityRelations
    }
    return []
  }

  /**
   * 根据属性名获取特定的关联关系
   * @param entityName 实体名称
   * @param propertyName 属性名
   * @returns 关联关系元数据，如果不存在返回 null
   */
  getRelation(entityName: string, propertyName: string): RelationMetadata | null {
    const entityRelations = this.relations.get(entityName)
    if (!entityRelations) {
      return null
    }
    for (let i = 0; i < entityRelations.length; i++) {
      const relation = entityRelations[i]
      if (relation.propertyName === propertyName) {
        return relation
      }
    }
    return null
  }

  /**
   * 获取关联关系，如果不存在则抛出错误
   * @param entityName 实体名称
   * @param propertyName 属性名
   * @returns 关联关系元数据
   * @throws RelationNotFoundError 如果关联关系不存在
   */
  getRelationOrThrow(entityName: string, propertyName: string): RelationMetadata {
    const relation = this.getRelation(entityName, propertyName)
    if (!relation) {
      throw new RelationNotFoundError(entityName, propertyName)
    }
    return relation
  }

  /**
   * 检查实体是否有指定的关联关系
   * @param entityName 实体名称
   * @param propertyName 属性名
   * @returns 是否存在该关联关系
   */
  hasRelation(entityName: string, propertyName: string): boolean {
    return this.getRelation(entityName, propertyName) !== null
  }

  /**
   * 获取已注册的关联关系总数
   * @returns 关联关系总数
   */
  getRelationCount(): number {
    let count = 0
    this.relations.forEach((relations: Array<RelationMetadata>) => {
      count += relations.length
    })
    return count
  }

  /**
   * 注册多对多关联关系
   * @param sourceEntity 源实体名称
   * @param targetEntity 目标实体名称
   * @param propertyName 在源实体中的属性名
   * @param joinTable 中间表名
   * @param joinSourceKey 源实体在中间表的外键列名
   * @param joinTargetKey 目标实体在中间表的外键列名
   */
  registerManyToMany(
    sourceEntity: string,
    targetEntity: string,
    propertyName: string,
    joinTable: string,
    joinSourceKey: string,
    joinTargetKey: string
  ): void {
    this.getEntityOrThrow(sourceEntity)
    this.getEntityOrThrow(targetEntity)
    const metadata = new ManyToManyMetadata(
      sourceEntity,
      targetEntity,
      propertyName,
      joinTable,
      joinSourceKey,
      joinTargetKey
    )
    this.registerRelation(sourceEntity, metadata)
  }

  registerMorphTo(
    sourceEntity: string,
    propertyName: string,
    idColumn: string,
    typeColumn: string,
    typeMap: Record<string, string> = {}
  ): void {
    this.getEntityOrThrow(sourceEntity)
    const metadata = new MorphToMetadata(
      sourceEntity,
      propertyName,
      idColumn,
      typeColumn,
      typeMap
    )
    this.registerRelation(sourceEntity, metadata)
  }

  /**
   * 获取多对多关联关系
   * @param entityName 实体名称
   * @param propertyName 属性名
   * @returns 多对多关联关系元数据，如果不存在或不是多对多关系返回 null
   */
  getManyToManyRelation(entityName: string, propertyName: string): ManyToManyMetadata | null {
    const relation = this.getRelation(entityName, propertyName)
    if (relation && relation.type === RelationType.MANY_TO_MANY) {
      return relation as ManyToManyMetadata
    }
    return null
  }

  getMorphToRelation(entityName: string, propertyName: string): MorphToMetadata | null {
    const relation = this.getRelation(entityName, propertyName)
    if (relation && relation.type === RelationType.MORPH_TO) {
      return relation as MorphToMetadata
    }
    return null
  }

  /**
   * 清除所有注册的元数据（主要用于测试）
   */
  clear(): void {
    this.entities.clear()
    this.instanceEntityMap.clear()
    this.relations.clear()
  }

  /**
   * 重置单例实例（主要用于测试）
   */
  static resetInstance(): void {
    MetadataStorage.instance = new MetadataStorage()
  }
}
