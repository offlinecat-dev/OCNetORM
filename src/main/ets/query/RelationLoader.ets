/**
 * 关联数据加载器
 * 负责执行关联数据的二次查询加载
 */

import { relationalStore } from '@kit.ArkData'
import { MetadataStorage } from '../core/MetadataStorage'
import { RelationMetadata } from '../core/RelationMetadata'
import { ManyToManyMetadata } from '../core/ManyToManyMetadata'
import { MorphToMetadata } from '../core/MorphToMetadata'
import { EntityMetadata } from '../core/EntityMetadata'
import { RelationType } from '../types/RelationType'
import { EntityData } from '../mapping/EntityData'
import { ResultSetRow } from '../mapping/ResultSetRow'
import { DatabaseManager } from '../database/DatabaseManager'
import { ValueType } from '../types/ValueTypes'
import { RelationNotFoundError } from '../errors/RelationError'
import { ExecutionError } from '../errors/DatabaseError'
import { OrmError } from '../errors/OrmError'
import { sanitizeErrorMessage } from '../errors/ErrorSanitizer'
import { ColumnType } from '../types/ColumnType'
import { Logger } from '../logging/Logger'
import { ResultSetUtils } from '../mapping/ResultSetUtils'
import { RelationLoadStrategy } from './RelationLoadStrategy'
import { OneToOneRelationLoadStrategy } from './OneToOneRelationLoadStrategy'
import { OneToManyRelationLoadStrategy } from './OneToManyRelationLoadStrategy'
import { ManyToOneRelationLoadStrategy } from './ManyToOneRelationLoadStrategy'
import { ManyToManyRelationLoadStrategy } from './ManyToManyRelationLoadStrategy'
import { RelationLoaderParallelSupport } from './RelationLoaderParallelSupport'
import { RelationLoaderCoreRelationSupport } from './RelationLoaderCoreRelationSupport'
import { RelationLoaderOneToOneSupport } from './RelationLoaderOneToOneSupport'
import { RelationLoaderManyToManySupport } from './RelationLoaderManyToManySupport'
import { RelationLoaderMorphToSupport } from './RelationLoaderMorphToSupport'
import { RelationQueryOptions } from './RelationQueryOptions'
import { QueryBuilder } from './QueryBuilder'
import { applyRelationQueryToPredicates as applyRelationQueryToPredicatesUtil } from './RelationPredicateUtils'

type AsyncFailure = Error | object | string | number | boolean | null | undefined

/**
 * 关联数据加载器类
 * 使用应用层二次查询策略加载关联数据
 */
export class RelationLoader {
  /** 源实体名称 */
  private sourceEntityName: string
  /** 关系加载策略映射 */
  private relationStrategies: Map<RelationType, RelationLoadStrategy>
  /** 并行加载支持 */
  private parallelSupport: RelationLoaderParallelSupport
  /** 关系核心加载支持（ONE_TO_MANY/MANY_TO_ONE） */
  private coreRelationSupport: RelationLoaderCoreRelationSupport
  /** ONE_TO_ONE 关系加载支持 */
  private oneToOneSupport: RelationLoaderOneToOneSupport
  /** MANY_TO_MANY 关系加载支持 */
  private manyToManySupport: RelationLoaderManyToManySupport
  /** MORPH_TO 关系加载支持 */
  private morphToSupport: RelationLoaderMorphToSupport
  /** 可选的 Store 提供者（用于复用外部租约连接） */
  private storeProvider: (() => relationalStore.RdbStore) | null

  /** IN 条件参数数量限制默认值 */
  private static readonly DEFAULT_IN_CLAUSE_LIMIT: number = 500
  /** IN 条件参数数量限制（可配置） */
  private static inClauseLimit: number = RelationLoader.DEFAULT_IN_CLAUSE_LIMIT

