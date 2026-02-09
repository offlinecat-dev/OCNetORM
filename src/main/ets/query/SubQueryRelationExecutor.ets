import { relationalStore } from '@kit.ArkData'
import { SubQuery } from './SubQuery'
import { Logger } from '../logging/Logger'
import { MetadataStorage } from '../core/MetadataStorage'
import { EntityMetadata } from '../core/EntityMetadata'
import { ManyToManyMetadata } from '../core/ManyToManyMetadata'
import { RelationType } from '../types/RelationType'
import { ValueType } from '../types/ValueTypes'
import { ConditionOperator } from '../types/ConditionOperator'
import { WhereCondition, LogicalOperator } from './WhereCondition'
import { ResultSetUtils } from '../mapping/ResultSetUtils'

export interface SubQueryRelationExecutorOptions {
  logger: Logger
  withQueryTimeout: (
    task: Promise<relationalStore.ResultSet>,
    operation: string
  ) => Promise<relationalStore.ResultSet>
  closeResultSet: (resultSet: relationalStore.ResultSet | null) => void
  toRdbValue: (value: ValueType | Array<ValueType> | null) => relationalStore.ValueType
}

export class SubQueryRelationExecutor {
  private options: SubQueryRelationExecutorOptions

  constructor(options: SubQueryRelationExecutorOptions) {
    this.options = options
  }

  async executeOneSubQuery(
    subQuery: SubQuery,
    store: relationalStore.RdbStore,
    entityName: string,
    sourcePkColumn: string
  ): Promise<Array<ValueType>> {
    const relationName = subQuery.getRelationName()
    const metadata = MetadataStorage.getInstance()

    // 获取关联关系元数据
    const relation = metadata.getRelation(entityName, relationName)
    if (relation === null) {
      this.options.logger.logError(`子查询关联 '${relationName}' 未找到`)
      return []
    }

    // 获取目标实体元数据
    const targetMetadata = metadata.getEntityMetadata(relation.targetEntity)
    if (targetMetadata === null) {
      this.options.logger.logError(`子查询目标实体 '${relation.targetEntity}' 未找到`)
      return []
    }

    // 根据关系类型执行不同的子查询策略
    if (relation.type === RelationType.MANY_TO_MANY) {
      return await this.executeSubQueryManyToMany(
        subQuery,
        store,
        relation as ManyToManyMetadata,
        targetMetadata.tableName
      )
    } else if (relation.type === RelationType.ONE_TO_MANY) {
      // ONE_TO_MANY: 查询目标表，返回 inverseKey 值作为源实体 ID
      return await this.executeSubQueryOneToMany(
        subQuery,
        store,
        relation.inverseKey,
        targetMetadata.tableName,
        relation.targetEntity
      )
    } else if (relation.type === RelationType.MANY_TO_ONE) {
      // MANY_TO_ONE: 查询目标表，获取目标实体主键，然后返回匹配的源实体
      return await this.executeSubQueryManyToOne(
        subQuery,
        store,
        entityName,
        relation.inverseKey,
        relation.targetEntity,
        sourcePkColumn
      )
    } else if (relation.type === RelationType.ONE_TO_ONE) {
      // ONE_TO_ONE: 根据 foreignKeySide 选择策略
      if (relation.foreignKeySide === 'target') {
        return await this.executeSubQueryOneToMany(
          subQuery,
          store,
          relation.inverseKey,
          targetMetadata.tableName,
          relation.targetEntity
        )
      } else {
        return await this.executeSubQueryManyToOne(
          subQuery,
          store,
          entityName,
          relation.inverseKey,
          relation.targetEntity,
          sourcePkColumn
        )
      }
    }

    return []
  }

