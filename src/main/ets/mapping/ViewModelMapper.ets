/**
 * ViewModel 映射器
 * 用于 EntityData 与 ViewModel 的双向转换
 *
 * 由于 ArkTS 不支持 Reflect API，本类使用回调函数和显式属性映射方式实现转换
 * 调用方需要提供属性映射逻辑以确保类型安全
 *
 * Requirements: 7.1, 7.2, 7.3, 7.4, 7.5
 */

import { EntityData, EntityPropertyValue } from './EntityData'
import { MetadataStorage } from '../core/MetadataStorage'
import { EntityMappingError } from '../errors/MappingError'
import { ValueType } from '../types/ValueTypes'

/**
 * 属性映射器类型
 * 用于从 EntityData 提取值并设置到 ViewModel
 */
export type PropertyMapper<T> = (entityData: EntityData, viewModel: T) => void

/**
 * 反向属性映射器类型
 * 用于从 ViewModel 提取值
 */
export type ReversePropertyMapper<T> = (viewModel: T, propertyName: string) => ValueType

/**
 * ViewModel 工厂类型
 * 用于创建 ViewModel 实例
 */
export type ViewModelFactory<T> = () => T

/**
 * ViewModel 映射配置
 * 用于配置 EntityData 与 ViewModel 之间的映射关系
 */
export class ViewModelMappingConfig<T> {
  /** 实体名称 */
  entityName: string = ''
  /** ViewModel 工厂函数 */
  factory: ViewModelFactory<T> | null = null
  /** 属性映射器列表 */
  private propertyMappers: Array<PropertyMapper<T>> = []
  /** 反向属性映射器 */
  private reverseMapper: ReversePropertyMapper<T> | null = null
  /** 属性名列表（用于反向映射） */
  private propertyNames: Array<string> = []

  /**
   * 构造函数
   * @param entityName 实体名称
   * @param factory ViewModel 工厂函数
   */
  constructor(entityName: string, factory: ViewModelFactory<T>) {
    this.entityName = entityName
    this.factory = factory
  }

  /**
   * 添加属性映射器
   * @param mapper 属性映射器
   * @returns 当前配置实例（支持链式调用）
   */
  addMapper(mapper: PropertyMapper<T>): ViewModelMappingConfig<T> {
    this.propertyMappers.push(mapper)
    return this
  }

  /**
   * 设置反向属性映射器（用于 ViewModel 转 EntityData）
   * @param mapper 反向属性映射器
   * @param propertyNames 需要映射的属性名列表
   * @returns 当前配置实例（支持链式调用）
   */
  setReverseMapper(mapper: ReversePropertyMapper<T>, propertyNames: Array<string>): ViewModelMappingConfig<T> {
    this.reverseMapper = mapper
    this.propertyNames = propertyNames
    return this
  }

  /**
   * 获取属性映射器列表
   * @returns 属性映射器数组
   */
  getMappers(): Array<PropertyMapper<T>> {
    return this.propertyMappers
  }

  /**
   * 获取反向属性映射器
   * @returns 反向属性映射器或 null
   */
  getReverseMapper(): ReversePropertyMapper<T> | null {
    return this.reverseMapper
  }

  /**
   * 获取属性名列表
   * @returns 属性名数组
   */
  getPropertyNames(): Array<string> {
    return this.propertyNames
  }
}

/**
 * ViewModel 映射器
 * 提供 EntityData 与 ViewModel 之间的双向转换功能
 */
export class ViewModelMapper {
  /**
   * 将 EntityData 转换为 ViewModel（使用配置）
   * @param entityData EntityData 实例
   * @param config 映射配置
   * @returns ViewModel 实例
   */
  static toViewModelWithConfig<T>(entityData: EntityData, config: ViewModelMappingConfig<T>): T {
    if (config.factory === null) {
      throw new EntityMappingError(entityData.entityName, 'ViewModel 工厂函数未配置')
    }
    const viewModel = config.factory()
    const mappers = config.getMappers()
    for (let i = 0; i < mappers.length; i++) {
      mappers[i](entityData, viewModel)
    }
    return viewModel
  }

  /**
   * 将 EntityData 转换为 ViewModel（使用回调）
   * 简化版本，直接使用回调函数进行映射
   * @param entityData EntityData 实例
   * @param factory ViewModel 工厂函数
   * @param mapper 属性映射回调
   * @returns ViewModel 实例
   */
  static toViewModel<T>(entityData: EntityData, factory: ViewModelFactory<T>, mapper: PropertyMapper<T>): T {
    const viewModel = factory()
    mapper(entityData, viewModel)
    return viewModel
  }

