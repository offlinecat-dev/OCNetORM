/**
 * Schema 构建器
 * 根据实体元数据生成 CREATE TABLE SQL 语句
 */

import { relationalStore } from '@kit.ArkData'
import { EntityMetadata } from '../core/EntityMetadata'
import { ColumnMetadata } from '../core/ColumnMetadata'
import { MetadataStorage } from '../core/MetadataStorage'
import { ManyToManyMetadata } from '../core/ManyToManyMetadata'
import { ColumnType } from '../types/ColumnType'
import { RelationType } from '../types/RelationType'
import { DatabaseManager } from '../database/DatabaseManager'
import { ExecutionError } from '../errors/DatabaseError'

/**
 * 建表执行结果类
 */
export class CreateTableResult {
  /** 是否成功 */
  success: boolean = false
  /** 表名 */
  tableName: string = ''
  /** 执行的 SQL */
  sql: string = ''
  /** 错误信息 */
  errorMessage: string = ''

  static createSuccess(tableName: string, sql: string): CreateTableResult {
    const result = new CreateTableResult()
    result.success = true
    result.tableName = tableName
    result.sql = sql
    return result
  }

  static createFailure(tableName: string, sql: string, errorMessage: string): CreateTableResult {
    const result = new CreateTableResult()
    result.success = false
    result.tableName = tableName
    result.sql = sql
    result.errorMessage = errorMessage
    return result
  }
}

/**
 * 批量建表执行结果类
 */
export class CreateAllTablesResult {
  /** 是否全部成功 */
  success: boolean = false
  /** 成功创建的表数量 */
  successCount: number = 0
  /** 失败的表数量 */
  failureCount: number = 0
  /** 各表的执行结果 */
  results: Array<CreateTableResult> = []

  static create(results: Array<CreateTableResult>): CreateAllTablesResult {
    const allResult = new CreateAllTablesResult()
    allResult.results = results

    let successCount = 0
    let failureCount = 0
    for (let i = 0; i < results.length; i++) {
      if (results[i].success) {
        successCount++
      } else {
        failureCount++
      }
    }

    allResult.successCount = successCount
    allResult.failureCount = failureCount
    allResult.success = failureCount === 0

    return allResult
  }
}

/**
 * SQL 建表语句生成器
 * 负责根据实体元数据生成符合 SQLite 语法的 CREATE TABLE 语句
 */