  /**
   * 构造函数
   * @param sourceEntityName 源实体名称
   */
  constructor(sourceEntityName: string, storeProvider?: () => relationalStore.RdbStore) {
    this.sourceEntityName = sourceEntityName
    this.relationStrategies = new Map<RelationType, RelationLoadStrategy>()
    this.storeProvider = storeProvider ? storeProvider : null
    this.relationStrategies.set(
      RelationType.ONE_TO_ONE,
      new OneToOneRelationLoadStrategy(async (
        entities: Array<EntityData>,
        relation: RelationMetadata
      ): Promise<Array<EntityData>> => await this.loadOneToOne(entities, relation))
    )
    this.relationStrategies.set(
      RelationType.ONE_TO_MANY,
      new OneToManyRelationLoadStrategy(async (
        entities: Array<EntityData>,
        relation: RelationMetadata
      ): Promise<Array<EntityData>> => await this.loadOneToMany(entities, relation))
    )
    this.relationStrategies.set(
      RelationType.MANY_TO_ONE,
      new ManyToOneRelationLoadStrategy(async (
        entities: Array<EntityData>,
        relation: RelationMetadata
      ): Promise<Array<EntityData>> => await this.loadManyToOne(entities, relation))
    )
    this.relationStrategies.set(
      RelationType.MANY_TO_MANY,
      new ManyToManyRelationLoadStrategy(async (
        entities: Array<EntityData>,
        relation: ManyToManyMetadata
      ): Promise<Array<EntityData>> => await this.loadManyToMany(entities, relation))
    )
    this.parallelSupport = new RelationLoaderParallelSupport(
      this.sourceEntityName,
      async (entities: Array<EntityData>, relationName: string): Promise<Array<EntityData>> =>
        await this.loadRelation(entities, relationName),
      (error: AsyncFailure): string => this.resolveErrorMessage(error),
      (context: string, message: string): void => this.logRelationWarnMessage(context, message)
    )
    this.coreRelationSupport = new RelationLoaderCoreRelationSupport(
      this.sourceEntityName,
      (): relationalStore.RdbStore => this.getStore(),
      (): number => this.resolveInClauseLimit(),
      (
        predicates: relationalStore.RdbPredicates,
        metadata: EntityMetadata,
        options: RelationQueryOptions | null
      ): void => this.applyRelationQueryToPredicates(predicates, metadata, options),
      (value: ValueType | Array<ValueType> | null): relationalStore.ValueType => this.toRdbValue(value),
      async (
        task: Promise<relationalStore.ResultSet>,
        operation: string
      ): Promise<relationalStore.ResultSet> => await this.withQueryTimeout(task, operation),
      (resultSet: relationalStore.ResultSet, metadata: EntityMetadata): ResultSetRow =>
        this.resultSetToRow(resultSet, metadata),
      (resultSet: relationalStore.ResultSet | null): void => this.closeResultSet(resultSet),
      (context: string, error: AsyncFailure): void => this.logRelationWarn(context, error),
      (items: Array<EntityData>, options: RelationQueryOptions | null): Array<EntityData> =>
        this.applyCollectionQueryOptions(items, options)
    )
    this.oneToOneSupport = new RelationLoaderOneToOneSupport(
      this.sourceEntityName,
      (): relationalStore.RdbStore => this.getStore(),
      (): number => this.resolveInClauseLimit(),
      (
        predicates: relationalStore.RdbPredicates,
        metadata: EntityMetadata,
        options: RelationQueryOptions | null
      ): void => this.applyRelationQueryToPredicates(predicates, metadata, options),
      (value: ValueType | Array<ValueType> | null): relationalStore.ValueType => this.toRdbValue(value),
      async (
        task: Promise<relationalStore.ResultSet>,
        operation: string
      ): Promise<relationalStore.ResultSet> => await this.withQueryTimeout(task, operation),
      (resultSet: relationalStore.ResultSet, metadata: EntityMetadata): ResultSetRow =>
        this.resultSetToRow(resultSet, metadata),
      (resultSet: relationalStore.ResultSet | null): void => this.closeResultSet(resultSet),
      (context: string, error: AsyncFailure): void => this.logRelationWarn(context, error)
    )
    this.manyToManySupport = new RelationLoaderManyToManySupport(
      this.sourceEntityName,
      (): relationalStore.RdbStore => this.getStore(),
      (): number => this.resolveInClauseLimit(),
      async (
        task: Promise<relationalStore.ResultSet>,
        operation: string
      ): Promise<relationalStore.ResultSet> => await this.withQueryTimeout(task, operation),
      (resultSet: relationalStore.ResultSet | null): void => this.closeResultSet(resultSet),
      (context: string, error: AsyncFailure): void => this.logRelationWarn(context, error),
      (
        predicates: relationalStore.RdbPredicates,
        metadata: EntityMetadata,
        options: RelationQueryOptions | null
      ): void => this.applyRelationQueryToPredicates(predicates, metadata, options),
      (value: ValueType | Array<ValueType> | null): relationalStore.ValueType => this.toRdbValue(value),
      (resultSet: relationalStore.ResultSet, metadata: EntityMetadata): ResultSetRow =>
        this.resultSetToRow(resultSet, metadata),
      (items: Array<EntityData>, options: RelationQueryOptions | null): Array<EntityData> =>
        this.applyCollectionQueryOptions(items, options)
    )
    this.morphToSupport = new RelationLoaderMorphToSupport(
      this.sourceEntityName,
      (): relationalStore.RdbStore => this.getStore(),
      (): number => this.resolveInClauseLimit(),
      async (
        task: Promise<relationalStore.ResultSet>,
        operation: string
      ): Promise<relationalStore.ResultSet> => await this.withQueryTimeout(task, operation),
      (resultSet: relationalStore.ResultSet | null): void => this.closeResultSet(resultSet),
      (context: string, error: AsyncFailure): void => this.logRelationWarn(context, error),
      (
        predicates: relationalStore.RdbPredicates,
        metadata: EntityMetadata,
        options: RelationQueryOptions | null
      ): void => this.applyRelationQueryToPredicates(predicates, metadata, options),
      (value: ValueType | Array<ValueType> | null): relationalStore.ValueType => this.toRdbValue(value),
      (resultSet: relationalStore.ResultSet, metadata: EntityMetadata): ResultSetRow =>
        this.resultSetToRow(resultSet, metadata)
    )
  }