  /**
   * 执行 ONE_TO_MANY 关系的子查询
   * 查询目标表，返回符合条件的记录的外键值（即源实体 ID）
   */
  private async executeSubQueryOneToMany(
    subQuery: SubQuery,
    store: relationalStore.RdbStore,
    inverseKey: string,
    targetTableName: string,
    targetEntityName: string
  ): Promise<Array<ValueType>> {
    const targetMetadata = MetadataStorage.getInstance().getEntityMetadata(targetEntityName)
    if (targetMetadata === null) {
      return []
    }
    const predicates = new relationalStore.RdbPredicates(targetTableName)
    this.applySoftDeleteToPredicates(predicates, targetMetadata)

    // 应用子查询条件
    const conditions = subQuery.getConditions()
    for (let i = 0; i < conditions.length; i++) {
      const cond = conditions[i]
      if (i > 0) {
        if (cond.logicalOperator === LogicalOperator.OR) {
          predicates.or()
        } else {
          predicates.and()
        }
      }
      if (!this.applyConditionToPredicates(predicates, cond, targetMetadata, targetEntityName)) {
        return []
      }
    }

    // 执行查询，只获取外键列
    let resultSet: relationalStore.ResultSet | null = null
    try {
      resultSet = await this.options.withQueryTimeout(store.query(predicates, [inverseKey]), 'SUBQUERY')
    } catch (e) {
      this.options.logger.logError(`子查询执行失败: ${e instanceof Error ? e.message : String(e)}`)
      return []
    }

    // 收集源实体 ID（去重）
    const sourceIds: Set<string> = new Set()
    try {
      while (resultSet !== null && resultSet.goToNextRow()) {
        const columnIndex = resultSet.getColumnIndex(inverseKey)
        if (!resultSet.isColumnNull(columnIndex)) {
          const fkValue = ResultSetUtils.getValueByRuntimeType(resultSet, columnIndex)
          if (fkValue !== null) {
            sourceIds.add(String(fkValue))
          }
        }
      }
    } catch (e) {
      // 忽略遍历错误
    } finally {
      this.options.closeResultSet(resultSet)
    }

    // 转换为数组
    const result: Array<ValueType> = []
    sourceIds.forEach((idStr: string) => {
      const numId = Number(idStr)
      if (!isNaN(numId)) {
        result.push(numId)
      } else {
        result.push(idStr)
      }
    })

    return result
  }

  /**
   * 执行 MANY_TO_ONE 关系的子查询
   * 先查询目标表获取符合条件的目标实体主键，再查询源表获取匹配的源实体 ID
   */
  private async executeSubQueryManyToOne(
    subQuery: SubQuery,
    store: relationalStore.RdbStore,
    sourceEntityName: string,
    inverseKey: string,
    targetEntityName: string,
    sourcePkColumn: string
  ): Promise<Array<ValueType>> {
    // 获取目标实体元数据
    const metadata = MetadataStorage.getInstance()
    const targetEntityMetadata = metadata.getEntityMetadata(targetEntityName)
    if (targetEntityMetadata === null) {
      return []
    }

    const targetPkColumn = targetEntityMetadata.getPrimaryKeyColumn()
    if (targetPkColumn === null) {
      return []
    }

    // 第一步：查询目标表，获取符合条件的目标实体主键
    const targetPredicates = new relationalStore.RdbPredicates(targetEntityMetadata.tableName)
    this.applySoftDeleteToPredicates(targetPredicates, targetEntityMetadata)

    const conditions = subQuery.getConditions()
    for (let i = 0; i < conditions.length; i++) {
      const cond = conditions[i]
      if (i > 0) {
        if (cond.logicalOperator === LogicalOperator.OR) {
          targetPredicates.or()
        } else {
          targetPredicates.and()
        }
      }
      if (!this.applyConditionToPredicates(targetPredicates, cond, targetEntityMetadata, targetEntityName)) {
        return []
      }
    }

    let targetResultSet: relationalStore.ResultSet | null = null
    try {
      targetResultSet = await this.options.withQueryTimeout(store.query(targetPredicates, [targetPkColumn.columnName]), 'SUBQUERY')
    } catch (e) {
      this.options.logger.logError(`子查询目标表查询失败: ${e instanceof Error ? e.message : String(e)}`)
      return []
    }

    // 收集目标实体主键
    const targetPkValues: Array<relationalStore.ValueType> = []
    try {
      while (targetResultSet !== null && targetResultSet.goToNextRow()) {
        const columnIndex = targetResultSet.getColumnIndex(targetPkColumn.columnName)
        if (!targetResultSet.isColumnNull(columnIndex)) {
          const pkValue = ResultSetUtils.getValueByRuntimeType(targetResultSet, columnIndex)
          if (pkValue !== null) {
            targetPkValues.push(pkValue as relationalStore.ValueType)
          }
        }
      }
    } catch (e) {
      // 忽略遍历错误
    } finally {
      this.options.closeResultSet(targetResultSet)
    }

    if (targetPkValues.length === 0) {
      return []
    }

    // 第二步：查询源表，获取外键在目标主键列表中的源实体 ID
    const sourceMetadata = metadata.getEntityMetadata(sourceEntityName)
    if (sourceMetadata === null) {
      return []
    }

    const sourcePredicates = new relationalStore.RdbPredicates(sourceMetadata.tableName)
    this.applySoftDeleteToPredicates(sourcePredicates, sourceMetadata)
    sourcePredicates.in(inverseKey, targetPkValues)

    let sourceResultSet: relationalStore.ResultSet | null = null
    try {
      sourceResultSet = await this.options.withQueryTimeout(store.query(sourcePredicates, [sourcePkColumn]), 'SUBQUERY')
    } catch (e) {
      this.options.logger.logError(`子查询源表查询失败: ${e instanceof Error ? e.message : String(e)}`)
      return []
    }

    // 收集源实体 ID
    const sourceIds: Array<ValueType> = []
    try {
      while (sourceResultSet !== null && sourceResultSet.goToNextRow()) {
        const columnIndex = sourceResultSet.getColumnIndex(sourcePkColumn)
        if (!sourceResultSet.isColumnNull(columnIndex)) {
          const pkValue = ResultSetUtils.getValueByRuntimeType(sourceResultSet, columnIndex)
          if (pkValue !== null) {
            sourceIds.push(pkValue as ValueType)
          }
        }
      }
    } catch (e) {
      // 忽略遍历错误
    } finally {
      this.options.closeResultSet(sourceResultSet)
    }

    return sourceIds
  }

