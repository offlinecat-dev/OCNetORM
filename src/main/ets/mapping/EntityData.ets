/**
 * EntityData 相关数据结构
 * 包含 EntityPropertyValue、RelatedDataValue、EntityData
 */

import { MetadataStorage } from '../core/MetadataStorage'
import { ColumnType } from '../types/ColumnType'
import { ValueType } from '../types/ValueTypes'
import { EntityMappingError } from '../errors/MappingError'
import { EntityDataInput } from './EntityDataInput'


/**
 * 实体属性值类
 * 用于存储实体的属性名和值
 */
export class EntityPropertyValue {
  /** 属性名 */
  propertyName: string = ''
  /** 属性值 */
  value: ValueType = null
  /** 属性类型标识 */
  propertyType: string = 'string'

  constructor(propertyName: string, value: ValueType, propertyType: string) {
    this.propertyName = propertyName
    this.value = value
    this.propertyType = propertyType
  }
}

/**
 * 关联数据类型
 * 用于存储关联实体数据
 */
export class RelatedDataValue {
  /** 是否为数组类型（ONE_TO_MANY） */
  isArray: boolean = false
  /** 单个关联实体（MANY_TO_ONE） */
  singleEntity: EntityData | null = null
  /** 关联实体数组（ONE_TO_MANY） */
  entityArray: Array<EntityData> = []

  /**
   * 创建数组类型的关联数据
   * @param entities 实体数组
   * @returns RelatedDataValue 实例
   */
  static fromArray(entities: Array<EntityData>): RelatedDataValue {
    const value = new RelatedDataValue()
    value.isArray = true
    value.entityArray = entities
    return value
  }

  /**
   * 创建单个实体类型的关联数据
   * @param entity 单个实体或 null
   * @returns RelatedDataValue 实例
   */
  static fromSingle(entity: EntityData | null): RelatedDataValue {
    const value = new RelatedDataValue()
    value.isArray = false
    value.singleEntity = entity
    return value
  }
}

/**
 * 实体数据类
 * 用于存储实体的所有属性值
 * 使用 @ObservedV2 装饰器支持 HarmonyOS 5.0+ 状态管理 V2 响应式
 */
@ObservedV2
export class EntityData {
  /** 实体名称 */
  entityName: string = ''
  /** 属性值数组（保留用于向后兼容） */
  properties: Array<EntityPropertyValue> = []
  /** 属性值 Map，使用 @Trace 支持响应式 */
  @Trace private propertyMap: Map<string, ValueType> = new Map()
  /** 临时数据存储（非数据库字段），使用 @Trace 支持响应式 */
  @Trace private transientData: Map<string, ValueType> = new Map()
  /** 关联数据存储，使用 @Trace 支持响应式 */
  @Trace private relatedData: Map<string, RelatedDataValue> = new Map()
  /** 延迟加载关联数据处理器（非响应式） */
  private lazyRelationLoaders: Map<string, () => Promise<RelatedDataValue>> = new Map()

  constructor(entityName: string) {
    this.entityName = entityName
  }

  /**
   * 添加属性值
   * @param propertyName 属性名
   * @param value 属性值
   * @param propertyType 属性类型
   */
  addProperty(propertyName: string, value: ValueType, propertyType: string): void {
    const prop = new EntityPropertyValue(propertyName, value, propertyType)
    this.properties.push(prop)
    // 同步到 propertyMap 以支持响应式
    this.propertyMap.set(propertyName, value)
  }

  /**
   * 获取属性值
   * @param propertyName 属性名
   * @returns 属性值，如果不存在返回 null
   */
  getProperty(propertyName: string): EntityPropertyValue | null {
    for (let i = 0; i < this.properties.length; i++) {
      if (this.properties[i].propertyName === propertyName) {
        return this.properties[i]
      }
    }
    return null
  }

  /**
   * 设置属性值（自动触发 UI 刷新）
   * @param propertyName 属性名
   * @param value 属性值
   */
  setPropertyValue(propertyName: string, value: ValueType): void {
    // 更新 properties 数组（向后兼容）
    for (let i = 0; i < this.properties.length; i++) {
      if (this.properties[i].propertyName === propertyName) {
        this.properties[i].value = value
        break
      }
    }
    // 更新 propertyMap（触发响应式更新）
    this.propertyMap.set(propertyName, value)
  }

