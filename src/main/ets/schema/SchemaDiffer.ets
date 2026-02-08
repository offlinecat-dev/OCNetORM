/**
 * Schema 差异分析器
 * 根据实体元数据与数据库实际结构生成变更计划
 */

import { relationalStore } from '@kit.ArkData'
import { ColumnMetadata } from '../core/ColumnMetadata'
import { MetadataStorage } from '../core/MetadataStorage'
import { ManyToManyMetadata } from '../core/ManyToManyMetadata'
import { RelationType } from '../types/RelationType'
import { ColumnType } from '../types/ColumnType'
import { SchemaInspector, TableInfo, ColumnInfo } from './SchemaInspector'

/**
 * Schema 变更类型
 */
export enum SchemaChangeType {
  /** 新建表 */
  CREATE_TABLE = 'CREATE_TABLE',
  /** 新增列 */
  ADD_COLUMN = 'ADD_COLUMN',
  /** 重建表（包含删除/修改列） */
  REBUILD_TABLE = 'REBUILD_TABLE'
}

/**
 * Schema 变更项
 */
export interface SchemaChange {
  type: SchemaChangeType
  tableName: string
  columnName?: string
  sql: Array<string>
  rollbackSql: Array<string>
  summary: string
  destructive: boolean
}

/**
 * Schema 差异分析结果
 */
export class SchemaDiffResult {
  changes: Array<SchemaChange> = []
  plannedSql: Array<string> = []
  rollbackSql: Array<string> = []

  addChange(change: SchemaChange): void {
    this.changes.push(change)
    this.plannedSql.push(...change.sql)
    this.rollbackSql.push(...change.rollbackSql)
  }

  hasChanges(): boolean {
    return this.changes.length > 0
  }
}

/**
 * Schema diff 选项
 */
export interface SchemaDiffOptions {
  includeJoinTables?: boolean
}

/**
 * 列差异对
 */
class ColumnDiffPair {
  desired: ColumnMetadata
  existing: ColumnInfo

  constructor(desired: ColumnMetadata, existing: ColumnInfo) {
    this.desired = desired
    this.existing = existing
  }
}

/**
 * Schema 差异分析器
 */
export class SchemaDiffer {
  private inspector: SchemaInspector

  constructor(inspector?: SchemaInspector) {
    this.inspector = inspector ? inspector : new SchemaInspector()
  }

  /**
   * 生成 Schema 差异
   */
  async diff(store: relationalStore.RdbStore, options?: SchemaDiffOptions): Promise<SchemaDiffResult> {
    const includeJoinTables = options?.includeJoinTables !== false
    const desiredTables = this.buildDesiredTables(includeJoinTables)
    const existingTables = await this.inspector.getExistingTables(store)
    const result = new SchemaDiffResult()

    for (let i = 0; i < desiredTables.length; i++) {
      const desired = desiredTables[i]
      const tableName = desired.tableName
      const existing = existingTables.indexOf(tableName) >= 0

      if (!existing) {
        const rollbackSql = [`DROP TABLE IF EXISTS ${this.escapeIdentifier(tableName)}`]
        result.addChange({
          type: SchemaChangeType.CREATE_TABLE,
          tableName,
          sql: [desired.createSql],
          rollbackSql,
          summary: `创建表 ${tableName}`,
          destructive: false
        })
        continue
      }

      const tableInfo = await this.inspector.getTableInfo(store, tableName)
      this.collectColumnChanges(result, desired, tableInfo)
    }

    return result
  }