  static setInClauseLimit(limit: number): void {
    RelationLoader.inClauseLimit = RelationLoader.normalizeInClauseLimit(limit)
  }

  static getInClauseLimit(): number {
    return RelationLoader.inClauseLimit
  }

  static resetInClauseLimit(): void {
    RelationLoader.inClauseLimit = RelationLoader.DEFAULT_IN_CLAUSE_LIMIT
  }

  private static normalizeInClauseLimit(limit: number): number {
    if (limit < 1) {
      return 1
    }
    return Math.floor(limit)
  }

  private async withQueryTimeout(
    task: Promise<relationalStore.ResultSet>,
    operation: string
  ): Promise<relationalStore.ResultSet> {
    const timeoutMs = DatabaseManager.getInstance().getQueryTimeoutMs()
    if (timeoutMs <= 0) {
      return await task
    }
    return await new Promise<relationalStore.ResultSet>((resolve, reject) => {
      const timerId = setTimeout(() => {
        reject(new Error(`${operation} 查询超时 (${timeoutMs}ms)`))
      }, timeoutMs)
      task.then((result) => {
        clearTimeout(timerId)
        resolve(result)
      }).catch((error: AsyncFailure) => {
        clearTimeout(timerId)
        reject(error)
      })
    })
  }

  private resolveInClauseLimit(): number {
    const config = DatabaseManager.getInstance().getConfig()
    if (config !== null && config.relationInClauseLimit > 0) {
      return config.relationInClauseLimit
    }
    return RelationLoader.inClauseLimit
  }

  /**
   * 获取 RdbStore 实例
   * @returns RdbStore 实例
   * @throws ExecutionError 如果数据库未初始化
   */
  private getStore(): relationalStore.RdbStore {
    if (this.storeProvider !== null) {
      try {
        return this.storeProvider()
      } catch (e) {
        if (e instanceof ExecutionError) {
          throw e
        }
        const errorMessage = e instanceof Error ? e.message : String(e)
        throw new ExecutionError('DATABASE', errorMessage)
      }
    }
    try {
      return DatabaseManager.getInstance().getStore()
    } catch (e) {
      const errorMessage = e instanceof Error ? e.message : String(e)
      throw new ExecutionError('DATABASE', errorMessage)
    }
  }

  private closeResultSet(resultSet: relationalStore.ResultSet | null): void {
    if (resultSet === null) {
      return
    }
    try {
      resultSet.close()
    } catch (e) {
      // ignore
    }
  }

  private resolveErrorMessage(error: AsyncFailure): string {
    if (error instanceof OrmError) {
      return sanitizeErrorMessage(error.getFullMessage())
    }
    if (error instanceof Error) {
      return sanitizeErrorMessage(error.message)
    }
    return sanitizeErrorMessage(String(error))
  }

  private logRelationWarn(context: string, error: AsyncFailure): void {
    Logger.getInstance().logWarn(`${context}: ${this.resolveErrorMessage(error)}`)
  }

  private logRelationWarnMessage(context: string, message: string): void {
    Logger.getInstance().logWarn(`${context}: ${sanitizeErrorMessage(message)}`)
  }

  private getRelationStrategy(relationType: RelationType): RelationLoadStrategy | null {
    const strategy = this.relationStrategies.get(relationType)
    if (strategy === undefined) {
      return null
    }
    return strategy
  }

