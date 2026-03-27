import { relationalStore } from '@kit.ArkData'
import { MetadataStorage } from '../core/MetadataStorage'
import { RelationMetadata } from '../core/RelationMetadata'
import { EntityMetadata } from '../core/EntityMetadata'
import { DataMapper } from '../mapping/DataMapper'
import { EntityData } from '../mapping/EntityData'
import { ResultSetRow } from '../mapping/ResultSetRow'
import { ValueType } from '../types/ValueTypes'
import { RelationQueryOptions } from './RelationQueryOptions'
import { splitIntoBatches as splitIntoBatchesUtil } from './QueryExecutionUtils'

type AsyncFailure = Error | object | string | number | boolean | null | undefined

type GetStore = () => relationalStore.RdbStore
type ResolveInClauseLimit = () => number
type ApplyRelationQueryToPredicates = (
  predicates: relationalStore.RdbPredicates,
  metadata: EntityMetadata,
  options: RelationQueryOptions | null
) => void
type ToRdbValue = (value: ValueType | Array<ValueType> | null) => relationalStore.ValueType
type WithQueryTimeout = (
  task: Promise<relationalStore.ResultSet>,
  operation: string
) => Promise<relationalStore.ResultSet>
type ResultSetToRow = (resultSet: relationalStore.ResultSet, metadata: EntityMetadata) => ResultSetRow
type CloseResultSet = (resultSet: relationalStore.ResultSet | null) => void
type LogRelationWarn = (context: string, error: AsyncFailure) => void

export class RelationLoaderOneToOneSupport {
  private sourceEntityName: string
  private getStore: GetStore
  private resolveInClauseLimit: ResolveInClauseLimit
  private applyRelationQueryToPredicates: ApplyRelationQueryToPredicates
  private toRdbValue: ToRdbValue
  private withQueryTimeout: WithQueryTimeout
  private resultSetToRow: ResultSetToRow
  private closeResultSet: CloseResultSet
  private logRelationWarn: LogRelationWarn

  constructor(
    sourceEntityName: string,
    getStore: GetStore,
    resolveInClauseLimit: ResolveInClauseLimit,
    applyRelationQueryToPredicates: ApplyRelationQueryToPredicates,
    toRdbValue: ToRdbValue,
    withQueryTimeout: WithQueryTimeout,
    resultSetToRow: ResultSetToRow,
    closeResultSet: CloseResultSet,
    logRelationWarn: LogRelationWarn
  ) {
    this.sourceEntityName = sourceEntityName
    this.getStore = getStore
    this.resolveInClauseLimit = resolveInClauseLimit
    this.applyRelationQueryToPredicates = applyRelationQueryToPredicates
    this.toRdbValue = toRdbValue
    this.withQueryTimeout = withQueryTimeout
    this.resultSetToRow = resultSetToRow
    this.closeResultSet = closeResultSet
    this.logRelationWarn = logRelationWarn
  }

