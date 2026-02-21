/**
 * 快速实体注册工具
 * 用于批量声明实体与列的映射信息
 */

import { ColumnType } from '../types/ColumnType'
import { MetadataStorage } from './MetadataStorage'
import { EntityMetadata } from './EntityMetadata'
import { IndexMetadata } from './IndexMetadata'
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
 * 多态单值关系配置
 */
export interface MorphToSchema {
  /** 关联属性名 */
  name: string
  /** ID 字段（源实体字段） */
  idColumn: string
  /** 类型字段（源实体字段） */
  typeColumn: string
  /** 类型值到实体名映射 */
  typeMap?: Record<string, string>
}

/**
 * 索引配置
 */
export interface IndexSchema {
  /** 索引名称（可选，不传自动生成） */
  name?: string
  /** 索引列（可传属性名或列名） */
  columns: Array<string>
  /** 是否唯一索引 */
  unique?: boolean
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
  /** 多态单值关系配置 */
  morphTo?: MorphToSchema | Array<MorphToSchema>
  /** 索引配置 */
  indexes?: Array<IndexSchema>
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

  if (schema.morphTo !== undefined) {
    registerMorphToRelations(storage, entityName, schema.morphTo)
  }

  if (schema.indexes !== undefined) {
    registerIndexes(metadata, schema.indexes)
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

function registerMorphToRelations(
  storage: MetadataStorage,
  entityName: string,
  morphToConfig: MorphToSchema | Array<MorphToSchema>
): void {
  const configs = morphToConfig instanceof Array ? morphToConfig : [morphToConfig]
  for (let i = 0; i < configs.length; i++) {
    const item = configs[i]
    if (item.name.trim().length === 0) {
      throw new Error('morphTo.name 不能为空')
    }
    if (item.idColumn.trim().length === 0) {
      throw new Error(`morphTo(${item.name}) idColumn 不能为空`)
    }
    if (item.typeColumn.trim().length === 0) {
      throw new Error(`morphTo(${item.name}) typeColumn 不能为空`)
    }
    if (storage.getRelation(entityName, item.name.trim()) !== null) {
      continue
    }
    storage.registerMorphTo(
      entityName,
      item.name.trim(),
      item.idColumn.trim(),
      item.typeColumn.trim(),
      item.typeMap ? item.typeMap : {}
    )
  }
}

function registerIndexes(metadata: EntityMetadata, indexes: Array<IndexSchema>): void {
  for (let i = 0; i < indexes.length; i++) {
    const indexSchema = indexes[i]
    const columns = resolveIndexColumns(metadata, indexSchema.columns)
    if (columns.length === 0) {
      throw new Error('index.columns 不能为空')
    }
    const unique = indexSchema.unique === true
    const indexName = buildIndexName(metadata.tableName, columns, unique, indexSchema.name)
    metadata.addIndex(new IndexMetadata(indexName, columns, unique))
  }
}

function resolveIndexColumns(metadata: EntityMetadata, candidates: Array<string>): Array<string> {
  const columns: Array<string> = []
  for (let i = 0; i < candidates.length; i++) {
    const token = candidates[i].trim()
    if (token.length === 0) {
      continue
    }
    const byProperty = metadata.getColumnByProperty(token)
    if (byProperty !== null) {
      columns.push(byProperty.columnName)
      continue
    }
    const byName = metadata.getColumnByName(token)
    if (byName !== null) {
      columns.push(byName.columnName)
      continue
    }
    throw new Error(`索引列未注册: ${token}`)
  }
  return columns
}

function buildIndexName(
  tableName: string,
  columns: Array<string>,
  unique: boolean,
  customName?: string
): string {
  if (customName !== undefined && customName.trim().length > 0) {
    return customName.trim()
  }
  const prefix = unique ? 'uidx' : 'idx'
  const parts: Array<string> = []
  parts.push(sanitizeIndexToken(tableName))
  for (let i = 0; i < columns.length; i++) {
    parts.push(sanitizeIndexToken(columns[i]))
  }
  return `${prefix}_${parts.join('_')}`
}

function sanitizeIndexToken(value: string): string {
  return value.replace(/[^A-Za-z0-9_]/g, '_')
}
