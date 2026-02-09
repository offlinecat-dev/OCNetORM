/**
 * 查询构建器
 * 提供链式调用 API 构建数据库查询
 */

import { EntityMetadata } from '../core/EntityMetadata'
import { MetadataStorage } from '../core/MetadataStorage'
import { ScopeRegistry } from '../core/ScopeRegistry'
import { ConditionOperator } from '../types/ConditionOperator'
import { ValueType, OrderByClause, SortDirection } from '../types/ValueTypes'
import { WhereCondition, LogicalOperator } from './WhereCondition'
import { EntityNotRegisteredError } from '../errors/MetadataError'
import { InvalidConditionError, SubQueryError, ScopeNotFoundError } from '../errors/QueryError'
import { RelationNotFoundError } from '../errors/RelationError'
import { PaginationParams } from './PaginationParams'
import { SubQuery, SubQueryCallback } from './SubQuery'
import { QueryExecutor } from './QueryExecutor'
import { RelationQueryOptions, RelationCountOption } from './RelationQueryOptions'

export class BatchUpdateValues {
  private values: Map<string, ValueType> = new Map()

  set(columnOrProperty: string, value: ValueType): BatchUpdateValues {
    this.values.set(columnOrProperty, value)
    return this
  }

  get(columnOrProperty: string): ValueType {
    const value = this.values.get(columnOrProperty)
    if (value === undefined) {
      return null
    }
    return value
  }

  keys(): Array<string> {
    const keys: Array<string> = []
    this.values.forEach((_, key) => keys.push(key))
    return keys
  }

  size(): number {
    return this.values.size
  }

  static create(): BatchUpdateValues {
    return new BatchUpdateValues()
  }
}

/**
 * 泛型查询构建器
 * 支持链式调用构建复杂查询
 */
export class QueryBuilder {
  /** 实体元数据 */
  private entityMetadata: EntityMetadata

  /** 实体类名 */
  private entityName: string = ''

  /** WHERE 条件列表 */
  private conditions: Array<WhereCondition> = []

  /** ORDER BY 子句列表 */
  private orderByColumns: Array<OrderByClause> = []

  /** LIMIT 值 */
  private limitValue: number = 0

  /** OFFSET 值 */
  private offsetValue: number = 0

  /** SELECT 列列表（空表示选择所有列） */
  private selectedColumns: Array<string> = []

  /** 需要加载的关联关系名称列表 */
  private relationNames: Array<string> = []

  /** 延迟加载的关联关系名称列表 */
  private lazyRelationNames: Array<string> = []

  /** 是否包含已删除的数据（软删除） */
  private includeDeleted: boolean = false

  /** 是否仅查询已删除的数据（软删除） */
  private onlyDeletedFlag: boolean = false

  /** 分页页码（从 1 开始，0 表示未设置分页） */
  private pageNumber: number = 0

  /** 分页每页数量（0 表示未设置分页） */
  private pageSizeValue: number = 0

  /** 子查询列表（用于 whereExists 深层过滤） */
  private subQueries: Array<SubQuery> = []
  /** 查询超时（毫秒），0 表示禁用 */
  private queryTimeoutMs: number = 0

  /** GROUP BY 列列表 */
  private groupByColumns: Array<string> = []
  /** HAVING 子句 */
  private havingClause: string = ''
  /** HAVING 参数 */
  private havingArgs: Array<ValueType> = []
  /** 原生 SELECT 表达式（用于聚合查询） */
  private selectRawExpressions: Array<string> = []
  /** 关联过滤配置（key: 关联路径） */
  private relationQueryOptions: Map<string, RelationQueryOptions> = new Map()
  /** MorphTo 关联过滤回调（key: 关联路径） */
  private morphRelationQueryCallbacks: Map<string, (qb: QueryBuilder) => void> = new Map()
  /** 关联计数配置 */
  private relationCountOptions: Array<RelationCountOption> = []

  /**
   * 构造函数
   * @param entityName 实体类名
   * @throws EntityNotRegisteredError 如果实体未注册
   */
  constructor(entityName: string) {
    this.entityName = entityName
    const metadata = MetadataStorage.getInstance().getEntityMetadata(entityName)
    if (metadata === null) {
      throw new EntityNotRegisteredError(entityName)
    }
    this.entityMetadata = metadata
  }

  /**
   * 获取实体元数据
   * @returns 实体元数据
   */
  getEntityMetadata(): EntityMetadata {
    return this.entityMetadata
  }

  /**
   * 获取实体类名
   * @returns 实体类名
   */
  getEntityName(): string {
    return this.entityName
  }

  /**
   * 获取所有条件
   * @returns 条件数组
   */
  getConditions(): Array<WhereCondition> {
    return this.conditions
  }

  /**
   * 获取排序子句
   * @returns 排序子句数组
   */
  getOrderByColumns(): Array<OrderByClause> {
    return this.orderByColumns
  }

  /**
   * 获取 LIMIT 值
   * @returns LIMIT 值
   */
  getLimitValue(): number {
    return this.limitValue
  }

  /**
   * 获取 OFFSET 值
   * @returns OFFSET 值
   */
  getOffsetValue(): number {
    return this.offsetValue
  }