  async loadOneToOneSourceSide(
    entities: Array<EntityData>,
    relation: RelationMetadata,
    options: RelationQueryOptions | null = null
  ): Promise<Array<EntityData>> {
    const targetMetadata = MetadataStorage.getInstance().getEntityMetadata(relation.targetEntity)
    if (targetMetadata === null) {
      return entities
    }
    const targetPkColumn = targetMetadata.getPrimaryKeyColumn()
    if (targetPkColumn === null) {
      return entities
    }
    const sourceMetadata = MetadataStorage.getInstance().getEntityMetadata(this.sourceEntityName)
    if (sourceMetadata === null) {
      return entities
    }

    const fkValues: Array<ValueType> = []
    const fkValueSet: Set<string> = new Set()
    for (let i = 0; i < entities.length; i++) {
      const fkValue = this.resolveRelationValue(entities[i], sourceMetadata, relation.inverseKey)
      if (fkValue !== null) {
        const fkKey = String(fkValue)
        if (!fkValueSet.has(fkKey)) {
          fkValueSet.add(fkKey)
          fkValues.push(fkValue)
        }
      }
    }

    if (fkValues.length === 0) {
      this.setAllRelatedSingleNull(entities, relation.propertyName)
      return entities
    }

    let store: relationalStore.RdbStore
    try {
      store = this.getStore()
    } catch (e) {
      this.setAllRelatedSingleNull(entities, relation.propertyName)
      return entities
    }

    const targetMapper = new DataMapper(relation.targetEntity)
    const relatedByPk: Map<string, EntityData> = new Map()
    const fkBatches = splitIntoBatchesUtil(fkValues, this.resolveInClauseLimit())

    for (let batchIndex = 0; batchIndex < fkBatches.length; batchIndex++) {
      const batch = fkBatches[batchIndex]
      const predicates = new relationalStore.RdbPredicates(targetMetadata.tableName)
      this.applyRelationQueryToPredicates(predicates, targetMetadata, options)

      const rdbValues: Array<relationalStore.ValueType> = []
      for (let i = 0; i < batch.length; i++) {
        rdbValues.push(this.toRdbValue(batch[i]))
      }
      try {
        predicates.in(targetPkColumn.columnName, rdbValues)
      } catch (e) {
        this.logRelationWarn(
          `ONE_TO_ONE(source) 构建查询条件失败: relation=${relation.propertyName}, batch=${batchIndex + 1}/${fkBatches.length}`,
          e
        )
        this.setAllRelatedSingleNull(entities, relation.propertyName)
        return entities
      }

      let resultSet: relationalStore.ResultSet | null = null
      try {
        resultSet = await this.withQueryTimeout(store.query(predicates), 'RELATION_LOAD')
      } catch (e) {
        this.logRelationWarn(
          `ONE_TO_ONE(source) 查询失败: relation=${relation.propertyName}, batch=${batchIndex + 1}/${fkBatches.length}`,
          e
        )
        this.setAllRelatedSingleNull(entities, relation.propertyName)
        return entities
      }

      try {
        while (resultSet !== null && resultSet.goToNextRow()) {
          const row = this.resultSetToRow(resultSet, targetMetadata)
          const relatedEntity = targetMapper.fromResultSetRow(row)
          const pkProp = relatedEntity.getProperty(targetPkColumn.propertyName)
          if (pkProp !== null && pkProp.value !== null) {
            relatedByPk.set(String(pkProp.value), relatedEntity)
          }
        }
      } catch (e) {
        this.logRelationWarn(
          `ONE_TO_ONE(source) 结果集遍历失败: relation=${relation.propertyName}, batch=${batchIndex + 1}/${fkBatches.length}`,
          e
        )
      } finally {
        this.closeResultSet(resultSet)
      }
    }

    for (let i = 0; i < entities.length; i++) {
      const fkValue = this.resolveRelationValue(entities[i], sourceMetadata, relation.inverseKey)
      if (fkValue !== null) {
        const relatedEntity = relatedByPk.get(String(fkValue))
        entities[i].setRelatedSingle(relation.propertyName, relatedEntity ? relatedEntity : null)
      } else {
        entities[i].setRelatedSingle(relation.propertyName, null)
      }
    }

    return entities
  }

