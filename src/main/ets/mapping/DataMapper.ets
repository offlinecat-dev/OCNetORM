/**
 * 数据映射器
 * 处理实体对象与数据库记录之间的双向转换
 */

import { EntityMetadata } from '../core/EntityMetadata'
import { ColumnMetadata } from '../core/ColumnMetadata'
import { MetadataStorage } from '../core/MetadataStorage'
import { ColumnType } from '../types/ColumnType'
import { ValueType } from '../types/ValueTypes'
import { TypeConverter } from './TypeConverter'
import { EntityMappingError, NullValueError } from '../errors/MappingError'
import { ValuesBucket } from './ValuesBucket'
import { EntityData } from './EntityData'
import { ResultSetRow } from './ResultSetRow'
import { ValidationMetadataStorage } from '../validation/ValidationMetadataStorage'

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

      let hasValue = false
      if (prop !== null) {
        // 从 properties 数组获取
        propValue = prop.value
        propType = prop.propertyType
        hasValue = true
      } else {
        // 尝试从 propertyMap 获取（支持 setPropertyValue 设置的值）
        if (entityData.hasProperty(column.propertyName)) {
          const mapValue = entityData.getPropertyValue(column.propertyName)
          propValue = mapValue
          if (mapValue !== null) {
            propType = this.inferValueType(mapValue)
          } else {
            propType = this.inferPropertyType(column)
          }
          hasValue = true
        }
      }

      if (!hasValue) {
        // 属性不存在，检查是否允许为空
        if (!column.isNullable && column.defaultValue === null) {
          throw new NullValueError(this.entityMetadata.entityName, column.columnName)
        }
        // 使用默认值或 null
        if (column.defaultValue !== null) {
          const defaultDbValue = TypeConverter.toDbValue(
            column.defaultValue,
            column.columnType,
            this.inferPropertyType(column),
            undefined,
            column.columnName
          )
          bucket.set(column.columnName, defaultDbValue)
        } else {
          bucket.set(column.columnName, null)
        }
        continue
      }

      // 转换值
      const dbValue = TypeConverter.toDbValue(
        propValue,
        column.columnType,
        propType,
        undefined,
        column.columnName
      )

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
        if (propertyType === 'Date' && typeof value === 'number') {
          value = TypeConverter.timestampToDate(value)
        }
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
        if (this.isDateColumn(column)) {
          return 'Date'
        }
        if (this.isBooleanColumn(column)) {
          return 'boolean'
        }
        return 'number'
      case ColumnType.REAL:
        return 'number'
      case ColumnType.BLOB:
        return 'object'
      default:
        return 'string'
    }
  }

  private inferValueType(value: ValueType): string {
    if (value instanceof Date) {
      return 'Date'
    }
    if (typeof value === 'boolean') {
      return 'boolean'
    }
    if (typeof value === 'number') {
      return 'number'
    }
    if (typeof value === 'string') {
      return 'string'
    }
    return 'object'
  }

  private isDateColumn(column: ColumnMetadata): boolean {
    const rules = ValidationMetadataStorage.getInstance()
      .getRules(this.entityMetadata.entityName)
      .get(column.propertyName)
    if (rules) {
      for (let i = 0; i < rules.length; i++) {
        if (rules[i].type === 'date') {
          return true
        }
      }
    }
    const propName = column.propertyName
    const columnName = column.columnName
    if (this.endsWithToken(propName, 'At') || this.endsWithToken(propName, 'Date') || this.endsWithToken(propName, 'Time')) {
      return true
    }
    const lower = columnName.toLowerCase()
    return lower.endsWith('_at') || lower.endsWith('_date') || lower.endsWith('_time')
  }

  private isBooleanColumn(column: ColumnMetadata): boolean {
    if (typeof column.defaultValue === 'boolean') {
      return true
    }
    const propName = column.propertyName
    return this.startsWithBooleanPrefix(propName) || this.startsWithBooleanPrefix(column.columnName)
  }

  private endsWithToken(value: string, token: string): boolean {
    if (value.length <= token.length) {
      return false
    }
    return value.endsWith(token)
  }

  private startsWithBooleanPrefix(value: string): boolean {
    const lower = value.toLowerCase()
    if (lower.startsWith('is_') || lower.startsWith('has_') || lower.startsWith('can_') || lower.startsWith('should_')) {
      return true
    }
    if (lower.startsWith('enable_') || lower.startsWith('enabled_')) {
      return true
    }
    return this.isCamelBooleanPrefix(value, 'is') ||
      this.isCamelBooleanPrefix(value, 'has') ||
      this.isCamelBooleanPrefix(value, 'can') ||
      this.isCamelBooleanPrefix(value, 'should') ||
      this.isCamelBooleanPrefix(value, 'enable') ||
      this.isCamelBooleanPrefix(value, 'enabled')
  }

  private isCamelBooleanPrefix(value: string, prefix: string): boolean {
    if (!value.startsWith(prefix) || value.length <= prefix.length) {
      return false
    }
    const nextChar = value[prefix.length]
    return nextChar >= 'A' && nextChar <= 'Z'
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