  /**
   * 将 ViewModel 转换为 EntityData（使用配置）
   * @param viewModel ViewModel 实例
   * @param config 映射配置
   * @returns EntityData 实例
   */
  static toEntityDataWithConfig<T>(viewModel: T, config: ViewModelMappingConfig<T>): EntityData {
    const entityData = new EntityData(config.entityName)
    const reverseMapper = config.getReverseMapper()
    const propertyNames = config.getPropertyNames()

    if (reverseMapper === null) {
      throw new EntityMappingError(config.entityName, '反向属性映射器未配置')
    }

    // 获取元数据以确定属性类型
    const metadata = MetadataStorage.getInstance().getEntityMetadata(config.entityName)

    for (let i = 0; i < propertyNames.length; i++) {
      const propertyName = propertyNames[i]
      const value = reverseMapper(viewModel, propertyName)

      // 推断属性类型
      let propertyType = 'string'
      if (typeof value === 'number') {
        propertyType = 'number'
      } else if (typeof value === 'boolean') {
        propertyType = 'boolean'
      }

      // 如果有元数据，使用元数据中的类型定义
      if (metadata !== null) {
        for (let j = 0; j < metadata.columns.length; j++) {
          if (metadata.columns[j].propertyName === propertyName) {
            // 使用列定义中的类型
            break
          }
        }
      }

      entityData.addProperty(propertyName, value, propertyType)
    }

    return entityData
  }

  /**
   * 将 ViewModel 转换为 EntityData（使用回调）
   * 简化版本，直接使用回调函数进行映射
   * @param viewModel ViewModel 实例
   * @param entityName 实体名称
   * @param propertyNames 属性名列表
   * @param valueGetter 值获取回调
   * @returns EntityData 实例
   */
  static toEntityData<T>(
    viewModel: T,
    entityName: string,
    propertyNames: Array<string>,
    valueGetter: ReversePropertyMapper<T>
  ): EntityData {
    const entityData = new EntityData(entityName)

    for (let i = 0; i < propertyNames.length; i++) {
      const propertyName = propertyNames[i]
      const value = valueGetter(viewModel, propertyName)

      // 推断属性类型
      let propertyType = 'string'
      if (typeof value === 'number') {
        propertyType = 'number'
      } else if (typeof value === 'boolean') {
        propertyType = 'boolean'
      }

      entityData.addProperty(propertyName, value, propertyType)
    }

    return entityData
  }

  /**
   * 创建通用的属性映射器
   * 从 EntityData 的所有属性创建到 Map 的映射
   * @param entityData EntityData 实例
   * @returns 属性值 Map
   */
  static toPropertyMap(entityData: EntityData): Map<string, ValueType> {
    const result: Map<string, ValueType> = new Map()
    const props = entityData.properties
    for (let i = 0; i < props.length; i++) {
      const prop = props[i]
      result.set(prop.propertyName, prop.value)
    }
    return result
  }

  /**
   * 从属性值 Map 创建 EntityData
   * @param entityName 实体名称
   * @param propertyMap 属性值 Map
   * @returns EntityData 实例
   */
  static fromPropertyMap(entityName: string, propertyMap: Map<string, ValueType>): EntityData {
    const entityData = new EntityData(entityName)
    propertyMap.forEach((value, key) => {
      let propertyType = 'string'
      if (typeof value === 'number') {
        propertyType = 'number'
      } else if (typeof value === 'boolean') {
        propertyType = 'boolean'
      }
      entityData.addProperty(key, value, propertyType)
    })
    return entityData
  }

  /**
   * 批量转换 EntityData 数组为 ViewModel 数组
   * @param entityDataArray EntityData 数组
   * @param factory ViewModel 工厂函数
   * @param mapper 属性映射回调
   * @returns ViewModel 数组
   */
  static toViewModelArray<T>(
    entityDataArray: Array<EntityData>,
    factory: ViewModelFactory<T>,
    mapper: PropertyMapper<T>
  ): Array<T> {
    const result: Array<T> = []
    for (let i = 0; i < entityDataArray.length; i++) {
      result.push(ViewModelMapper.toViewModel(entityDataArray[i], factory, mapper))
    }
    return result
  }

  /**
   * 批量转换 ViewModel 数组为 EntityData 数组
   * @param viewModelArray ViewModel 数组
   * @param entityName 实体名称
   * @param propertyNames 属性名列表
   * @param valueGetter 值获取回调
   * @returns EntityData 数组
   */
  static toEntityDataArray<T>(
    viewModelArray: Array<T>,
    entityName: string,
    propertyNames: Array<string>,
    valueGetter: ReversePropertyMapper<T>
  ): Array<EntityData> {
    const result: Array<EntityData> = []
    for (let i = 0; i < viewModelArray.length; i++) {
      result.push(ViewModelMapper.toEntityData(viewModelArray[i], entityName, propertyNames, valueGetter))
    }
    return result
  }
}