  private collectColumnChanges(result: SchemaDiffResult, desired: DesiredTable, tableInfo: TableInfo): void {
    const desiredColumnMap = this.mapDesiredColumns(desired.columns)
    const existingColumnMap = this.mapExistingColumns(tableInfo.columns)

    const columnsToAdd: Array<ColumnMetadata> = []
    const columnsToModify: Array<ColumnDiffPair> = []
    const columnsToDrop: Array<ColumnInfo> = []

    desiredColumnMap.forEach((column, name) => {
      const existing = existingColumnMap.get(name)
      if (!existing) {
        columnsToAdd.push(column)
      } else if (!this.isColumnCompatible(column, existing)) {
        columnsToModify.push(new ColumnDiffPair(column, existing))
      }
    })

    existingColumnMap.forEach((column, name) => {
      if (!desiredColumnMap.has(name)) {
        columnsToDrop.push(column)
      }
    })

    const requiresRebuild = this.requiresRebuild(columnsToAdd, columnsToModify, columnsToDrop)

    if (requiresRebuild) {
      const rebuildChange = this.buildRebuildChange(desired, tableInfo, columnsToModify, columnsToDrop)
      result.addChange(rebuildChange)
      return
    }

    for (let i = 0; i < columnsToAdd.length; i++) {
      const column = columnsToAdd[i]
      const columnDefinition = this.generateColumnDefinition(column)
      const sql = `ALTER TABLE ${this.escapeIdentifier(desired.tableName)} ADD COLUMN ${columnDefinition}`
      const rollbackSql = [`-- 回滚建议: SQLite 不支持直接删除列，请手动重建表`]
      result.addChange({
        type: SchemaChangeType.ADD_COLUMN,
        tableName: desired.tableName,
        columnName: column.columnName,
        sql: [sql],
        rollbackSql,
        summary: `新增列 ${desired.tableName}.${column.columnName}`,
        destructive: false
      })
    }
  }

  private requiresRebuild(
    columnsToAdd: Array<ColumnMetadata>,
    columnsToModify: Array<ColumnDiffPair>,
    columnsToDrop: Array<ColumnInfo>
  ): boolean {
    if (columnsToModify.length > 0 || columnsToDrop.length > 0) {
      return true
    }

    for (let i = 0; i < columnsToAdd.length; i++) {
      const column = columnsToAdd[i]
      if (column.isPrimaryKey || column.isAutoIncrement) {
        return true
      }
      if (!column.isNullable && column.defaultValue === null) {
        return true
      }
    }

    return false
  }

  private buildRebuildChange(
    desired: DesiredTable,
    tableInfo: TableInfo,
    columnsToModify: Array<ColumnDiffPair>,
    columnsToDrop: Array<ColumnInfo>
  ): SchemaChange {
    const timestamp = Date.now()
    const tableName = desired.tableName
    const escapedTable = this.escapeIdentifier(tableName)
    const tempTable = `__ocorm_tmp_${tableName}_${timestamp}`
    const backupTable = `__ocorm_backup_${tableName}_${timestamp}`

    const existingColumnNames = tableInfo.columns.map((col) => col.name)
    const desiredColumnNames = desired.columns.map((col) => col.columnName)
    const intersection = desiredColumnNames.filter((name) => existingColumnNames.indexOf(name) >= 0)

    const sql: Array<string> = []
    const rollbackSql: Array<string> = []

    const backupColumns = this.collectBackupColumns(tableInfo, columnsToModify, columnsToDrop)
    if (backupColumns.length > 0) {
      const backupColumnSql = backupColumns.map((name) => this.escapeIdentifier(name)).join(', ')
      sql.push(`CREATE TABLE IF NOT EXISTS ${this.escapeIdentifier(backupTable)} AS SELECT ${backupColumnSql} FROM ${escapedTable}`)
      rollbackSql.push(`-- 回滚建议: 从备份表 ${backupTable} 恢复列数据`) 
      rollbackSql.push(`INSERT INTO ${escapedTable} (${backupColumnSql}) SELECT ${backupColumnSql} FROM ${this.escapeIdentifier(backupTable)}`)
    }

    const createTempSql = this.generateCreateTableSql(tempTable, desired.columns)
    sql.push(createTempSql)

    if (intersection.length > 0) {
      const intersectionSql = intersection.map((name) => this.escapeIdentifier(name)).join(', ')
      sql.push(`INSERT INTO ${this.escapeIdentifier(tempTable)} (${intersectionSql}) SELECT ${intersectionSql} FROM ${escapedTable}`)
    }

    sql.push(`DROP TABLE ${escapedTable}`)
    sql.push(`ALTER TABLE ${this.escapeIdentifier(tempTable)} RENAME TO ${this.escapeIdentifier(tableName)}`)

    rollbackSql.push(`-- 回滚建议: 使用 ${backupTable} 中的数据手动恢复或回滚版本库`) 

    return {
      type: SchemaChangeType.REBUILD_TABLE,
      tableName,
      sql,
      rollbackSql,
      summary: `重建表 ${tableName}（修改列: ${columnsToModify.length}, 删除列: ${columnsToDrop.length}）`,
      destructive: true
    }
  }

