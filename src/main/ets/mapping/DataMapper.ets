/**
 * 数据映射器
 * 处理实体对象与数据库记录之间的双向转换
 */

import { EntityMetadata } from '../core/EntityMetadata'
import { ColumnMetadata } from '../core/ColumnMetadata'
import { MetadataStorage } from '../core/MetadataStorage'
import { ColumnType } from '../types/ColumnType'
import { ValueType, DbValueType } from '../types/ValueTypes'
import { TypeConverter } from './TypeConverter'
import { EntityMappingError, NullValueError } from '../errors/MappingError'
import { EntityDataInput } from './EntityDataInput'

/**
 * ValuesBucket 类型定义
 * 用于数据库插入/更新操作的键值对
 */
export class ValuesBucket {
  private data: Map<string, DbValueType> = new Map()

  /**
   * 设置值
   * @param key 键名
   * @param value 值
   */
  set(key: string, value: DbValueType): void {
    this.data.set(key, value)
  }

  /**
   * 获取值
   * @param key 键名
   * @returns 值
   */
  get(key: string): DbValueType {
    const value = this.data.get(key)
    if (value === undefined) {
      return null
    }
    return value
  }

  /**
   * 检查是否包含键
   * @param key 键名
   * @returns 是否包含
   */
  has(key: string): boolean {
    return this.data.has(key)
  }

  /**
   * 获取所有键
   * @returns 键数组
   */
  keys(): Array<string> {
    const result: Array<string> = []
    this.data.forEach((_, key) => {
      result.push(key)
    })
    return result
  }

  /**
   * 获取数据 Map
   * @returns 数据 Map
   */
  getData(): Map<string, DbValueType> {
    return this.data
  }
}


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


/**
 * 结果集行数据类
 * 模拟数据库查询结果的单行数据
 */
export class ResultSetRow {
  private data: Map<string, DbValueType> = new Map()

  /**
   * 设置列值
   * @param columnName 列名
   * @param value 值
   */
  set(columnName: string, value: DbValueType): void {
    this.data.set(columnName, value)
  }

  /**
   * 获取列值
   * @param columnName 列名
   * @returns 值
   */
  get(columnName: string): DbValueType {
    const value = this.data.get(columnName)
    if (value === undefined) {
      return null
    }
    return value
  }

  /**
   * 检查是否包含列
   * @param columnName 列名
   * @returns 是否包含
   */
  has(columnName: string): boolean {
    return this.data.has(columnName)
  }

  /**
   * 获取所有列名
   * @returns 列名数组
   */
  getColumnNames(): Array<string> {
    const result: Array<string> = []
    this.data.forEach((_, key) => {
      result.push(key)
    })
    return result
  }
}

/**
 * 数据映射器类
 * 处理实体数据与数据库记录之间的双向转换
 */
export class DataMapper {
  /** 实体元数据 */
  private entityMetadata: EntityMetadata

  /**
   * 构造函数
   * @param entityName 实体名称
   */
  constructor(entityName: string) {
    const metadata = MetadataStorage.getInstance().getEntityMetadata(entityName)
    if (metadata === null) {
      throw new EntityMappingError(entityName, '实体未注册')
    }
    this.entityMetadata = metadata
  }

  /**
   * 获取实体元数据
   * @returns 实体元数据
   */
  getMetadata(): EntityMetadata {
    return this.entityMetadata
  }


  /**
   * 实体数据转换为 ValuesBucket（用于插入/更新）
   * @param entityData 实体数据
   * @param includeAutoIncrement 是否包含自增主键
   * @returns ValuesBucket 对象
   */
  toValuesBucket(entityData: EntityData, includeAutoIncrement: boolean = false): ValuesBucket {
    const bucket = new ValuesBucket()

    for (let i = 0; i < this.entityMetadata.columns.length; i++) {
      const column = this.entityMetadata.columns[i]

      // 跳过自增主键（除非明确要求包含）
      if (column.isAutoIncrement && !includeAutoIncrement) {
        continue
      }

      // 获取属性值 - 优先从 properties 数组获取，如果不存在则从 propertyMap 获取
      const prop = entityData.getProperty(column.propertyName)
      let propValue: ValueType = null
      let propType: string = 'string'

      if (prop !== null) {
        // 从 properties 数组获取
        propValue = prop.value
        propType = prop.propertyType
      } else {
        // 尝试从 propertyMap 获取（支持 setPropertyValue 设置的值）
        const mapValue = entityData.getPropertyValue(column.propertyName)
        if (mapValue !== null) {
          propValue = mapValue
          propType = this.inferPropertyType(column)
        } else {
          // 属性不存在，检查是否允许为空
          if (!column.isNullable && column.defaultValue === null) {
            throw new NullValueError(this.entityMetadata.entityName, column.columnName)
          }
          // 使用默认值或 null
          if (column.defaultValue !== null) {
            bucket.set(column.columnName, column.defaultValue)
          } else {
            bucket.set(column.columnName, null)
          }
          continue
        }
      }

      // 转换值
      const dbValue = TypeConverter.toDbValue(propValue, column.columnType, propType)

      // 检查非空约束
      if (dbValue === null && !column.isNullable) {
        throw new NullValueError(this.entityMetadata.entityName, column.columnName)
      }

      bucket.set(column.columnName, dbValue)
    }

    return bucket
  }