  /**
   * 执行 MANY_TO_MANY 关系的子查询
   * 先查询目标表获取符合条件的目标实体主键，再查询中间表获取关联的源实体 ID
   */
  private async executeSubQueryManyToMany(
    subQuery: SubQuery,
    store: relationalStore.RdbStore,
    relation: ManyToManyMetadata,
    targetTableName: string
  ): Promise<Array<ValueType>> {
    // 获取目标实体元数据
    const metadata = MetadataStorage.getInstance()
    const targetEntityMetadata = metadata.getEntityMetadata(relation.targetEntity)
    if (targetEntityMetadata === null) {
      return []
    }

    const targetPkColumn = targetEntityMetadata.getPrimaryKeyColumn()
    if (targetPkColumn === null) {
      return []
    }

    // 第一步：查询目标表，获取符合条件的目标实体主键
    const targetPredicates = new relationalStore.RdbPredicates(targetTableName)
    this.applySoftDeleteToPredicates(targetPredicates, targetEntityMetadata)

    const conditions = subQuery.getConditions()
    for (let i = 0; i < conditions.length; i++) {
      const cond = conditions[i]
      if (i > 0) {
        if (cond.logicalOperator === LogicalOperator.OR) {
          targetPredicates.or()
        } else {
          targetPredicates.and()
        }
      }
      if (!this.applyConditionToPredicates(targetPredicates, cond, targetEntityMetadata, relation.targetEntity)) {
        return []
      }
    }

    let targetResultSet: relationalStore.ResultSet | null = null
    try {
      targetResultSet = await this.options.withQueryTimeout(store.query(targetPredicates, [targetPkColumn.columnName]), 'SUBQUERY')
    } catch (e) {
      this.options.logger.logError(`子查询目标表查询失败: ${e instanceof Error ? e.message : String(e)}`)
      return []
    }

    // 收集目标实体主键
    const targetPkValues: Array<relationalStore.ValueType> = []
    try {
      while (targetResultSet !== null && targetResultSet.goToNextRow()) {
        const columnIndex = targetResultSet.getColumnIndex(targetPkColumn.columnName)
        if (!targetResultSet.isColumnNull(columnIndex)) {
          const pkValue = targetResultSet.getLong(columnIndex)
          targetPkValues.push(pkValue)
        }
      }
    } catch (e) {
      // 忽略遍历错误
    } finally {
      this.options.closeResultSet(targetResultSet)
    }

    if (targetPkValues.length === 0) {
      return []
    }

    // 第二步：查询中间表，获取关联的源实体 ID
    const joinPredicates = new relationalStore.RdbPredicates(relation.joinTable)
    joinPredicates.in(relation.joinTargetKey, targetPkValues)

    let joinResultSet: relationalStore.ResultSet | null = null
    try {
      joinResultSet = await this.options.withQueryTimeout(store.query(joinPredicates, [relation.joinSourceKey]), 'SUBQUERY')
    } catch (e) {
      this.options.logger.logError(`子查询中间表查询失败: ${e instanceof Error ? e.message : String(e)}`)
      return []
    }

    // 收集源实体 ID（去重）
    const sourceIds: Set<string> = new Set()
    try {
      while (joinResultSet !== null && joinResultSet.goToNextRow()) {
        const columnIndex = joinResultSet.getColumnIndex(relation.joinSourceKey)
        if (!joinResultSet.isColumnNull(columnIndex)) {
          const sourceId = ResultSetUtils.getValueByRuntimeType(joinResultSet, columnIndex)
          if (sourceId !== null) {
            sourceIds.add(String(sourceId))
          }
        }
      }
    } catch (e) {
      // 忽略遍历错误
    } finally {
      this.options.closeResultSet(joinResultSet)
    }

    // 转换为数组
    const result: Array<ValueType> = []
    sourceIds.forEach((idStr: string) => {
      const numId = Number(idStr)
      if (!isNaN(numId)) {
        result.push(numId)
      } else {
        result.push(idStr)
      }
    })

    return result
  }