  private collectBackupColumns(
    tableInfo: TableInfo,
    columnsToModify: Array<ColumnDiffPair>,
    columnsToDrop: Array<ColumnInfo>
  ): Array<string> {
    const backupSet = new Set<string>()

    const primaryKeys = tableInfo.columns.filter((col) => col.primaryKey).map((col) => col.name)
    for (let i = 0; i < primaryKeys.length; i++) {
      backupSet.add(primaryKeys[i])
    }

    for (let i = 0; i < columnsToModify.length; i++) {
      backupSet.add(columnsToModify[i].existing.name)
    }

    for (let i = 0; i < columnsToDrop.length; i++) {
      backupSet.add(columnsToDrop[i].name)
    }

    return Array.from(backupSet.values())
  }

  private mapDesiredColumns(columns: Array<ColumnMetadata>): Map<string, ColumnMetadata> {
    const map = new Map<string, ColumnMetadata>()
    for (let i = 0; i < columns.length; i++) {
      map.set(columns[i].columnName, columns[i])
    }
    return map
  }

  private mapExistingColumns(columns: Array<ColumnInfo>): Map<string, ColumnInfo> {
    const map = new Map<string, ColumnInfo>()
    for (let i = 0; i < columns.length; i++) {
      map.set(columns[i].name, columns[i])
    }
    return map
  }

  private isColumnCompatible(column: ColumnMetadata, existing: ColumnInfo): boolean {
    const desiredType = this.normalizeType(column.columnType)
    const existingType = this.normalizeType(existing.type)
    if (desiredType !== existingType) {
      return false
    }

    const desiredNotNull = !column.isNullable || column.isPrimaryKey
    if (desiredNotNull !== existing.notNull) {
      return false
    }

    if (column.isPrimaryKey !== existing.primaryKey) {
      return false
    }

    const desiredDefault = column.defaultValue === null
      ? null
      : this.normalizeDefaultValue(this.formatDefaultValue(column.defaultValue, column.columnType))
    const existingDefault = existing.defaultValue === null
      ? null
      : this.normalizeDefaultValue(existing.defaultValue)

    if (desiredDefault !== existingDefault) {
      return false
    }

    return true
  }

  private normalizeType(value: string): string {
    const upper = value.toUpperCase().trim()
    const match = upper.match(/^[A-Z]+/)
    return match ? match[0] : upper
  }

  private normalizeDefaultValue(value: string): string {
    const trimmed = value.trim()
    if (trimmed.length >= 2) {
      const first = trimmed[0]
      const last = trimmed[trimmed.length - 1]
      if ((first === "'" && last === "'") || (first === '"' && last === '"')) {
        return trimmed.substring(1, trimmed.length - 1)
      }
    }
    return trimmed
  }

  private buildDesiredTables(includeJoinTables: boolean): Array<DesiredTable> {
    const storage = MetadataStorage.getInstance()
    const entities = storage.getAllEntities()
    const tables: Array<DesiredTable> = []

    for (let i = 0; i < entities.length; i++) {
      const metadata = entities[i]
      tables.push({
        tableName: metadata.tableName,
        columns: metadata.columns,
        createSql: this.generateCreateTableSql(metadata.tableName, metadata.columns),
        isJoinTable: false
      })
    }

    if (includeJoinTables) {
      const relations = this.collectManyToManyRelations()
      for (let i = 0; i < relations.length; i++) {
        const relation = relations[i]
        const columns = this.buildJoinTableColumns(relation)
        tables.push({
          tableName: relation.joinTable,
          columns,
          createSql: this.generateJoinTableSql(relation),
          isJoinTable: true
        })
      }
    }

    return tables
  }