  /**
   * 获取选择的列
   * @returns 列名数组
   */
  getSelectedColumns(): Array<string> {
    return this.selectedColumns
  }

  /**
   * 获取表名
   * @returns 表名
   */
  getTableName(): string {
    return this.entityMetadata.tableName
  }

  /**
   * 添加 WHERE 条件
   * @param column 列名或属性名
   * @param operator 操作符
   * @param value 值
   * @returns 当前实例（支持链式调用）
   */
  where(column: string, operator: ConditionOperator, value: ValueType): QueryBuilder {
    const resolvedColumn = this.getResolvedColumnName(column)
    if (resolvedColumn === null) {
      throw new InvalidConditionError(column, `列 '${column}' 在实体 '${this.entityName}' 中不存在`)
    }
    this.ensureValidOperator(operator)
    const condition = new WhereCondition()
    condition.column = resolvedColumn
    condition.operator = operator
    condition.value = value
    condition.logicalOperator = LogicalOperator.AND
    this.conditions.push(condition)
    return this
  }

  /**
   * 添加 AND WHERE 条件
   * @param column 列名或属性名
   * @param operator 操作符
   * @param value 值
   * @returns 当前实例（支持链式调用）
   */
  andWhere(column: string, operator: ConditionOperator, value: ValueType): QueryBuilder {
    const resolvedColumn = this.getResolvedColumnName(column)
    if (resolvedColumn === null) {
      throw new InvalidConditionError(column, `列 '${column}' 在实体 '${this.entityName}' 中不存在`)
    }
    this.ensureValidOperator(operator)
    const condition = new WhereCondition()
    condition.column = resolvedColumn
    condition.operator = operator
    condition.value = value
    condition.logicalOperator = LogicalOperator.AND
    this.conditions.push(condition)
    return this
  }

  /**
   * 添加 OR WHERE 条件
   * @param column 列名或属性名
   * @param operator 操作符
   * @param value 值
   * @returns 当前实例（支持链式调用）
   */
  orWhere(column: string, operator: ConditionOperator, value: ValueType): QueryBuilder {
    const resolvedColumn = this.getResolvedColumnName(column)
    if (resolvedColumn === null) {
      throw new InvalidConditionError(column, `列 '${column}' 在实体 '${this.entityName}' 中不存在`)
    }
    this.ensureValidOperator(operator)
    const condition = new WhereCondition()
    condition.column = resolvedColumn
    condition.operator = operator
    condition.value = value
    condition.logicalOperator = LogicalOperator.OR
    this.conditions.push(condition)
    return this
  }

  /**
   * 添加 IN 条件
   * @param column 列名或属性名
   * @param values 值数组
   * @returns 当前实例（支持链式调用）
   */
  whereIn(column: string, values: Array<ValueType>): QueryBuilder {
    const resolvedColumn = this.getResolvedColumnName(column)
    if (resolvedColumn === null) {
      throw new InvalidConditionError(column, `列 '${column}' 在实体 '${this.entityName}' 中不存在`)
    }
    if (values.length === 0) {
      throw new InvalidConditionError(column, 'IN 条件不能为空')
    }
    const condition = WhereCondition.inValues(resolvedColumn, values)
    condition.logicalOperator = LogicalOperator.AND
    this.conditions.push(condition)
    return this
  }

  /**
   * 添加 IS NULL 条件
   * @param column 列名或属性名
   * @returns 当前实例（支持链式调用）
   */
  whereNull(column: string): QueryBuilder {
    const resolvedColumn = this.getResolvedColumnName(column)
    if (resolvedColumn === null) {
      throw new InvalidConditionError(column, `列 '${column}' 在实体 '${this.entityName}' 中不存在`)
    }
    const condition = WhereCondition.isNull(resolvedColumn)
    condition.logicalOperator = LogicalOperator.AND
    this.conditions.push(condition)
    return this
  }

  /**
   * 添加 IS NOT NULL 条件
   * @param column 列名或属性名
   * @returns 当前实例（支持链式调用）
   */
  whereNotNull(column: string): QueryBuilder {
    const resolvedColumn = this.getResolvedColumnName(column)
    if (resolvedColumn === null) {
      throw new InvalidConditionError(column, `列 '${column}' 在实体 '${this.entityName}' 中不存在`)
    }
    const condition = WhereCondition.isNotNull(resolvedColumn)
    condition.logicalOperator = LogicalOperator.AND
    this.conditions.push(condition)
    return this
  }

  /**
   * 添加 BETWEEN 条件
   * @param column 列名或属性名
   * @param min 最小值
   * @param max 最大值
   * @returns 当前实例（支持链式调用）
   */
  whereBetween(column: string, min: ValueType, max: ValueType): QueryBuilder {
    const resolvedColumn = this.getResolvedColumnName(column)
    if (resolvedColumn === null) {
      throw new InvalidConditionError(column, `列 '${column}' 在实体 '${this.entityName}' 中不存在`)
    }
    const condition = WhereCondition.between(resolvedColumn, min, max)
    condition.logicalOperator = LogicalOperator.AND
    this.conditions.push(condition)
    return this
  }