  /**
   * 加载关联数据
   * @param entities 主实体数据数组
   * @param relationName 关联属性名
   * @returns 带有关联数据的实体数组
   * @throws RelationNotFoundError 如果关联关系未注册
   */
  async loadRelation(
    entities: Array<EntityData>,
    relationName: string,
    options: RelationQueryOptions | null = null,
    morphWithWhereCallback: ((qb: QueryBuilder) => void) | null = null
  ): Promise<Array<EntityData>> {
    if (entities.length === 0) {
      return entities
    }

    // 获取关联关系元数据
    const relation = MetadataStorage.getInstance().getRelation(this.sourceEntityName, relationName)
    if (relation === null) {
      throw new RelationNotFoundError(this.sourceEntityName, relationName)
    }

    const strategy = this.getRelationStrategy(relation.type)
    if (strategy !== null && options === null) {
      return await strategy.load(entities, relation)
    }

    if (relation.type === RelationType.ONE_TO_ONE) {
      return await this.loadOneToOne(entities, relation, options)
    }
    if (relation.type === RelationType.ONE_TO_MANY) {
      return await this.loadOneToMany(entities, relation, options)
    }
    if (relation.type === RelationType.MANY_TO_ONE) {
      return await this.loadManyToOne(entities, relation, options)
    }
    if (relation.type === RelationType.MANY_TO_MANY) {
      return await this.loadManyToMany(entities, relation as ManyToManyMetadata, options)
    }
    if (relation.type === RelationType.MORPH_TO) {
      return await this.loadMorphTo(entities, relation as MorphToMetadata, options, morphWithWhereCallback)
    }

    return entities
  }

  /**
   * 并行加载多个关联数据
   * 使用 Promise.all 并行执行多个关联的加载
   * @param entities 主实体数据数组
   * @param relationNames 关联属性名数组
   * @returns 带有所有关联数据的实体数组
   */
  async loadRelationsParallel(
    entities: Array<EntityData>,
    relationNames: Array<string>
  ): Promise<Array<EntityData>> {
    return await this.parallelSupport.loadRelationsParallel(entities, relationNames)
  }

  /**
   * 加载 ONE_TO_MANY 关联数据
   * 根据主实体的主键值查询关联实体列表
   * @param entities 主实体数据数组
   * @param relation 关联关系元数据
   * @returns 带有关联数据的实体数组
   */
  private async loadOneToMany(
    entities: Array<EntityData>,
    relation: RelationMetadata,
    options: RelationQueryOptions | null = null
  ): Promise<Array<EntityData>> {
    return await this.coreRelationSupport.loadOneToMany(entities, relation, options)
  }

  /**
   * 加载 MANY_TO_ONE 关联数据
   * 根据外键值查询单个关联实体
   * @param entities 主实体数据数组
   * @param relation 关联关系元数据
   * @returns 带有关联数据的实体数组
   */
  private async loadManyToOne(
    entities: Array<EntityData>,
    relation: RelationMetadata,
    options: RelationQueryOptions | null = null
  ): Promise<Array<EntityData>> {
    return await this.coreRelationSupport.loadManyToOne(entities, relation, options)
  }

  /**
   * 加载 ONE_TO_ONE 关联数据
   * 根据 foreignKeySide 配置选择加载策略：
   * - 'source': 外键在源实体，根据源实体的外键值查询目标实体
   * - 'target': 外键在目标实体，根据目标实体的外键值查询源实体
   * @param entities 主实体数据数组
   * @param relation 关联关系元数据
   * @returns 带有关联数据的实体数组
   */
  private async loadOneToOne(
    entities: Array<EntityData>,
    relation: RelationMetadata,
    options: RelationQueryOptions | null = null
  ): Promise<Array<EntityData>> {
    // 根据 foreignKeySide 选择加载策略
    if (relation.foreignKeySide === 'target') {
      return await this.loadOneToOneTargetSide(entities, relation, options)
    } else {
      // 默认 'source'：外键在源实体
      return await this.loadOneToOneSourceSide(entities, relation, options)
    }
  }

  /**
   * 加载 ONE_TO_ONE 关联数据（外键在源实体侧）
   * 根据源实体的外键值查询目标实体
   * @param entities 主实体数据数组
   * @param relation 关联关系元数据
   * @returns 带有关联数据的实体数组
   */
  private async loadOneToOneSourceSide(
    entities: Array<EntityData>,
    relation: RelationMetadata,
    options: RelationQueryOptions | null = null
  ): Promise<Array<EntityData>> {
    return await this.oneToOneSupport.loadOneToOneSourceSide(entities, relation, options)
  }

