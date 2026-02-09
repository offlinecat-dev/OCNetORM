/**
 * 泛型实体数据类
 * 提供类型安全的属性访问
 * 使用 @ObservedV2 装饰器支持 HarmonyOS 5.0+ 状态管理 V2 响应式
 *
 * 注意：由于 ArkTS 不支持索引访问类型（T[K]），
 * 本类使用字符串键和 ValueType 值，类型安全由调用方保证
 */

import { ValueType } from '../types/ValueTypes'
import { EntityData, RelatedDataValue } from './EntityData'

/**
 * 泛型实体数据类
 * 提供类型安全的属性访问，支持 V2 响应式
 * 泛型参数 T 用于文档目的，实际类型检查由调用方保证
 */
@ObservedV2
export class TypedEntityData<T> {
  /** 实体名称 */
  entityName: string = ''

  /** 属性值 Map，使用 @Trace 支持响应式 */
  @Trace private data: Map<string, ValueType> = new Map()

  /** 关联数据存储，使用 @Trace 支持响应式 */
  @Trace private relatedData: Map<string, RelatedDataValue> = new Map()

  /**
   * 构造函数
   * @param entityName 实体名称
   */
  constructor(entityName: string) {
    this.entityName = entityName
  }

  /**
   * 获取字符串类型的属性值
   * @param key 属性名
   * @returns 属性值，如果不存在返回 null
   */
  getString(key: string): string | null {
    const value = this.data.get(key)
    if (value === undefined || value === null) {
      return null
    }
    if (typeof value === 'string') {
      return value
    }
    return String(value)
  }

  /**
   * 获取数字类型的属性值
   * @param key 属性名
   * @returns 属性值，如果不存在返回 null
   */
  getNumber(key: string): number | null {
    const value = this.data.get(key)
    if (value === undefined || value === null) {
      return null
    }
    if (typeof value === 'number') {
      return value
    }
    return null
  }

  /**
   * 获取布尔类型的属性值
   * @param key 属性名
   * @returns 属性值，如果不存在返回 null
   */
  getBoolean(key: string): boolean | null {
    const value = this.data.get(key)
    if (value === undefined || value === null) {
      return null
    }
    if (typeof value === 'boolean') {
      return value
    }
    return null
  }

  /**
   * 获取属性值（通用方法）
   * @param key 属性名
   * @returns 属性值，如果不存在返回 null
   */
  getValue(key: string): ValueType {
    const value = this.data.get(key)
    if (value === undefined) {
      return null
    }
    return value
  }

  /**
   * 设置字符串类型的属性值（自动触发 UI 刷新）
   * @param key 属性名
   * @param value 属性值
   */
  setString(key: string, value: string): void {
    this.data.set(key, value)
  }

  /**
   * 设置数字类型的属性值（自动触发 UI 刷新）
   * @param key 属性名
   * @param value 属性值
   */
  setNumber(key: string, value: number): void {
    this.data.set(key, value)
  }

  /**
   * 设置布尔类型的属性值（自动触发 UI 刷新）
   * @param key 属性名
   * @param value 属性值
   */
  setBoolean(key: string, value: boolean): void {
    this.data.set(key, value)
  }

  /**
   * 设置属性值（通用方法，自动触发 UI 刷新）
   * @param key 属性名
   * @param value 属性值
   */
  setValue(key: string, value: ValueType): void {
    this.data.set(key, value)
  }

  /**
   * 检查属性是否存在
   * @param key 属性名
   * @returns 是否存在
   */
  hasValue(key: string): boolean {
    return this.data.has(key)
  }

  /**
   * 获取所有属性名
   * @returns 属性名数组
   */
  getPropertyNames(): Array<string> {
    const names: Array<string> = []
    this.data.forEach((_, key) => {
      names.push(key)
    })
    return names
  }

  /**
   * 设置关联数据（数组类型，用于 ONE_TO_MANY 或 MANY_TO_MANY）
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
   * 获取关联数据（数组类型）
   * @param propertyName 关联属性名
   * @returns 关联实体数组，如果不存在或类型不匹配返回空数组
   */
  getRelatedArray(propertyName: string): Array<EntityData> {
    const value = this.relatedData.get(propertyName)
    if (value !== undefined && value.isArray) {
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
    if (value !== undefined && !value.isArray) {
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
   * 从普通 EntityData 转换为 TypedEntityData
   * @param entityData 普通 EntityData 实例
   * @returns TypedEntityData 实例
   */
  static fromEntityData<T>(entityData: EntityData): TypedEntityData<T> {
    const typed = new TypedEntityData<T>(entityData.entityName)

    // 复制所有属性值
    const props = entityData.properties
    for (let i = 0; i < props.length; i++) {
      const prop = props[i]
      typed.data.set(prop.propertyName, prop.value)
    }

    // 复制所有关联数据
    const relatedNames = entityData.getRelatedPropertyNames()
    for (let i = 0; i < relatedNames.length; i++) {
      const name = relatedNames[i]
      if (entityData.isRelatedArray(name)) {
        typed.setRelatedArray(name, entityData.getRelatedArray(name))
      } else {
        typed.setRelatedSingle(name, entityData.getRelatedSingle(name))
      }
    }

    return typed
  }

  /**
   * 转换为普通 EntityData
   * @returns EntityData 实例
   */
  toEntityData(): EntityData {
    const entityData = new EntityData(this.entityName)

    // 复制所有属性值
    this.data.forEach((value, key) => {
      // 根据值类型推断属性类型
      let propertyType = 'string'
      if (typeof value === 'number') {
        propertyType = 'number'
      } else if (typeof value === 'boolean') {
        propertyType = 'boolean'
      }
      entityData.addProperty(key, value, propertyType)
    })

    // 复制所有关联数据
    this.relatedData.forEach((value, key) => {
      entityData.setRelated(key, value)
    })

    return entityData
  }

  /**
   * 获取属性数量
   * @returns 属性数量
   */
  getPropertyCount(): number {
    return this.data.size
  }

  /**
   * 清空所有属性
   */
  clear(): void {
    this.data.clear()
    this.relatedData.clear()
  }
}