  /**
   * 添加 LIKE 条件
   * @param column 列名或属性名
   * @param pattern 匹配模式
   * @returns 当前实例（支持链式调用）
   */
  whereLike(column: string, pattern: string): QueryBuilder {
    const resolvedColumn = this.getResolvedColumnName(column)
    if (resolvedColumn === null) {
      throw new InvalidConditionError(column, `列 '${column}' 在实体 '${this.entityName}' 中不存在`)
    }
    const condition = WhereCondition.like(resolvedColumn, pattern)
    condition.logicalOperator = LogicalOperator.AND
    this.conditions.push(condition)
    return this
  }

  /**
   * 添加排序
   * @param column 列名或属性名
   * @param direction 排序方向
   * @returns 当前实例（支持链式调用）
   */
  orderBy(column: string, direction: SortDirection): QueryBuilder {
    const resolvedColumn = this.getResolvedColumnName(column)
    if (resolvedColumn === null) {
      throw new InvalidConditionError(column, `列 '${column}' 在实体 '${this.entityName}' 中不存在`)
    }
    const orderByClause = new OrderByClause(resolvedColumn, direction)
    this.orderByColumns.push(orderByClause)
    return this
  }

  /**
   * 设置 LIMIT
   * @param count 限制数量
   * @returns 当前实例（支持链式调用）
   */
  limit(count: number): QueryBuilder {
    if (count < 0) {
      throw new InvalidConditionError('LIMIT', 'LIMIT 值不能为负数')
    }
    this.limitValue = count
    return this
  }

  /**
   * 设置 OFFSET
   * @param count 偏移量
   * @returns 当前实例（支持链式调用）
   */
  offset(count: number): QueryBuilder {
    if (count < 0) {
      throw new InvalidConditionError('OFFSET', 'OFFSET 值不能为负数')
    }
    this.offsetValue = count
    return this
  }

  /**
   * 选择指定列
   * @param columns 列名或属性名数组
   * @returns 当前实例（支持链式调用）
   */
  select(columns: Array<string>): QueryBuilder {
    const resolvedColumns: Array<string> = []
    for (let i = 0; i < columns.length; i++) {
      const resolvedColumn = this.getResolvedColumnName(columns[i])
      if (resolvedColumn === null) {
        throw new InvalidConditionError(columns[i], `列 '${columns[i]}' 在实体 '${this.entityName}' 中不存在`)
      }
      resolvedColumns.push(resolvedColumn)
    }
    this.selectedColumns = resolvedColumns
    return this
  }

  /**
   * 验证列名是否有效
   * @param column 列名
   * @returns 是否有效
   */
  private isValidColumn(column: string): boolean {
    const columnMetadata = this.entityMetadata.getColumnByName(column)
    if (columnMetadata !== null) {
      return true
    }
    // 也尝试通过属性名查找
    const columnByProperty = this.entityMetadata.getColumnByProperty(column)
    return columnByProperty !== null
  }

  /**
   * 将属性名或列名解析为数据库列名
   * @param column 列名或属性名
   * @returns 数据库列名，未找到时返回 null
   */
  private getResolvedColumnName(column: string): string | null {
    const columnMetadata = this.entityMetadata.getColumnByName(column)
    if (columnMetadata !== null) {
      return columnMetadata.columnName
    }
    const columnByProperty = this.entityMetadata.getColumnByProperty(column)
    if (columnByProperty !== null) {
      return columnByProperty.columnName
    }
    return null
  }

  private ensureValidOperator(operator: ConditionOperator): void {
    if (!this.isSupportedConditionOperator(operator)) {
      throw new InvalidConditionError(String(operator), `不支持的操作符: ${String(operator)}`)
    }
  }

  private isSupportedConditionOperator(operator: ConditionOperator): boolean {
    switch (operator) {
      case ConditionOperator.EQUAL:
      case ConditionOperator.NOT_EQUAL:
      case ConditionOperator.GREATER:
      case ConditionOperator.LESS:
      case ConditionOperator.GREATER_EQUAL:
      case ConditionOperator.LESS_EQUAL:
      case ConditionOperator.LIKE:
      case ConditionOperator.IN:
      case ConditionOperator.NOT_IN:
      case ConditionOperator.BETWEEN:
      case ConditionOperator.IS_NULL:
      case ConditionOperator.IS_NOT_NULL:
        return true
      default:
        return false
    }
  }

  private validateAndNormalizeHavingClause(clause: string, args: Array<ValueType>): string {
    const normalized = clause.trim()
    if (normalized.length === 0) {
      throw new InvalidConditionError('HAVING', 'HAVING 条件不能为空')
    }
    this.ensureNoDangerousSqlTokens(normalized, 'HAVING')
    if (!/^[A-Za-z0-9_(),.*+\-/%<>=!\s?]+$/.test(normalized)) {
      throw new InvalidConditionError('HAVING', 'HAVING 子句包含非法字符')
    }
    if (args.length === 0) {
      throw new InvalidConditionError('HAVING', 'HAVING 必须使用参数占位符')
    }
    if (this.countPlaceholders(normalized) !== args.length) {
      throw new InvalidConditionError('HAVING', 'HAVING 占位符数量与参数数量不一致')
    }
    return normalized
  }