  private applySoftDeleteToPredicates(predicates: relationalStore.RdbPredicates, metadata: EntityMetadata): void {
    if (!metadata.isSoftDeleteEnabled()) {
      return
    }
    const deletedAtColumn = metadata.getDeletedAtColumn()
    predicates.isNull(deletedAtColumn)
  }

  private applyConditionToPredicates(
    predicates: relationalStore.RdbPredicates,
    condition: WhereCondition,
    metadata: EntityMetadata,
    entityName: string
  ): boolean {
    const resolvedColumn = this.resolveSubQueryColumn(metadata, condition.column)
    if (resolvedColumn === null) {
      this.options.logger.logError(`子查询列 '${condition.column}' 在实体 '${entityName}' 中不存在`)
      return false
    }
    const value = condition.value

    switch (condition.operator) {
      case ConditionOperator.EQUAL:
        predicates.equalTo(resolvedColumn, this.options.toRdbValue(value))
        break
      case ConditionOperator.NOT_EQUAL:
        predicates.notEqualTo(resolvedColumn, this.options.toRdbValue(value))
        break
      case ConditionOperator.GREATER:
        predicates.greaterThan(resolvedColumn, this.options.toRdbValue(value))
        break
      case ConditionOperator.LESS:
        predicates.lessThan(resolvedColumn, this.options.toRdbValue(value))
        break
      case ConditionOperator.GREATER_EQUAL:
        predicates.greaterThanOrEqualTo(resolvedColumn, this.options.toRdbValue(value))
        break
      case ConditionOperator.LESS_EQUAL:
        predicates.lessThanOrEqualTo(resolvedColumn, this.options.toRdbValue(value))
        break
      case ConditionOperator.LIKE:
        predicates.like(resolvedColumn, value !== null ? String(value) : '')
        break
      case ConditionOperator.IN:
        if (Array.isArray(value)) {
          const rdbValues: Array<relationalStore.ValueType> = []
          for (let i = 0; i < value.length; i++) {
            rdbValues.push(this.options.toRdbValue(value[i]))
          }
          predicates.in(resolvedColumn, rdbValues)
        }
        break
      case ConditionOperator.NOT_IN:
        if (Array.isArray(value)) {
          const rdbValues: Array<relationalStore.ValueType> = []
          for (let i = 0; i < value.length; i++) {
            rdbValues.push(this.options.toRdbValue(value[i]))
          }
          predicates.notIn(resolvedColumn, rdbValues)
        }
        break
      case ConditionOperator.BETWEEN:
        predicates.between(resolvedColumn, this.options.toRdbValue(value), this.options.toRdbValue(condition.secondValue))
        break
      case ConditionOperator.IS_NULL:
        predicates.isNull(resolvedColumn)
        break
      case ConditionOperator.IS_NOT_NULL:
        predicates.isNotNull(resolvedColumn)
        break
      default:
        break
    }
    return true
  }

  private resolveSubQueryColumn(metadata: EntityMetadata, column: string): string | null {
    const columnByName = metadata.getColumnByName(column)
    if (columnByName !== null) {
      return columnByName.columnName
    }
    const columnByProperty = metadata.getColumnByProperty(column)
    if (columnByProperty !== null) {
      return columnByProperty.columnName
    }
    return null
  }
}
