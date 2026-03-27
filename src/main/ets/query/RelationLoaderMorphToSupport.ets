import { relationalStore } from '@kit.ArkData'
import { MetadataStorage } from '../core/MetadataStorage'
import { MorphToMetadata } from '../core/MorphToMetadata'
import { EntityMetadata } from '../core/EntityMetadata'
import { DataMapper } from '../mapping/DataMapper'
import { EntityData } from '../mapping/EntityData'
import { ResultSetRow } from '../mapping/ResultSetRow'
import { ValueType, OrderByClause } from '../types/ValueTypes'
import { RelationQueryOptions } from './RelationQueryOptions'
import { WhereCondition } from './WhereCondition'
import { QueryBuilder } from './QueryBuilder'
import { splitIntoBatches as splitIntoBatchesUtil } from './QueryExecutionUtils'

type AsyncFailure = Error | object | string | number | boolean | null | undefined

type GetStore = () => relationalStore.RdbStore
type ResolveInClauseLimit = () => number
type WithQueryTimeout = (
  task: Promise<relationalStore.ResultSet>,
  operation: string
) => Promise<relationalStore.ResultSet>
type CloseResultSet = (resultSet: relationalStore.ResultSet | null) => void
type LogRelationWarn = (context: string, error: AsyncFailure) => void
type ApplyRelationQueryToPredicates = (
  predicates: relationalStore.RdbPredicates,
  metadata: EntityMetadata,
  options: RelationQueryOptions | null
) => void
type ToRdbValue = (value: ValueType | Array<ValueType> | null) => relationalStore.ValueType
type ResultSetToRow = (resultSet: relationalStore.ResultSet, metadata: EntityMetadata) => ResultSetRow

export class RelationLoaderMorphToSupport {
  private sourceEntityName: string
  private getStore: GetStore
  private resolveInClauseLimit: ResolveInClauseLimit
  private withQueryTimeout: WithQueryTimeout
  private closeResultSet: CloseResultSet
  private logRelationWarn: LogRelationWarn
  private applyRelationQueryToPredicates: ApplyRelationQueryToPredicates
  private toRdbValue: ToRdbValue
  private resultSetToRow: ResultSetToRow

  constructor(
    sourceEntityName: string,
    getStore: GetStore,
    resolveInClauseLimit: ResolveInClauseLimit,
    withQueryTimeout: WithQueryTimeout,
    closeResultSet: CloseResultSet,
    logRelationWarn: LogRelationWarn,
    applyRelationQueryToPredicates: ApplyRelationQueryToPredicates,
    toRdbValue: ToRdbValue,
    resultSetToRow: ResultSetToRow
  ) {
    this.sourceEntityName = sourceEntityName
    this.getStore = getStore
    this.resolveInClauseLimit = resolveInClauseLimit
    this.withQueryTimeout = withQueryTimeout
    this.closeResultSet = closeResultSet
    this.logRelationWarn = logRelationWarn
    this.applyRelationQueryToPredicates = applyRelationQueryToPredicates
    this.toRdbValue = toRdbValue
    this.resultSetToRow = resultSetToRow
  }