  private validateAndNormalizeSelectRawExpressions(expressions: Array<string>): Array<string> {
    if (expressions.length === 0) {
      throw new InvalidConditionError('selectRaw', 'selectRaw 表达式不能为空')
    }
    const normalized: Array<string> = []
    for (let i = 0; i < expressions.length; i++) {
      const expression = expressions[i].trim()
      if (expression.length === 0) {
        throw new InvalidConditionError('selectRaw', 'selectRaw 表达式不能为空字符串')
      }
      this.ensureNoDangerousSqlTokens(expression, 'selectRaw')
      if (!this.isSafeSelectRawExpression(expression)) {
        throw new InvalidConditionError('selectRaw', `不支持的 selectRaw 表达式: ${expression}`)
      }
      normalized.push(expression)
    }
    return normalized
  }

  private countPlaceholders(clause: string): number {
    return clause.split('?').length - 1
  }

  private ensureNoDangerousSqlTokens(value: string, fieldName: string): void {
    const hasDangerousToken = value.includes(';') ||
      value.includes('--') ||
      value.includes('/*') ||
      value.includes('*/') ||
      value.includes("'") ||
      value.includes('"') ||
      value.includes('`')
    if (hasDangerousToken) {
      throw new InvalidConditionError(fieldName, `${fieldName} 包含危险 SQL 片段`)
    }
  }