  async loadOneToOneTargetSide(
    entities: Array<EntityData>,
    relation: RelationMetadata,
    options: RelationQueryOptions | null = null
  ): Promise<Array<EntityData>> {
    const sourceMetadata = MetadataStorage.getInstance().getEntityMetadata(this.sourceEntityName)
    if (sourceMetadata === null) {
      return entities
    }
    const sourcePkColumn = sourceMetadata.getPrimaryKeyColumn()
    if (sourcePkColumn === null) {
      return entities
    }
    const targetMetadata = MetadataStorage.getInstance().getEntityMetadata(relation.targetEntity)
    if (targetMetadata === null) {
      return entities
    }

    const pkValues: Array<ValueType> = []
    const pkValueSet: Set<string> = new Set()
    for (let i = 0; i < entities.length; i++) {
      const pkProp = entities[i].getProperty(sourcePkColumn.propertyName)
      if (pkProp !== null && pkProp.value !== null) {
        const pkKey = String(pkProp.value)
        if (!pkValueSet.has(pkKey)) {
          pkValueSet.add(pkKey)
          pkValues.push(pkProp.value)
        }
      }
    }

    if (pkValues.length === 0) {
      this.setAllRelatedSingleNull(entities, relation.propertyName)
      return entities
    }

    let store: relationalStore.RdbStore
    try {
      store = this.getStore()
    } catch (e) {
      this.setAllRelatedSingleNull(entities, relation.propertyName)
      return entities
    }

    const inverseKeyColumn = targetMetadata.getColumnByProperty(relation.inverseKey)
    const inverseColumnName = inverseKeyColumn !== null
      ? inverseKeyColumn.columnName
      : relation.inverseKey
    const targetMapper = new DataMapper(relation.targetEntity)
    const relatedByFk: Map<string, EntityData> = new Map()
    const pkBatches = splitIntoBatchesUtil(pkValues, this.resolveInClauseLimit())

    for (let batchIndex = 0; batchIndex < pkBatches.length; batchIndex++) {
      const batch = pkBatches[batchIndex]
      const predicates = new relationalStore.RdbPredicates(targetMetadata.tableName)
      this.applyRelationQueryToPredicates(predicates, targetMetadata, options)

      const rdbValues: Array<relationalStore.ValueType> = []
      for (let i = 0; i < batch.length; i++) {
        rdbValues.push(this.toRdbValue(batch[i]))
      }
      try {
        predicates.in(inverseColumnName, rdbValues)
      } catch (e) {
        this.logRelationWarn(
          `ONE_TO_ONE(target) 构建查询条件失败: relation=${relation.propertyName}, batch=${batchIndex + 1}/${pkBatches.length}`,
          e
        )
        this.setAllRelatedSingleNull(entities, relation.propertyName)
        return entities
      }

      let resultSet: relationalStore.ResultSet | null = null
      try {
        resultSet = await this.withQueryTimeout(store.query(predicates), 'RELATION_LOAD')
      } catch (e) {
        this.logRelationWarn(
          `ONE_TO_ONE(target) 查询失败: relation=${relation.propertyName}, batch=${batchIndex + 1}/${pkBatches.length}`,
          e
        )
        this.setAllRelatedSingleNull(entities, relation.propertyName)
        return entities
      }

      try {
        while (resultSet !== null && resultSet.goToNextRow()) {
          const row = this.resultSetToRow(resultSet, targetMetadata)
          const relatedEntity = targetMapper.fromResultSetRow(row)
          const fkValue = this.resolveRelationValue(relatedEntity, targetMetadata, relation.inverseKey)
          if (fkValue !== null) {
            relatedByFk.set(String(fkValue), relatedEntity)
          }
        }
      } catch (e) {
        this.logRelationWarn(
          `ONE_TO_ONE(target) 结果集遍历失败: relation=${relation.propertyName}, batch=${batchIndex + 1}/${pkBatches.length}`,
          e
        )
      } finally {
        this.closeResultSet(resultSet)
      }
    }

    for (let i = 0; i < entities.length; i++) {
      const entity = entities[i]
      const pkProp = entity.getProperty(sourcePkColumn.propertyName)
      if (pkProp !== null && pkProp.value !== null) {
        const relatedEntity = relatedByFk.get(String(pkProp.value))
        entity.setRelatedSingle(relation.propertyName, relatedEntity ? relatedEntity : null)
      } else {
        entity.setRelatedSingle(relation.propertyName, null)
      }
    }

    return entities
  }

  private resolveRelationValue(entity: EntityData, metadata: EntityMetadata, relationKey: string): ValueType {
    let prop = entity.getProperty(relationKey)
    if (prop === null) {
      const column = metadata.getColumnByName(relationKey)
      if (column !== null) {
        prop = entity.getProperty(column.propertyName)
      }
    }
    if (prop === null || prop.value === null) {
      return null
    }
    return prop.value
  }

  private setAllRelatedSingleNull(entities: Array<EntityData>, relationName: string): void {
    for (let i = 0; i < entities.length; i++) {
      entities[i].setRelatedSingle(relationName, null)
    }
  }
}