export class SchemaBuilder {
  /**
   * 转义 SQL 标识符（表名、列名）
   * 使用双引号包裹并转义内部的双引号，防止 SQL 注入
   * @param identifier 标识符（表名或列名）
   * @returns 转义后的标识符
   */
  private escapeIdentifier(identifier: string): string {
    // 替换双引号为两个双引号（SQLite 转义规则）
    const escaped = identifier.replace(/"/g, '""')
    return `"${escaped}"`
  }

  /**
   * 收集所有多对多关联关系（去重）
   * @returns 多对多关联元数据数组
   */
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

  /**
   * 获取多对多中间表外键列类型
   */
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

  /**
   * 生成多对多中间表的 CREATE TABLE SQL
   */
  private generateCreateJoinTableSql(relation: ManyToManyMetadata): string {
    const joinTable = this.escapeIdentifier(relation.joinTable)
    const joinSourceKey = this.escapeIdentifier(relation.joinSourceKey)
    const joinTargetKey = this.escapeIdentifier(relation.joinTargetKey)
    const sourceType = this.resolveJoinColumnType(relation.sourceEntity)
    const targetType = this.resolveJoinColumnType(relation.targetEntity)

    return `CREATE TABLE IF NOT EXISTS ${joinTable} (${joinSourceKey} ${sourceType} NOT NULL, ${joinTargetKey} ${targetType} NOT NULL, UNIQUE(${joinSourceKey}, ${joinTargetKey}))`
  }

  /**
   * 创建多对多中间表
   */
  private async createJoinTable(
    store: relationalStore.RdbStore,
    relation: ManyToManyMetadata
  ): Promise<CreateTableResult> {
    const sql = this.generateCreateJoinTableSql(relation)

    try {
      await store.executeSql(sql)
      return CreateTableResult.createSuccess(relation.joinTable, sql)
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      return CreateTableResult.createFailure(relation.joinTable, sql, errorMessage)
    }
  }
  /**
   * 根据实体元数据生成 CREATE TABLE SQL 语句
   * @param metadata 实体元数据
   * @returns CREATE TABLE SQL 语句
   */
  generateCreateTableSql(metadata: EntityMetadata): string {
    const tableName = metadata.tableName
    const columnDefinitions: Array<string> = []

    // 遍历所有列，生成列定义
    for (let i = 0; i < metadata.columns.length; i++) {
      const column = metadata.columns[i]
      const columnDef = this.generateColumnDefinition(column)
      columnDefinitions.push(columnDef)
    }

    // 组装完整的 CREATE TABLE 语句
    // 使用转义后的表名防止 SQL 注入
    const columnsStr = columnDefinitions.join(', ')
    const escapedTableName = this.escapeIdentifier(tableName)
    const sql = `CREATE TABLE IF NOT EXISTS ${escapedTableName} (${columnsStr})`

    return sql
  }

  /**
   * 生成单个列的定义 SQL 片段
   * @param column 列元数据
   * @returns 列定义 SQL 片段
   */
  private generateColumnDefinition(column: ColumnMetadata): string {
    const parts: Array<string> = []

    // 列名（使用转义后的列名防止 SQL 注入）
    parts.push(this.escapeIdentifier(column.columnName))

    // 列类型
    parts.push(column.columnType)

    // 主键约束
    if (column.isPrimaryKey) {
      parts.push('PRIMARY KEY')
    }

    // 自增约束（仅对 INTEGER 主键有效）
    if (column.isAutoIncrement && column.isPrimaryKey && column.columnType === ColumnType.INTEGER) {
      parts.push('AUTOINCREMENT')
    }

    // 非空约束（主键默认非空，不需要显式声明）
    if (!column.isNullable && !column.isPrimaryKey) {
      parts.push('NOT NULL')
    }

    // 唯一约束（主键默认唯一，不需要显式声明）
    if (column.isUnique && !column.isPrimaryKey) {
      parts.push('UNIQUE')
    }

    // 默认值
    if (column.defaultValue !== null) {
      const defaultVal = this.formatDefaultValue(column.defaultValue, column.columnType)
      parts.push(`DEFAULT ${defaultVal}`)
    }

    return parts.join(' ')
  }

  /**
   * 格式化默认值
   * @param value 默认值
   * @param columnType 列类型
   * @returns 格式化后的默认值字符串
   */
  private formatDefaultValue(value: string | number | boolean, columnType: ColumnType): string {
    if (typeof value === 'string') {
      // 字符串类型需要用单引号包裹，并转义内部的单引号
      const escaped = value.replace(/'/g, "''")
      return `'${escaped}'`
    }
    if (typeof value === 'boolean') {
      return value ? '1' : '0'
    }
    // 数字类型直接返回
    return value.toString()
  }

  /**
   * 根据实体名称生成 CREATE TABLE SQL 语句
   * @param entityName 实体类名
   * @returns CREATE TABLE SQL 语句，如果实体未注册返回空字符串
   */
  generateCreateTableSqlByName(entityName: string): string {
    const storage = MetadataStorage.getInstance()
    const metadata = storage.getEntityMetadata(entityName)
    if (metadata === null) {
      return ''
    }
    return this.generateCreateTableSql(metadata)
  }

  /**
   * 生成所有已注册实体的 CREATE TABLE SQL 语句
   * @returns SQL 语句数组
   */
  generateAllCreateTableSql(includeJoinTables: boolean = false): Array<string> {
    const storage = MetadataStorage.getInstance()
    const entities = storage.getAllEntities()
    const sqlStatements: Array<string> = []

    for (let i = 0; i < entities.length; i++) {
      const sql = this.generateCreateTableSql(entities[i])
      sqlStatements.push(sql)
    }

    if (includeJoinTables) {
      const relations = this.collectManyToManyRelations()
      for (let i = 0; i < relations.length; i++) {
        sqlStatements.push(this.generateCreateJoinTableSql(relations[i]))
      }
    }

    return sqlStatements
  }

  /**
   * 执行建表操作
   * @param store RdbStore 实例
   * @param metadata 实体元数据
   * @returns Promise<CreateTableResult>
   */
  async createTable(store: relationalStore.RdbStore, metadata: EntityMetadata): Promise<CreateTableResult> {
    const sql = this.generateCreateTableSql(metadata)

    try {
      await store.executeSql(sql)
      return CreateTableResult.createSuccess(metadata.tableName, sql)
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      return CreateTableResult.createFailure(metadata.tableName, sql, errorMessage)
    }
  }

  /**
   * 根据实体名称执行建表操作
   * @param store RdbStore 实例
   * @param entityName 实体名称
   * @returns Promise<CreateTableResult>
   */
  async createTableByName(store: relationalStore.RdbStore, entityName: string): Promise<CreateTableResult> {
    const storage = MetadataStorage.getInstance()
    const metadata = storage.getEntityMetadata(entityName)

    if (metadata === null) {
      return CreateTableResult.createFailure(entityName, '', `实体 '${entityName}' 未注册`)
    }

    return await this.createTable(store, metadata)
  }

  /**
   * 批量创建所有已注册实体的表
   * @param store RdbStore 实例
   * @returns Promise<CreateAllTablesResult>
   */
  async createAllTables(
    store: relationalStore.RdbStore,
    includeJoinTables: boolean = true
  ): Promise<CreateAllTablesResult> {
    const storage = MetadataStorage.getInstance()
    const entities = storage.getAllEntities()
    const results: Array<CreateTableResult> = []

    for (let i = 0; i < entities.length; i++) {
      const result = await this.createTable(store, entities[i])
      results.push(result)
    }

    if (includeJoinTables) {
      const relations = this.collectManyToManyRelations()
      for (let i = 0; i < relations.length; i++) {
        const result = await this.createJoinTable(store, relations[i])
        results.push(result)
      }
    }

    return CreateAllTablesResult.create(results)
  }

  /**
   * 使用 DatabaseManager 执行建表操作
   * @param metadata 实体元数据
   * @returns Promise<CreateTableResult>
   */
  async createTableWithManager(metadata: EntityMetadata): Promise<CreateTableResult> {
    try {
      const store = DatabaseManager.getInstance().getStore()
      return await this.createTable(store, metadata)
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      return CreateTableResult.createFailure(metadata.tableName, '', errorMessage)
    }
  }

  /**
   * 使用 DatabaseManager 批量创建所有已注册实体的表
   * @returns Promise<CreateAllTablesResult>
   */
  async createAllTablesWithManager(includeJoinTables: boolean = true): Promise<CreateAllTablesResult> {
    try {
      const store = DatabaseManager.getInstance().getStore()
      return await this.createAllTables(store, includeJoinTables)
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      const failResult = CreateTableResult.createFailure('', '', errorMessage)
      return CreateAllTablesResult.create([failResult])
    }
  }
}