  private isSafeSelectRawExpression(expression: string): boolean {
    const identifierPattern = /^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)?$/
    if (identifierPattern.test(expression)) {
      return true
    }
    const aggregatePattern =
      /^(COUNT|SUM|AVG|MIN|MAX)\(\s*(\*|[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)?)\s*\)(\s+AS\s+[A-Za-z_][A-Za-z0-9_]*)?$/i
    return aggregatePattern.test(expression)
  }

  private normalizeRelationPath(relationPath: string): string {
    return relationPath.trim()
  }

  private splitRelationPathOrThrow(relationPath: string): Array<string> {
    const normalizedPath = this.normalizeRelationPath(relationPath)
    if (normalizedPath.length === 0) {
      throw new RelationNotFoundError(this.entityName, relationPath)
    }
    const segments = normalizedPath.split('.')
    for (let i = 0; i < segments.length; i++) {
      if (segments[i].trim().length === 0) {
        throw new RelationNotFoundError(this.entityName, relationPath)
      }
      segments[i] = segments[i].trim()
    }
    return segments
  }

  private resolveRelationPathTargetEntity(relationPath: string): string {
    const segments = this.splitRelationPathOrThrow(relationPath)
    let currentEntityName = this.entityName
    const metadataStorage = MetadataStorage.getInstance()
    for (let i = 0; i < segments.length; i++) {
      const relation = metadataStorage.getRelation(currentEntityName, segments[i])
      if (relation === null) {
        throw new RelationNotFoundError(currentEntityName, segments[i])
      }
      if (relation.targetEntity.length === 0) {
        // 动态目标实体（如 MorphTo）无法在构建阶段静态验证后续路径
        return ''
      }
      currentEntityName = relation.targetEntity
    }
    return currentEntityName
  }

  private createRelationQueryOptions(builder: QueryBuilder): RelationQueryOptions {
    const options = new RelationQueryOptions()
    const conditions = builder.getConditions()
    for (let i = 0; i < conditions.length; i++) {
      options.conditions.push(this.cloneCondition(conditions[i]))
    }
    const orderByColumns = builder.getOrderByColumns()
    for (let i = 0; i < orderByColumns.length; i++) {
      const item = orderByColumns[i]
      options.orderByColumns.push(new OrderByClause(item.column, item.direction))
    }
    options.limitValue = builder.getLimitValue()
    options.offsetValue = builder.getOffsetValue()
    options.includeDeleted = builder.isIncludeDeleted()
    options.onlyDeleted = builder.isOnlyDeleted()
    return options
  }

  /**
   * 指定需要加载的关联关系
   * @param relationName 关联属性名
   * @returns 当前实例（支持链式调用）
   * @throws RelationNotFoundError 如果关联关系未注册
   */
  with(relationName: string): QueryBuilder {
    const normalizedRelationPath = this.normalizeRelationPath(relationName)
    this.resolveRelationPathTargetEntity(normalizedRelationPath)

    // 避免重复添加
    if (!this.relationNames.includes(normalizedRelationPath)) {
      this.relationNames.push(normalizedRelationPath)
    }

    // 如果之前设置了延迟加载，移除以避免重复
    const lazyIndex = this.lazyRelationNames.indexOf(normalizedRelationPath)
    if (lazyIndex >= 0) {
      this.lazyRelationNames.splice(lazyIndex, 1)
    }

    return this
  }

  /**
   * 指定需要延迟加载的关联关系
   * @param relationName 关联属性名
   * @returns 当前实例（支持链式调用）
   * @throws RelationNotFoundError 如果关联关系未注册
   */
  withLazy(relationName: string): QueryBuilder {
    const normalizedRelationPath = this.normalizeRelationPath(relationName)
    const relation = MetadataStorage.getInstance().getRelation(this.entityName, normalizedRelationPath)
    if (relation === null) {
      throw new RelationNotFoundError(this.entityName, normalizedRelationPath)
    }

    if (!this.lazyRelationNames.includes(normalizedRelationPath) && !this.relationNames.includes(normalizedRelationPath)) {
      this.lazyRelationNames.push(normalizedRelationPath)
    }

    return this
  }

  /**
   * 关联条件过滤（预加载时应用条件）
   * @param relationName 关联路径，支持嵌套（如 posts.comments）
   * @param callback 过滤条件回调
   * @returns 当前实例（支持链式调用）
   */
  withWhere(relationName: string, callback: (qb: QueryBuilder) => void): QueryBuilder {
    const normalizedRelationPath = this.normalizeRelationPath(relationName)
    const targetEntityName = this.resolveRelationPathTargetEntity(normalizedRelationPath)
    if (targetEntityName.length === 0) {
      this.morphRelationQueryCallbacks.set(normalizedRelationPath, callback)
      this.relationQueryOptions.delete(normalizedRelationPath)
      return this.with(normalizedRelationPath)
    }
    const relationQueryBuilder = new QueryBuilder(targetEntityName)
    try {
      callback(relationQueryBuilder)
    } catch (e) {
      const errorMessage = e instanceof Error ? e.message : String(e)
      throw new InvalidConditionError('withWhere', `关联过滤回调执行失败: ${errorMessage}`)
    }
    this.morphRelationQueryCallbacks.delete(normalizedRelationPath)
    this.relationQueryOptions.set(normalizedRelationPath, this.createRelationQueryOptions(relationQueryBuilder))
    return this.with(normalizedRelationPath)
  }

  /**
   * 获取需要加载的关联关系名称列表
   * @returns 关联关系名称数组
   */
  getRelationNames(): Array<string> {
    return this.relationNames
  }

  /**
   * 获取关联过滤配置
   * @param relationPath 关联路径
   * @returns 过滤配置，不存在时返回 null
   */
  getRelationQueryOptions(relationPath: string): RelationQueryOptions | null {
    const options = this.relationQueryOptions.get(this.normalizeRelationPath(relationPath))
    if (options === undefined) {
      return null
    }
    return options.clone()
  }

  getMorphRelationQueryCallback(relationPath: string): ((qb: QueryBuilder) => void) | null {
    const callback = this.morphRelationQueryCallbacks.get(this.normalizeRelationPath(relationPath))
    if (callback === undefined) {
      return null
    }
    return callback
  }

  /**
   * 获取延迟加载的关联关系名称列表
   */
  getLazyRelationNames(): Array<string> {
    return this.lazyRelationNames
  }

  /**
   * 检查是否有需要加载的关联关系
   * @returns 是否有关联关系需要加载
   */
  hasRelations(): boolean {
    return this.relationNames.length > 0
  }

  /**
   * 检查是否有延迟加载的关联关系
   */
  hasLazyRelations(): boolean {
    return this.lazyRelationNames.length > 0
  }

  hasRelationQueryOptions(): boolean {
    return this.relationQueryOptions.size > 0
  }

  /**
   * 关联计数
   * @param relationPath 关联路径
   * @param alias 结果别名，默认 `${relationPath}_count`
   * @returns 当前实例（支持链式调用）
   */
  withCount(relationPath: string, alias: string = ''): QueryBuilder {
    const normalizedRelationPath = this.normalizeRelationPath(relationPath)
    this.resolveRelationPathTargetEntity(normalizedRelationPath)
    const resolvedAlias = alias.trim().length > 0 ? alias.trim() : `${normalizedRelationPath.replace(/\./g, '_')}_count`
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(resolvedAlias)) {
      throw new InvalidConditionError('withCount', `非法别名: ${resolvedAlias}`)
    }
    for (let i = 0; i < this.relationCountOptions.length; i++) {
      if (this.relationCountOptions[i].relationPath === normalizedRelationPath) {
        this.relationCountOptions[i].alias = resolvedAlias
        return this
      }
    }
    this.relationCountOptions.push(new RelationCountOption(normalizedRelationPath, resolvedAlias))
    return this
  }

  getRelationCountOptions(): Array<RelationCountOption> {
    return this.relationCountOptions.slice()
  }

  hasRelationCounts(): boolean {
    return this.relationCountOptions.length > 0
  }

  /**
   * 包含已删除的数据（软删除）
   * 调用此方法后，查询将不会自动过滤已删除的数据
   * @returns 当前实例（支持链式调用）
   */
  withDeleted(): QueryBuilder {
    this.includeDeleted = true
    this.onlyDeletedFlag = false
    return this
  }

  /**
   * 仅查询已删除的数据（软删除）
   * 调用此方法后，查询将只返回已删除的数据
   * @returns 当前实例（支持链式调用）
   */
  onlyDeleted(): QueryBuilder {
    this.onlyDeletedFlag = true
    this.includeDeleted = false
    return this
  }

  /**
   * 检查是否包含已删除的数据
   * @returns 是否包含已删除的数据
   */
  isIncludeDeleted(): boolean {
    return this.includeDeleted
  }

  /**
   * 检查是否仅查询已删除的数据
   * @returns 是否仅查询已删除的数据
   */
  isOnlyDeleted(): boolean {
    return this.onlyDeletedFlag
  }

  /**
   * 获取软删除相关的条件
   * 根据实体的软删除配置和查询设置，返回需要追加的软删除条件
   * @returns 软删除条件，如果不需要追加则返回 null
   */
  getSoftDeleteCondition(): WhereCondition | null {
    // 如果实体未启用软删除，不需要追加条件
    if (!this.entityMetadata.isSoftDeleteEnabled()) {
      return null
    }

    const deletedAtColumn = this.entityMetadata.getDeletedAtColumn()

    // 如果包含已删除的数据，不需要追加条件
    if (this.includeDeleted) {
      return null
    }

    // 如果仅查询已删除的数据，追加 IS NOT NULL 条件
    if (this.onlyDeletedFlag) {
      const condition = WhereCondition.isNotNull(deletedAtColumn)
      condition.logicalOperator = LogicalOperator.AND
      return condition
    }

    // 默认情况：排除已删除的数据，追加 IS NULL 条件
    const condition = WhereCondition.isNull(deletedAtColumn)
    condition.logicalOperator = LogicalOperator.AND
    return condition
  }

  /**
   * 获取所有条件（包括软删除条件）
   * @returns 包含软删除条件的完整条件数组
   */
  getAllConditions(): Array<WhereCondition> {
    const allConditions: Array<WhereCondition> = []

    // 添加用户定义的条件
    for (let i = 0; i < this.conditions.length; i++) {
      allConditions.push(this.cloneCondition(this.conditions[i]))
    }

    // 添加软删除条件（需要按 OR 分段追加）
    const softDeleteCondition = this.getSoftDeleteCondition()
    if (softDeleteCondition !== null) {
      if (allConditions.length === 0) {
        const softClone = this.cloneCondition(softDeleteCondition)
        softClone.logicalOperator = LogicalOperator.AND
        allConditions.push(softClone)
      } else {
        let hasOr = false
        for (let i = 1; i < allConditions.length; i++) {
          if (allConditions[i].logicalOperator === LogicalOperator.OR) {
            hasOr = true
            break
          }
        }

        if (!hasOr) {
          const softClone = this.cloneCondition(softDeleteCondition)
          softClone.logicalOperator = LogicalOperator.AND
          allConditions.push(softClone)
        } else {
          const expanded: Array<WhereCondition> = []
          for (let i = 0; i < allConditions.length; i++) {
            const condition = allConditions[i]
            if (i > 0 && condition.logicalOperator === LogicalOperator.OR) {
              const softClone = this.cloneCondition(softDeleteCondition)
              softClone.logicalOperator = LogicalOperator.AND
              expanded.push(softClone)
            }
            expanded.push(condition)
          }
          const tailSoftClone = this.cloneCondition(softDeleteCondition)
          tailSoftClone.logicalOperator = LogicalOperator.AND
          expanded.push(tailSoftClone)
          return expanded
        }
      }
    }

    return allConditions
  }

  /**
   * 设置分页参数
   * 自动计算 offset 值：offset = (page - 1) * size
   * @param page 页码（从 1 开始）
   * @param size 每页数量
   * @returns 当前实例（支持链式调用）
   */
  paginate(page: number, size: number): QueryBuilder {
    // 确保页码至少为 1
    this.pageNumber = page >= 1 ? page : 1
    // 确保每页数量至少为 1
    this.pageSizeValue = size >= 1 ? size : 20

    // 自动计算并设置 offset 和 limit
    this.offsetValue = (this.pageNumber - 1) * this.pageSizeValue
    this.limitValue = this.pageSizeValue

    return this
  }

  /**
   * 设置分页参数（paginate 的别名）
   * @param page 页码（从 1 开始）
   * @param size 每页数量
   * @returns 当前实例（支持链式调用）
   */
  forPage(page: number, size: number): QueryBuilder {
    return this.paginate(page, size)
  }

  /**
   * 设置查询超时（毫秒）
   * @param timeoutMs 超时时间，<= 0 表示禁用
   * @returns 当前实例（支持链式调用）
   */
  timeout(timeoutMs: number): QueryBuilder {
    this.queryTimeoutMs = timeoutMs > 0 ? Math.floor(timeoutMs) : 0
    return this
  }

  /**
   * 获取查询超时（毫秒）
   * @returns 超时时间，0 表示禁用
   */
  getQueryTimeoutMs(): number {
    return this.queryTimeoutMs
  }

  /**
   * 获取分页参数
   * @returns PaginationParams 实例，如果未设置分页则返回 null
   */
  getPaginationParams(): PaginationParams | null {
    if (this.pageNumber === 0 || this.pageSizeValue === 0) {
      return null
    }
    return new PaginationParams(this.pageNumber, this.pageSizeValue)
  }

  /**
   * 检查是否设置了分页
   * @returns 是否设置了分页
   */
  hasPagination(): boolean {
    return this.pageNumber > 0 && this.pageSizeValue > 0
  }

  /**
   * 批量更新（不加载实体）
   * @param values 需要更新的字段和值
   * @returns 受影响行数
   */
  async update(values: BatchUpdateValues): Promise<number> {
    const executor = new QueryExecutor(this)
    return await executor.update(values)
  }

  /**
   * 批量删除（不加载实体）
   * @returns 受影响行数
   */
  async delete(): Promise<number> {
    const executor = new QueryExecutor(this)
    return await executor.delete()
  }

  /**
   * 获取当前页码
   * @returns 页码（从 1 开始），未设置分页时返回 0
   */
  getPageNumber(): number {
    return this.pageNumber
  }

  /**
   * 获取每页数量
   * @returns 每页数量，未设置分页时返回 0
   */
  getPageSizeValue(): number {
    return this.pageSizeValue
  }

  /**
   * 重置查询构建器状态
   * @returns 当前实例（支持链式调用）
   */
  reset(): QueryBuilder {
    this.conditions = []
    this.orderByColumns = []
    this.limitValue = 0
    this.offsetValue = 0
    this.selectedColumns = []
    this.relationNames = []
    this.lazyRelationNames = []
    this.includeDeleted = false
    this.onlyDeletedFlag = false
    this.pageNumber = 0
    this.pageSizeValue = 0
    this.subQueries = []
    this.queryTimeoutMs = 0
    this.groupByColumns = []
    this.havingClause = ''
    this.havingArgs = []
    this.selectRawExpressions = []
    this.relationQueryOptions.clear()
    this.relationCountOptions = []
    return this
  }

  private cloneCondition(condition: WhereCondition): WhereCondition {
    const cloned = new WhereCondition()
    cloned.column = condition.column
    cloned.operator = condition.operator
    cloned.value = condition.value
    cloned.secondValue = condition.secondValue
    cloned.logicalOperator = condition.logicalOperator
    return cloned
  }

  /**
   * 基于关联实体存在性过滤（深层关联过滤）
   * 使用子查询过滤主实体，只返回满足关联条件的主实体
   * @param relationName 关联关系名称
   * @param callback 子查询回调函数，用于添加过滤条件
   * @returns 当前实例（支持链式调用）
   * @throws RelationNotFoundError 如果关联关系未注册
   * @throws SubQueryError 如果子查询构建失败
   */
  whereExists(relationName: string, callback: SubQueryCallback): QueryBuilder {
    // 验证关联关系是否存在
    const relation = MetadataStorage.getInstance().getRelation(this.entityName, relationName)
    if (relation === null) {
      throw new RelationNotFoundError(this.entityName, relationName)
    }

    // 创建子查询并调用回调函数添加条件
    const subQuery = new SubQuery(relationName)
    try {
      callback(subQuery)
    } catch (e) {
      const errorMessage = e instanceof Error ? e.message : String(e)
      throw new SubQueryError(`关联 '${relationName}' 的子查询回调执行失败: ${errorMessage}`)
    }

    // 添加到子查询列表
    this.subQueries.push(subQuery)

    return this
  }

  /**
   * 获取子查询列表
   * @returns 子查询数组
   */
  getSubQueries(): Array<SubQuery> {
    return this.subQueries
  }

  /**
   * 检查是否有子查询
   * @returns 是否有子查询
   */
  hasSubQueries(): boolean {
    return this.subQueries.length > 0
  }

  // ==================== GROUP BY 支持 ====================

  /**
   * 添加 GROUP BY 列
   * @param column 列名或属性名
   * @returns 当前实例（支持链式调用）
   */
  groupBy(column: string): QueryBuilder {
    const resolvedColumn = this.getResolvedColumnName(column)
    if (resolvedColumn === null) {
      throw new InvalidConditionError(column, `列 '${column}' 在实体 '${this.entityName}' 中不存在`)
    }
    if (!this.groupByColumns.includes(resolvedColumn)) {
      this.groupByColumns.push(resolvedColumn)
    }
    return this
  }

  /**
   * 添加多个 GROUP BY 列
   * @param columns 列名或属性名数组
   * @returns 当前实例（支持链式调用）
   */
  groupByMultiple(columns: Array<string>): QueryBuilder {
    for (let i = 0; i < columns.length; i++) {
      this.groupBy(columns[i])
    }
    return this
  }

  /**
   * 设置 HAVING 子句
   * @param clause HAVING 条件（使用 ? 作为占位符）
   * @param args 参数数组
   * @returns 当前实例（支持链式调用）
   */
  having(clause: string, args: Array<ValueType> = []): QueryBuilder {
    const normalizedClause = this.validateAndNormalizeHavingClause(clause, args)
    this.havingClause = normalizedClause
    this.havingArgs = args.slice()
    return this
  }

  /**
   * 设置原生 SELECT 表达式（用于聚合查询）
   * @param expressions 表达式数组，如 ['category', 'COUNT(*) as count', 'SUM(price) as total']
   * @returns 当前实例（支持链式调用）
   */
  selectRaw(expressions: Array<string>): QueryBuilder {
    this.selectRawExpressions = this.validateAndNormalizeSelectRawExpressions(expressions)
    return this
  }

  /**
   * 获取 GROUP BY 列
   * @returns GROUP BY 列数组
   */
  getGroupByColumns(): Array<string> {
    return this.groupByColumns
  }

  /**
   * 获取 HAVING 子句
   * @returns HAVING 子句
   */
  getHavingClause(): string {
    return this.havingClause
  }

  /**
   * 获取 HAVING 参数
   * @returns HAVING 参数数组
   */
  getHavingArgs(): Array<ValueType> {
    return this.havingArgs
  }

  /**
   * 获取原生 SELECT 表达式
   * @returns 表达式数组
   */
  getSelectRawExpressions(): Array<string> {
    return this.selectRawExpressions
  }

  /**
   * 检查是否有 GROUP BY
   * @returns 是否有 GROUP BY
   */
  hasGroupBy(): boolean {
    return this.groupByColumns.length > 0
  }

  /**
   * 检查是否有原生 SELECT 表达式
   * @returns 是否有原生 SELECT 表达式
   */
  hasSelectRaw(): boolean {
    return this.selectRawExpressions.length > 0
  }

  // ==================== 查询作用域 ====================

  /**
   * 应用查询作用域
   * @param scopeName 作用域名称
   * @returns 当前实例（支持链式调用）
   * @throws ScopeNotFoundError 如果作用域未注册
   */
  scope(scopeName: string): QueryBuilder {
    const scopeRegistry = ScopeRegistry.getInstance()
    if (!scopeRegistry.hasScope(this.entityName, scopeName)) {
      throw new ScopeNotFoundError(this.entityName, scopeName)
    }
    return scopeRegistry.applyScope(this.entityName, scopeName, this)
  }

  /**
   * 应用多个查询作用域
   * @param scopeNames 作用域名称数组
   * @returns 当前实例（支持链式调用）
   * @throws ScopeNotFoundError 如果任一作用域未注册
   */
  scopes(scopeNames: Array<string>): QueryBuilder {
    let result: QueryBuilder = this
    for (let i = 0; i < scopeNames.length; i++) {
      result = result.scope(scopeNames[i])
    }
    return result
  }

  /**
   * 获取查询描述（用于调试）
   * @returns 查询描述字符串
   */
  getQueryDescription(): string {
    const parts: Array<string> = []

    // SELECT 部分
    if (this.selectedColumns.length > 0) {
      parts.push('SELECT: ' + this.selectedColumns.join(', '))
    } else {
      parts.push('SELECT: *')
    }

    // FROM 部分
    parts.push('FROM: ' + this.entityMetadata.tableName)

    // WHERE 部分（包括软删除条件）
    const allConditions = this.getAllConditions()
    if (allConditions.length > 0) {
      const conditionStrs: Array<string> = []
      for (let i = 0; i < allConditions.length; i++) {
        const cond = allConditions[i]
        if (i > 0) {
          conditionStrs.push(cond.logicalOperator + ' ' + cond.toString())
        } else {
          conditionStrs.push(cond.toString())
        }
      }
      parts.push('WHERE: ' + conditionStrs.join(' '))
    }

    // ORDER BY 部分
    if (this.orderByColumns.length > 0) {
      const orderStrs: Array<string> = []
      for (let i = 0; i < this.orderByColumns.length; i++) {
        const order = this.orderByColumns[i]
        orderStrs.push(order.column + ' ' + order.direction)
      }
      parts.push('ORDER BY: ' + orderStrs.join(', '))
    }

    // 分页部分
    if (this.hasPagination()) {
      parts.push('PAGINATION: page=' + this.pageNumber.toString() + ', pageSize=' + this.pageSizeValue.toString())
    }

    // LIMIT 部分
    if (this.limitValue > 0) {
      parts.push('LIMIT: ' + this.limitValue.toString())
    }

    // OFFSET 部分
    if (this.offsetValue > 0) {
      parts.push('OFFSET: ' + this.offsetValue.toString())
    }

    // WITH 部分（关联关系）
    if (this.relationNames.length > 0) {
      parts.push('WITH: ' + this.relationNames.join(', '))
    }
    if (this.relationQueryOptions.size > 0) {
      const relationFilters: Array<string> = []
      this.relationQueryOptions.forEach((_, relationPath) => {
        relationFilters.push(relationPath)
      })
      parts.push('WITH_WHERE: ' + relationFilters.join(', '))
    }
    if (this.relationCountOptions.length > 0) {
      const relationCounts: Array<string> = []
      for (let i = 0; i < this.relationCountOptions.length; i++) {
        relationCounts.push(`${this.relationCountOptions[i].relationPath} AS ${this.relationCountOptions[i].alias}`)
      }
      parts.push('WITH_COUNT: ' + relationCounts.join(', '))
    }

    // 软删除状态
    if (this.entityMetadata.isSoftDeleteEnabled()) {
      if (this.includeDeleted) {
        parts.push('SOFT_DELETE: withDeleted')
      } else if (this.onlyDeletedFlag) {
        parts.push('SOFT_DELETE: onlyDeleted')
      } else {
        parts.push('SOFT_DELETE: excludeDeleted')
      }
    }

    // 子查询部分
    if (this.subQueries.length > 0) {
      const subQueryStrs: Array<string> = []
      for (let i = 0; i < this.subQueries.length; i++) {
        subQueryStrs.push(this.subQueries[i].getDescription())
      }
      parts.push('WHERE_EXISTS: ' + subQueryStrs.join('; '))
    }

    return parts.join('\n')
  }
}