  /**
   * 从结果集行转换为实体数据
   * @param row 结果集行
   * @returns 实体数据
   */
  fromResultSetRow(row: ResultSetRow): EntityData {
    const entityData = new EntityData(this.entityMetadata.entityName)

    for (let i = 0; i < this.entityMetadata.columns.length; i++) {
      const column = this.entityMetadata.columns[i]

      // 获取数据库值
      const dbValue = row.get(column.columnName)

      // 确定属性类型
      const propertyType = this.inferPropertyType(column)

      // 转换值
      let value: ValueType = null
      if (dbValue !== null) {
        value = TypeConverter.fromDbValue(dbValue, propertyType, column.columnName)
      } else if (!column.isNullable && column.defaultValue !== null) {
        // 使用默认值
        value = column.defaultValue
      }

      entityData.addProperty(column.propertyName, value, propertyType)
    }

    return entityData
  }


  /**
   * 从结果集转换为实体数据数组
   * @param rows 结果集行数组
   * @returns 实体数据数组
   */
  fromResultSet(rows: Array<ResultSetRow>): Array<EntityData> {
    const result: Array<EntityData> = []
    for (let i = 0; i < rows.length; i++) {
      result.push(this.fromResultSetRow(rows[i]))
    }
    return result
  }

  /**
   * 获取实体数据的主键值
   * @param entityData 实体数据
   * @returns 主键值，如果没有主键或主键值为空返回 null
   */
  getPrimaryKeyValue(entityData: EntityData): ValueType {
    const pkColumn = this.entityMetadata.getPrimaryKeyColumn()
    if (pkColumn === null) {
      return null
    }

    // 优先从 properties 数组获取
    const prop = entityData.getProperty(pkColumn.propertyName)
    if (prop !== null) {
      return prop.value
    }

    // 尝试从 propertyMap 获取（支持 setPropertyValue 设置的值）
    return entityData.getPropertyValue(pkColumn.propertyName)
  }

  /**
   * 设置实体数据的主键值
   * @param entityData 实体数据
   * @param value 主键值
   */
  setPrimaryKeyValue(entityData: EntityData, value: ValueType): void {
    const pkColumn = this.entityMetadata.getPrimaryKeyColumn()
    if (pkColumn === null) {
      throw new EntityMappingError(this.entityMetadata.entityName, '实体没有定义主键')
    }

    // 查找并更新主键属性
    const prop = entityData.getProperty(pkColumn.propertyName)
    if (prop !== null) {
      prop.value = value
      // 同步更新 propertyMap 以支持 getPropertyValue 获取
      entityData.setPropertyValue(pkColumn.propertyName, value)
    } else {
      // 添加主键属性（addProperty 会同时更新 properties 和 propertyMap）
      const propertyType = this.inferPropertyType(pkColumn)
      entityData.addProperty(pkColumn.propertyName, value, propertyType)
    }
  }

  /**
   * 根据列元数据推断属性类型
   * @param column 列元数据
   * @returns 属性类型标识
   */
  private inferPropertyType(column: ColumnMetadata): string {
    switch (column.columnType) {
      case ColumnType.TEXT:
        return 'string'
      case ColumnType.INTEGER:
        // INTEGER 可能是 number、boolean 或 Date
        // 这里默认返回 number，具体类型需要在实体定义时指定
        return 'number'
      case ColumnType.REAL:
        return 'number'
      case ColumnType.BLOB:
        return 'object'
      default:
        return 'string'
    }
  }

  /**
   * 检查实体数据是否为新记录（主键为空或为 0）
   * @param entityData 实体数据
   * @returns 是否为新记录
   */
  isNewRecord(entityData: EntityData): boolean {
    const pkValue = this.getPrimaryKeyValue(entityData)
    if (pkValue === null) {
      return true
    }
    if (typeof pkValue === 'number' && pkValue === 0) {
      return true
    }
    return false
  }
}