  /**
   * 获取属性值（响应式版本）
   * @param propertyName 属性名
   * @returns 属性值，如果不存在返回 null
   */
  getPropertyValue(propertyName: string): ValueType {
    const value = this.propertyMap.get(propertyName)
    if (value === undefined) {
      return null
    }
    return value
  }

  /**
   * 检查属性是否存在
   * @param propertyName 属性名
   * @returns 是否存在
   */
  hasProperty(propertyName: string): boolean {
    return this.propertyMap.has(propertyName)
  }

  /**
   * 获取所有属性名
   * @returns 属性名数组
   */
  getPropertyNames(): Array<string> {
    const names: Array<string> = []
    this.propertyMap.forEach((_, key) => {
      names.push(key)
    })
    return names
  }

  /**
   * 设置临时数据（非数据库字段）
   * @param key 键名
   * @param value 值
   */
  setTransient(key: string, value: ValueType): void {
    this.transientData.set(key, value)
  }

  /**
   * 获取临时数据
   * @param key 键名
   * @returns 值，如果不存在返回 null
   */
  getTransient(key: string): ValueType {
    const value = this.transientData.get(key)
    if (value === undefined) {
      return null
    }
    return value
  }

  /**
   * 检查是否存在临时数据
   * @param key 键名
   * @returns 是否存在
   */
  hasTransient(key: string): boolean {
    return this.transientData.has(key)
  }

  /**
   * 删除临时数据
   * @param key 键名
   */
  removeTransient(key: string): void {
    this.transientData.delete(key)
  }

  /**
   * 获取所有临时数据的键
   * @returns 键数组
   */
  getTransientKeys(): Array<string> {
    const keys: Array<string> = []
    this.transientData.forEach((_, key) => {
      keys.push(key)
    })
    return keys
  }

  /**
   * 设置关联数据（数组类型，用于 ONE_TO_MANY）
   * 自动触发 UI 刷新
   * @param propertyName 关联属性名
   * @param data 关联实体数组
   */
  setRelatedArray(propertyName: string, data: Array<EntityData>): void {
    this.relatedData.set(propertyName, RelatedDataValue.fromArray(data))
  }

  /**
   * 设置关联数据（单个实体类型，用于 MANY_TO_ONE 或 ONE_TO_ONE）
   * 自动触发 UI 刷新
   * @param propertyName 关联属性名
   * @param data 单个关联实体或 null
   */
  setRelatedSingle(propertyName: string, data: EntityData | null): void {
    this.relatedData.set(propertyName, RelatedDataValue.fromSingle(data))
  }

  /**
   * 设置关联数据（通用方法，自动触发 UI 刷新）
   * @param propertyName 关联属性名
   * @param data 关联数据值
   */
  setRelated(propertyName: string, data: RelatedDataValue): void {
    this.relatedData.set(propertyName, data)
  }

  /**
   * 获取关联数据原始值
   * @param propertyName 关联属性名
   * @returns 关联数据值或 null
   */
  getRelatedValue(propertyName: string): RelatedDataValue | null {
    const value = this.relatedData.get(propertyName)
    return value ? value : null
  }

  /**
   * 获取关联数据（数组类型）
   * @param propertyName 关联属性名
   * @returns 关联实体数组，如果不存在或类型不匹配返回空数组
   */
  getRelatedArray(propertyName: string): Array<EntityData> {
    const value = this.relatedData.get(propertyName)
    if (value && value.isArray) {
      return value.entityArray
    }
    return []
  }

  /**
   * 获取关联数据（单个实体类型）
   * @param propertyName 关联属性名
   * @returns 单个关联实体，如果不存在或类型不匹配返回 null
   */
  getRelatedSingle(propertyName: string): EntityData | null {
    const value = this.relatedData.get(propertyName)
    if (value && !value.isArray) {
      return value.singleEntity
    }
    return null
  }