  private collectManyToManyRelations(): Array<ManyToManyMetadata> {
    const storage = MetadataStorage.getInstance()
    const entities = storage.getAllEntities()
    const relationMap: Map<string, ManyToManyMetadata> = new Map()

    for (let i = 0; i < entities.length; i++) {
      const entityName = entities[i].entityName
      const relations = storage.getRelations(entityName)
      for (let j = 0; j < relations.length; j++) {
        const relation = relations[j]
        if (relation.type !== RelationType.MANY_TO_MANY) {
          continue
        }
        const manyToMany = relation as ManyToManyMetadata
        if (!manyToMany.joinTable) {
          continue
        }
        if (!relationMap.has(manyToMany.joinTable)) {
          relationMap.set(manyToMany.joinTable, manyToMany)
        }
      }
    }

    return Array.from(relationMap.values())
  }

  private resolveJoinColumnType(entityName: string): ColumnType {
    const metadata = MetadataStorage.getInstance().getEntityMetadata(entityName)
    if (metadata === null) {
      return ColumnType.INTEGER
    }
    const pkColumn = metadata.getPrimaryKeyColumn()
    if (pkColumn === null) {
      return ColumnType.INTEGER
    }
    return pkColumn.columnType
  }

  private buildJoinTableColumns(relation: ManyToManyMetadata): Array<ColumnMetadata> {
    const sourceType = this.resolveJoinColumnType(relation.sourceEntity)
    const targetType = this.resolveJoinColumnType(relation.targetEntity)

    const sourceColumn = new ColumnMetadata(relation.joinSourceKey, relation.joinSourceKey)
    sourceColumn.columnType = sourceType
    sourceColumn.isNullable = false

    const targetColumn = new ColumnMetadata(relation.joinTargetKey, relation.joinTargetKey)
    targetColumn.columnType = targetType
    targetColumn.isNullable = false

    return [sourceColumn, targetColumn]
  }

  private generateJoinTableSql(relation: ManyToManyMetadata): string {
    const joinTable = this.escapeIdentifier(relation.joinTable)
    const joinSourceKey = this.escapeIdentifier(relation.joinSourceKey)
    const joinTargetKey = this.escapeIdentifier(relation.joinTargetKey)
    const sourceType = this.resolveJoinColumnType(relation.sourceEntity)
    const targetType = this.resolveJoinColumnType(relation.targetEntity)

    return `CREATE TABLE IF NOT EXISTS ${joinTable} (${joinSourceKey} ${sourceType} NOT NULL, ${joinTargetKey} ${targetType} NOT NULL, UNIQUE(${joinSourceKey}, ${joinTargetKey}))`
  }

  private generateCreateTableSql(tableName: string, columns: Array<ColumnMetadata>): string {
    const columnDefinitions: Array<string> = []

    for (let i = 0; i < columns.length; i++) {
      columnDefinitions.push(this.generateColumnDefinition(columns[i]))
    }

    const columnsStr = columnDefinitions.join(', ')
    const escapedTableName = this.escapeIdentifier(tableName)
    return `CREATE TABLE IF NOT EXISTS ${escapedTableName} (${columnsStr})`
  }

  private generateColumnDefinition(column: ColumnMetadata): string {
    const parts: Array<string> = []
    parts.push(this.escapeIdentifier(column.columnName))
    parts.push(column.columnType)

    if (column.isPrimaryKey) {
      parts.push('PRIMARY KEY')
    }

    if (column.isAutoIncrement && column.isPrimaryKey && column.columnType === ColumnType.INTEGER) {
      parts.push('AUTOINCREMENT')
    }

    if (!column.isNullable && !column.isPrimaryKey) {
      parts.push('NOT NULL')
    }

    if (column.isUnique && !column.isPrimaryKey) {
      parts.push('UNIQUE')
    }

    if (column.defaultValue !== null) {
      const defaultVal = this.formatDefaultValue(column.defaultValue, column.columnType)
      parts.push(`DEFAULT ${defaultVal}`)
    }

    return parts.join(' ')
  }

  private formatDefaultValue(value: string | number | boolean, columnType: ColumnType): string {
    if (typeof value === 'string') {
      const escaped = value.replace(/'/g, "''")
      return `'${escaped}'`
    }
    if (typeof value === 'boolean') {
      return value ? '1' : '0'
    }
    return value.toString()
  }

  private escapeIdentifier(identifier: string): string {
    const escaped = identifier.replace(/"/g, '""')
    return `"${escaped}"`
  }
}

interface DesiredTable {
  tableName: string
  columns: Array<ColumnMetadata>
  createSql: string
  isJoinTable: boolean
}
