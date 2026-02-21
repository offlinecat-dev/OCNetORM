/**
 * 实体元数据类
 * 存储整个实体类到数据库表的映射信息
 */

import { ColumnMetadata } from './ColumnMetadata'
import { IndexMetadata } from './IndexMetadata'
import { EntityHooks } from '../types/EntityHooks'

/**
 * 实体元数据
 * 记录实体类与数据库表之间的映射关系
 */
export class EntityMetadata {
  /** 实体类名 */
  entityName: string = ''

  /** 数据库表名 */
  tableName: string = ''

  /** 列元数据数组 */
  columns: Array<ColumnMetadata> = []

  /** 索引元数据数组 */
  indexes: Array<IndexMetadata> = []

  /** 是否启用软删除 */
  softDelete: boolean = false

  /** 软删除时间戳列名，默认为 'deleted_at' */
  deletedAtColumn: string = 'deleted_at'

  /** 实体生命周期钩子 */
  hooks: EntityHooks | null = null

  /**
   * 构造函数
   * @param entityName 实体类名
   * @param tableName 数据库表名（可选，默认使用实体类名）
   * @param softDelete 是否启用软删除（可选，默认 false）
   * @param deletedAtColumn 软删除时间戳列名（可选，默认 'deleted_at'）
   * @param hooks 实体生命周期钩子（可选）
   */
  constructor(
    entityName: string,
    tableName?: string,
    softDelete?: boolean,
    deletedAtColumn?: string,
    hooks?: EntityHooks | null
  ) {
    this.entityName = entityName
    this.tableName = tableName ? tableName : entityName
    if (softDelete !== undefined) {
      this.softDelete = softDelete
    }
    if (deletedAtColumn !== undefined) {
      this.deletedAtColumn = deletedAtColumn
    }
    if (hooks !== undefined) {
      this.hooks = hooks
    }
  }

  /**
   * 添加列元数据
   * @param column 列元数据
   */
  addColumn(column: ColumnMetadata): void {
    this.columns.push(column)
  }

  /**
   * 添加索引元数据（按名称或签名去重）
   * @param index 索引元数据
   */
  addIndex(index: IndexMetadata): void {
    const signature = index.getSignature()
    for (let i = 0; i < this.indexes.length; i++) {
      const existing = this.indexes[i]
      if (existing.name === index.name || existing.getSignature() === signature) {
        return
      }
    }
    this.indexes.push(index)
  }

  /**
   * 获取索引元数据列表
   */
  getIndexes(): Array<IndexMetadata> {
    return this.indexes.slice()
  }

  hasIndex(indexName: string): boolean {
    for (let i = 0; i < this.indexes.length; i++) {
      if (this.indexes[i].name === indexName) {
        return true
      }
    }
    return false
  }

  /**
   * 根据属性名获取列元数据
   * @param propertyName ArkTS 属性名
   * @returns 列元数据，如果不存在返回 null
   */
  getColumnByProperty(propertyName: string): ColumnMetadata | null {
    for (let i = 0; i < this.columns.length; i++) {
      const col = this.columns[i]
      if (col.propertyName === propertyName) {
        return col
      }
    }
    return null
  }

  /**
   * 根据列名获取列元数据
   * @param columnName 数据库列名
   * @returns 列元数据，如果不存在返回 null
   */
  getColumnByName(columnName: string): ColumnMetadata | null {
    for (let i = 0; i < this.columns.length; i++) {
      const col = this.columns[i]
      if (col.columnName === columnName) {
        return col
      }
    }
    return null
  }

  /**
   * 获取主键列元数据
   * @returns 主键列元数据，如果不存在返回 null
   */
  getPrimaryKeyColumn(): ColumnMetadata | null {
    for (let i = 0; i < this.columns.length; i++) {
      const col = this.columns[i]
      if (col.isPrimaryKey) {
        return col
      }
    }
    return null
  }

  /**
   * 检查是否有主键
   * @returns 是否有主键
   */
  hasPrimaryKey(): boolean {
    return this.getPrimaryKeyColumn() !== null
  }

  /**
   * 获取所有非主键列
   * @returns 非主键列数组
   */
  getNonPrimaryKeyColumns(): Array<ColumnMetadata> {
    const result: Array<ColumnMetadata> = []
    for (let i = 0; i < this.columns.length; i++) {
      const col = this.columns[i]
      if (!col.isPrimaryKey) {
        result.push(col)
      }
    }
    return result
  }

  /**
   * 获取列数量
   * @returns 列数量
   */
  getColumnCount(): number {
    return this.columns.length
  }

  /**
   * 检查是否启用软删除
   * @returns 是否启用软删除
   */
  isSoftDeleteEnabled(): boolean {
    return this.softDelete
  }

  /**
   * 获取软删除时间戳列名
   * @returns 软删除时间戳列名
   */
  getDeletedAtColumn(): string {
    if (!this.deletedAtColumn) {
      return 'deleted_at'
    }
    return this.deletedAtColumn
  }

  /**
   * 设置软删除配置
   * @param enabled 是否启用软删除
   * @param columnName 软删除时间戳列名（可选）
   */
  setSoftDelete(enabled: boolean, columnName?: string): void {
    this.softDelete = enabled
    if (columnName !== undefined) {
      this.deletedAtColumn = columnName
    }
  }

  /**
   * 获取实体钩子
   * @returns 实体钩子，如果未设置返回 null
   */
  getHooks(): EntityHooks | null {
    return this.hooks
  }

  /**
   * 设置实体钩子
   * @param hooks 实体钩子
   */
  setHooks(hooks: EntityHooks | null): void {
    this.hooks = hooks
  }

  /**
   * 检查是否有钩子配置
   * @returns 是否有钩子配置
   */
  hasHooks(): boolean {
    return this.hooks !== null
  }
}