  async loadMorphTo(
    entities: Array<EntityData>,
    relation: MorphToMetadata,
    options: RelationQueryOptions | null = null,
    morphWithWhereCallback: ((qb: QueryBuilder) => void) | null = null
  ): Promise<Array<EntityData>> {
    const sourceMetadata = MetadataStorage.getInstance().getEntityMetadata(this.sourceEntityName)
    if (sourceMetadata === null) {
      return entities
    }

    const entitiesByRef: Map<string, Array<EntityData>> = new Map()
    const idsByType: Map<string, Array<ValueType>> = new Map()
    const seenIdByType: Map<string, Set<string>> = new Map()

    for (let i = 0; i < entities.length; i++) {
      const entity = entities[i]
      entity.setRelatedSingle(relation.propertyName, null)
      const typeValue = this.resolveEntityValue(entity, sourceMetadata, relation.typeColumn)
      const idValue = this.resolveEntityValue(entity, sourceMetadata, relation.idColumn)
      if (typeValue === null || idValue === null) {
        continue
      }
      const normalizedType = String(typeValue)
      if (normalizedType.length === 0) {
        continue
      }
      const refKey = `${normalizedType}::${String(idValue)}`
      let owners = entitiesByRef.get(refKey)
      if (!owners) {
        owners = []
        entitiesByRef.set(refKey, owners)
      }
      owners.push(entity)
      this.collectMorphId(idsByType, seenIdByType, normalizedType, idValue)
    }

    if (entitiesByRef.size === 0) {
      return entities
    }

    let store: relationalStore.RdbStore
    try {
      store = this.getStore()
    } catch (e) {
      return entities
    }

    const typeEntries = Array.from(idsByType.entries())
    for (let i = 0; i < typeEntries.length; i++) {
      const typeValue = typeEntries[i][0]
      const ids = typeEntries[i][1]
      if (ids.length === 0) {
        continue
      }

      const targetEntityName = relation.resolveTargetEntity(typeValue)
      if (targetEntityName.length === 0) {
        continue
      }

      const targetMetadata = MetadataStorage.getInstance().getEntityMetadata(targetEntityName)
      if (targetMetadata === null) {
        continue
      }
      const targetPkColumn = targetMetadata.getPrimaryKeyColumn()
      if (targetPkColumn === null) {
        continue
      }

      const targetMapper = new DataMapper(targetEntityName)
      let effectiveOptions = options
      if (morphWithWhereCallback !== null) {
        effectiveOptions = this.buildMorphRelationOptions(targetEntityName, morphWithWhereCallback)
      }
      const batches = splitIntoBatchesUtil(ids, this.resolveInClauseLimit())
      for (let batchIndex = 0; batchIndex < batches.length; batchIndex++) {
        const batch = batches[batchIndex]
        const predicates = new relationalStore.RdbPredicates(targetMetadata.tableName)
        this.applyRelationQueryToPredicates(predicates, targetMetadata, effectiveOptions)
        const rdbValues: Array<relationalStore.ValueType> = []
        for (let j = 0; j < batch.length; j++) {
          rdbValues.push(this.toRdbValue(batch[j]))
        }
        try {
          predicates.in(targetPkColumn.columnName, rdbValues)
        } catch (e) {
          this.logRelationWarn(
            `MORPH_TO 构建查询条件失败: relation=${relation.propertyName}, target=${targetEntityName}, batch=${batchIndex + 1}/${batches.length}`,
            e
          )
          continue
        }

        let resultSet: relationalStore.ResultSet | null = null
        try {
          resultSet = await this.withQueryTimeout(store.query(predicates), 'RELATION_LOAD')
        } catch (e) {
          this.logRelationWarn(
            `MORPH_TO 查询失败: relation=${relation.propertyName}, target=${targetEntityName}, batch=${batchIndex + 1}/${batches.length}`,
            e
          )
          continue
        }
        try {
          while (resultSet !== null && resultSet.goToNextRow()) {
            const row = this.resultSetToRow(resultSet, targetMetadata)
            const relatedEntity = targetMapper.fromResultSetRow(row)
            const pkProp = relatedEntity.getProperty(targetPkColumn.propertyName)
            if (pkProp === null || pkProp.value === null) {
              continue
            }
            const refKey = `${typeValue}::${String(pkProp.value)}`
            const owners = entitiesByRef.get(refKey)
            if (!owners) {
              continue
            }
            for (let ownerIndex = 0; ownerIndex < owners.length; ownerIndex++) {
              owners[ownerIndex].setRelatedSingle(relation.propertyName, relatedEntity)
            }
          }
        } catch (e) {
          this.logRelationWarn(
            `MORPH_TO 结果集遍历失败: relation=${relation.propertyName}, target=${targetEntityName}, batch=${batchIndex + 1}/${batches.length}`,
            e
          )
          throw e instanceof Error ? e : new Error(String(e))
        } finally {
          this.closeResultSet(resultSet)
        }
      }
    }

    return entities
  }

  private resolveEntityValue(
    entity: EntityData,
    metadata: EntityMetadata,
    propertyOrColumnName: string
  ): ValueType {
    let prop = entity.getProperty(propertyOrColumnName)
    if (prop !== null) {
      return prop.value
    }
    const column = metadata.getColumnByName(propertyOrColumnName)
    if (column === null) {
      return null
    }
    prop = entity.getProperty(column.propertyName)
    if (prop === null) {
      return null
    }
    return prop.value
  }

  private collectMorphId(
    idsByType: Map<string, Array<ValueType>>,
    seenIdByType: Map<string, Set<string>>,
    typeValue: string,
    idValue: ValueType
  ): void {
    let ids = idsByType.get(typeValue)
    if (!ids) {
      ids = []
      idsByType.set(typeValue, ids)
    }
    let seen = seenIdByType.get(typeValue)
    if (!seen) {
      seen = new Set<string>()
      seenIdByType.set(typeValue, seen)
    }
    const idKey = String(idValue)
    if (!seen.has(idKey)) {
      seen.add(idKey)
      ids.push(idValue)
    }
  }

  private buildMorphRelationOptions(
    targetEntityName: string,
    callback: (qb: QueryBuilder) => void
  ): RelationQueryOptions {
    const relationBuilder = new QueryBuilder(targetEntityName)
    callback(relationBuilder)
    const options = new RelationQueryOptions()
    const conditions = relationBuilder.getConditions()
    for (let i = 0; i < conditions.length; i++) {
      const source = conditions[i]
      const target = new WhereCondition()
      target.column = source.column
      target.operator = source.operator
      target.value = source.value
      target.secondValue = source.secondValue
      target.logicalOperator = source.logicalOperator
      options.conditions.push(target)
    }
    const orderByColumns = relationBuilder.getOrderByColumns()
    for (let i = 0; i < orderByColumns.length; i++) {
      const item = orderByColumns[i]
      options.orderByColumns.push(new OrderByClause(item.column, item.direction))
    }
    options.limitValue = relationBuilder.getLimitValue()
    options.offsetValue = relationBuilder.getOffsetValue()
    options.includeDeleted = relationBuilder.isIncludeDeleted()
    options.onlyDeleted = relationBuilder.isOnlyDeleted()
    return options
  }
}