  /**
   * 设置延迟加载关联数据
   * @param propertyName 关联属性名
   * @param loader 延迟加载器
   */
  setLazyRelation(propertyName: string, loader: () => Promise<RelatedDataValue>): void {
    this.lazyRelationLoaders.set(propertyName, loader)
  }

  /**
   * 检查是否存在延迟加载关联
   * @param propertyName 关联属性名
   */
  hasLazyRelation(propertyName: string): boolean {
    return this.lazyRelationLoaders.has(propertyName)
  }

  /**
   * 触发延迟加载关联数据
   * @param propertyName 关联属性名
   */
  async loadRelated(propertyName: string): Promise<RelatedDataValue | null> {
    const existing = this.relatedData.get(propertyName)
    if (existing) {
      return existing
    }
    const loader = this.lazyRelationLoaders.get(propertyName)
    if (!loader) {
      return null
    }
    const value = await loader()
    this.relatedData.set(propertyName, value)
    this.lazyRelationLoaders.delete(propertyName)
    return value
  }

  /**
   * 延迟加载关联数组
   * @param propertyName 关联属性名
   */
  async loadRelatedArray(propertyName: string): Promise<Array<EntityData>> {
    const value = await this.loadRelated(propertyName)
    if (value && value.isArray) {
      return value.entityArray
    }
    return []
  }

  /**
   * 延迟加载单个关联实体
   * @param propertyName 关联属性名
   */
  async loadRelatedSingle(propertyName: string): Promise<EntityData | null> {
    const value = await this.loadRelated(propertyName)
    if (value && !value.isArray) {
      return value.singleEntity
    }
    return null
  }

  /**
   * 检查是否存在关联数据
   * @param propertyName 关联属性名
   * @returns 是否存在
   */
  hasRelated(propertyName: string): boolean {
    return this.relatedData.has(propertyName)
  }

  /**
   * 删除关联数据
   * @param propertyName 关联属性名
   */
  removeRelated(propertyName: string): void {
    this.relatedData.delete(propertyName)
  }

  /**
   * 获取所有关联数据的属性名
   * @returns 属性名数组
   */
  getRelatedPropertyNames(): Array<string> {
    const names: Array<string> = []
    this.relatedData.forEach((_, key) => {
      names.push(key)
    })
    return names
  }

  /**
   * 检查关联数据是否为数组类型
   * @param propertyName 关联属性名
   * @returns 是否为数组类型，如果不存在返回 false
   */
  isRelatedArray(propertyName: string): boolean {
    const value = this.relatedData.get(propertyName)
    if (value) {
      return value.isArray
    }
    return false
  }

  /**
   * 从 EntityDataInput 快速构建实体数据
   * 根据 MetadataStorage 中的列定义自动匹配属性
   * @param entityName 实体名称
   * @param input 输入数据
   * @returns EntityData 实例
   * @throws EntityMappingError 如果实体未注册
   */
  static from(entityName: string, input: EntityDataInput): EntityData {
    const metadata = MetadataStorage.getInstance().getEntityMetadata(entityName)
    if (metadata === null) {
      throw new EntityMappingError(entityName, '实体未注册')
    }

    const entityData = new EntityData(entityName)
    const inputKeys = input.keys()

    // 遍历元数据中的所有列
    for (let i = 0; i < metadata.columns.length; i++) {
      const column = metadata.columns[i]
      const propertyName = column.propertyName

      // 检查输入数据中是否包含该属性
      if (input.has(propertyName)) {
        const value = input.get(propertyName)
        // 根据列类型推断属性类型
        const propertyType = EntityData.inferPropertyTypeFromColumn(column.columnType)
        entityData.addProperty(propertyName, value, propertyType)
      }
    }

    // 注意：输入数据中不在元数据中的属性会被忽略（符合 Requirements 4.5）

    return entityData
  }

  /**
   * 根据列类型推断属性类型
   * @param columnType 列类型
   * @returns 属性类型标识
   */
  private static inferPropertyTypeFromColumn(columnType: ColumnType): string {
    switch (columnType) {
      case ColumnType.TEXT:
        return 'string'
      case ColumnType.INTEGER:
        return 'number'
      case ColumnType.REAL:
        return 'number'
      case ColumnType.BLOB:
        return 'object'
      default:
        return 'string'
    }
  }
}
