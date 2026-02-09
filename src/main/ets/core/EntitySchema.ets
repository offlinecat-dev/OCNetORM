/**
 * 快速实体注册工具
 * 用于批量声明实体与列的映射信息
 */

import { ColumnType } from '../types/ColumnType'
import { MetadataStorage } from './MetadataStorage'
import { EntityMetadata } from './EntityMetadata'
import { ScopeRegistry, ScopeFunction } from './ScopeRegistry'
import { ColumnOptions, createColumnOptions, registerColumn, registerPrimaryKey, registerAutoIncrementPrimaryKey } from '../decorators/ColumnDecorator'
import { registerEntity, createEntityOptions } from '../decorators/EntityDecorator'

/**
 * 列定义
 */
export interface ColumnSchema {
  /** 实体属性名 */
  property: string
  /** 数据库列名 */
  name?: string
  /** 列类型 */
  type?: ColumnType
  /** 是否允许为空 */
  nullable?: boolean
  /** 是否唯一 */
  unique?: boolean
  /** 默认值 */
  defaultValue?: string | number | boolean | null
  /** TEXT 长度 */
  length?: number
  /** 是否主键 */
  primaryKey?: boolean
  /** 是否自增主键（默认 true） */
  autoIncrement?: boolean
}

/**
 * 软删除配置
 */
export interface SoftDeleteSchema {
  /** 实体属性名，默认 deletedAt */
  propertyName?: string
  /** 数据库列名，默认 deleted_at */
  columnName?: string
}

/**
 * 实体定义
 */
export interface EntitySchema {
  /** 表名 */
  tableName?: string
  /** 列定义列表 */
  columns: Array<ColumnSchema>
  /** 软删除配置 */
  softDelete?: boolean | SoftDeleteSchema
  /** 查询作用域定义 */
  scopes?: Record<string, ScopeFunction>
}

/**
 * 快速定义实体
 * @param entityName 实体名称
 * @param schema 实体定义
 * @returns 实体元数据
 */
export function defineEntity(entityName: string, schema: EntitySchema): EntityMetadata {
  const storage = MetadataStorage.getInstance()

  if (!storage.hasEntity(entityName)) {
    registerEntity(entityName, schema.tableName ? createEntityOptions(schema.tableName) : undefined)
  } else if (schema.tableName) {
    const metadata = storage.getEntityMetadata(entityName)
    if (metadata !== null && metadata.tableName === entityName) {
      metadata.tableName = schema.tableName
    }
  }

  const metadata = storage.getEntityMetadata(entityName)
  if (metadata === null) {
    throw new Error(`实体 ${entityName} 注册失败，无法获取元数据`)
  }

  for (let i = 0; i < schema.columns.length; i++) {
    const columnSchema = schema.columns[i]
    const existing = metadata.getColumnByProperty(columnSchema.property)
    if (existing !== null) {
      continue
    }

    try {
      if (columnSchema.primaryKey) {
        const autoIncrement = columnSchema.autoIncrement !== undefined ? columnSchema.autoIncrement : true
        if (autoIncrement) {
          registerAutoIncrementPrimaryKey(entityName, columnSchema.property, columnSchema.name)
        } else {
          registerPrimaryKey(entityName, columnSchema.property, columnSchema.name)
        }
        continue
      }

      const options = buildColumnOptions(columnSchema)
      registerColumn(entityName, columnSchema.property, options)
    } catch (e) {
      throw new Error(`注册列 ${columnSchema.property} 失败: ${e instanceof Error ? e.message : String(e)}`)
    }
  }

  if (schema.softDelete && metadata !== null) {
    const config = normalizeSoftDelete(schema.softDelete)
    metadata.setSoftDelete(true, config.columnName)

    const existing = metadata.getColumnByProperty(config.propertyName)
    if (existing === null) {
      try {
        const softDeleteOptions = createColumnOptions()
        softDeleteOptions.name = config.columnName
        softDeleteOptions.type = ColumnType.INTEGER
        softDeleteOptions.nullable = true
        registerColumn(entityName, config.propertyName, softDeleteOptions)
      } catch (e) {
        throw new Error(`注册软删除列失败: ${e instanceof Error ? e.message : String(e)}`)
      }
    }
  }

  // 注册查询作用域
  if (schema.scopes !== undefined) {
    const scopeRegistry = ScopeRegistry.getInstance()
    scopeRegistry.registerScopes(entityName, schema.scopes)
  }

  return metadata
}

/**
 * 创建 ColumnOptions
 */
function buildColumnOptions(schema: ColumnSchema): ColumnOptions {
  const options = createColumnOptions()
  if (schema.name !== undefined) {
    options.name = schema.name
  }
  if (schema.type !== undefined) {
    options.type = schema.type
  }
  if (schema.nullable !== undefined) {
    options.nullable = schema.nullable
  }
  if (schema.unique !== undefined) {
    options.unique = schema.unique
  }
  if (schema.defaultValue !== undefined) {
    options.defaultValue = schema.defaultValue
  }
  if (schema.length !== undefined) {
    options.length = schema.length
  }
  return options
}

function normalizeSoftDelete(config: boolean | SoftDeleteSchema): Required<SoftDeleteSchema> {
  if (config === true) {
    return { propertyName: 'deletedAt', columnName: 'deleted_at' }
  }
  if (config === false) {
    return { propertyName: 'deletedAt', columnName: 'deleted_at' }
  }
  return {
    propertyName: config.propertyName ? config.propertyName : 'deletedAt',
    columnName: config.columnName ? config.columnName : 'deleted_at'
  }
}