  /**
   * 加载 ONE_TO_ONE 关联数据（外键在目标实体侧）
   * 根据目标实体的外键值查询源实体
   * @param entities 主实体数据数组
   * @param relation 关联关系元数据
   * @returns 带有关联数据的实体数组
   */
  private async loadOneToOneTargetSide(
    entities: Array<EntityData>,
    relation: RelationMetadata,
    options: RelationQueryOptions | null = null
  ): Promise<Array<EntityData>> {
    return await this.oneToOneSupport.loadOneToOneTargetSide(entities, relation, options)
  }

  /**
   * 加载 MANY_TO_MANY 关联数据
   * 使用两次查询策略：
   * 1. 先查询中间表获取目标实体 ID 列表
   * 2. 再根据 ID 列表查询目标实体数据
   * @param entities 主实体数据数组
   * @param relation 多对多关联关系元数据
   * @returns 带有关联数据的实体数组
   */
  private async loadManyToMany(
    entities: Array<EntityData>,
    relation: ManyToManyMetadata,
    options: RelationQueryOptions | null = null
  ): Promise<Array<EntityData>> {
    return await this.manyToManySupport.loadManyToMany(entities, relation, options)
  }

  private async loadMorphTo(
    entities: Array<EntityData>,
    relation: MorphToMetadata,
    options: RelationQueryOptions | null = null,
    morphWithWhereCallback: ((qb: QueryBuilder) => void) | null = null
  ): Promise<Array<EntityData>> {
    return await this.morphToSupport.loadMorphTo(entities, relation, options, morphWithWhereCallback)
  }

  private applyCollectionQueryOptions(
    entities: Array<EntityData>,
    options: RelationQueryOptions | null
  ): Array<EntityData> {
    if (options === null) {
      return entities
    }
    const safeOffset = options.offsetValue > 0 ? options.offsetValue : 0
    if (safeOffset >= entities.length) {
      return []
    }
    if (options.limitValue > 0) {
      return entities.slice(safeOffset, safeOffset + options.limitValue)
    }
    if (safeOffset > 0) {
      return entities.slice(safeOffset)
    }
    return entities
  }

  private applyRelationQueryToPredicates(
    predicates: relationalStore.RdbPredicates,
    metadata: EntityMetadata,
    options: RelationQueryOptions | null
  ): void {
    applyRelationQueryToPredicatesUtil(
      predicates,
      metadata,
      options,
      (value: ValueType | Array<ValueType> | null): relationalStore.ValueType => this.toRdbValue(value)
    )
  }

  /**
   * 将 ValueType 转换为 RdbPredicates 支持的值类型
   */
  private toRdbValue(value: ValueType | Array<ValueType> | null): relationalStore.ValueType {
    if (value === null) {
      return null
    }
    if (Array.isArray(value)) {
      return null
    }
    if (typeof value === 'boolean') {
      return value ? 1 : 0
    }
    if (value instanceof Date) {
      return value.getTime()
    }
    if (value instanceof Uint8Array) {
      return value
    }
    if (typeof value === 'object') {
      try {
        return JSON.stringify(value as object)
      } catch (e) {
        return null
      }
    }
    if (typeof value === 'string' || typeof value === 'number') {
      return value
    }
    return null
  }

  /**
   * 将 ResultSet 当前行转换为 ResultSetRow
   */
  private resultSetToRow(resultSet: relationalStore.ResultSet, metadata: EntityMetadata): ResultSetRow {
    const row = new ResultSetRow()
    const columnNames = resultSet.columnNames

    for (let i = 0; i < columnNames.length; i++) {
      const columnName = columnNames[i]
      try {
        const columnIndex = resultSet.getColumnIndex(columnName)

        if (resultSet.isColumnNull(columnIndex)) {
          row.set(columnName, null)
        } else {
          const columnMetadata = metadata.getColumnByName(columnName)
          if (columnMetadata !== null) {
            switch (columnMetadata.columnType) {
              case ColumnType.INTEGER:
                row.set(columnName, resultSet.getLong(columnIndex))
                break
              case ColumnType.REAL:
                row.set(columnName, resultSet.getDouble(columnIndex))
                break
              case ColumnType.TEXT:
                row.set(columnName, resultSet.getString(columnIndex))
                break
              case ColumnType.BLOB:
                row.set(columnName, resultSet.getBlob(columnIndex))
                break
              default:
                row.set(columnName, resultSet.getString(columnIndex))
            }
          } else {
            row.set(columnName, resultSet.getString(columnIndex))
          }
        }
      } catch (e) {
        row.set(columnName, null)
      }
    }

    return row
  }
}
