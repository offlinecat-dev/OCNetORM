import { relationalStore } from '@kit.ArkData'
import { MetadataStorage } from '../core/MetadataStorage'
import { EntityMetadata } from '../core/EntityMetadata'
import { ManyToManyMetadata } from '../core/ManyToManyMetadata'
import { DataMapper } from '../mapping/DataMapper'
import { EntityData } from '../mapping/EntityData'
import { ResultSetRow } from '../mapping/ResultSetRow'
import { ResultSetUtils } from '../mapping/ResultSetUtils'
import { ValueType } from '../types/ValueTypes'
import { RelationQueryOptions } from './RelationQueryOptions'
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
type ApplyCollectionQueryOptions = (
  entities: Array<EntityData>,
  options: RelationQueryOptions | null
) => Array<EntityData>

export class RelationLoaderManyToManySupport {
  private sourceEntityName: string
  private getStore: GetStore
  private resolveInClauseLimit: ResolveInClauseLimit
  private withQueryTimeout: WithQueryTimeout
  private closeResultSet: CloseResultSet
  private logRelationWarn: LogRelationWarn
  private applyRelationQueryToPredicates: ApplyRelationQueryToPredicates
  private toRdbValue: ToRdbValue
  private resultSetToRow: ResultSetToRow
  private applyCollectionQueryOptions: ApplyCollectionQueryOptions

  constructor(
    sourceEntityName: string,
    getStore: GetStore,
    resolveInClauseLimit: ResolveInClauseLimit,
    withQueryTimeout: WithQueryTimeout,
    closeResultSet: CloseResultSet,
    logRelationWarn: LogRelationWarn,
    applyRelationQueryToPredicates: ApplyRelationQueryToPredicates,
    toRdbValue: ToRdbValue,
    resultSetToRow: ResultSetToRow,
    applyCollectionQueryOptions: ApplyCollectionQueryOptions
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
    this.applyCollectionQueryOptions = applyCollectionQueryOptions
  }

  async loadManyToMany(
    entities: Array<EntityData>,
    relation: ManyToManyMetadata,
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

    const targetPkColumn = targetMetadata.getPrimaryKeyColumn()
    if (targetPkColumn === null) {
      return entities
    }

    const pkValues: Array<ValueType> = []
    const pkValueSet: Set<string> = new Set()
    for (let i = 0; i < entities.length; i++) {
      const entity = entities[i]
      const pkProp = entity.getProperty(sourcePkColumn.propertyName)
      if (pkProp !== null && pkProp.value !== null) {
        const pkKey = String(pkProp.value)
        if (!pkValueSet.has(pkKey)) {
          pkValueSet.add(pkKey)
          pkValues.push(pkProp.value)
        }
      }
    }

    if (pkValues.length === 0) {
      for (let i = 0; i < entities.length; i++) {
        entities[i].setRelatedArray(relation.propertyName, [])
      }
      return entities
    }

    let store: relationalStore.RdbStore
    try {
      store = this.getStore()
    } catch (e) {
      for (let i = 0; i < entities.length; i++) {
        entities[i].setRelatedArray(relation.propertyName, [])
      }
      return entities
    }

    const sourceToTargetIds: Map<string, Array<ValueType>> = new Map()
    const allTargetIds: Array<ValueType> = []
    const targetIdSet: Set<string> = new Set()
    const pkBatches = splitIntoBatchesUtil(pkValues, this.resolveInClauseLimit())

    for (let batchIndex = 0; batchIndex < pkBatches.length; batchIndex++) {
      const batch = pkBatches[batchIndex]
      const joinPredicates = new relationalStore.RdbPredicates(relation.joinTable)

      const rdbPkValues: Array<relationalStore.ValueType> = []
      for (let i = 0; i < batch.length; i++) {
        rdbPkValues.push(this.toRdbValue(batch[i]))
      }

      try {
        joinPredicates.in(relation.joinSourceKey, rdbPkValues)
      } catch (e) {
        this.logRelationWarn(
          `MANY_TO_MANY(中间表) 构建查询条件失败: relation=${relation.propertyName}, batch=${batchIndex + 1}/${pkBatches.length}`,
          e
        )
        continue
      }

      let joinResultSet: relationalStore.ResultSet | null = null
      try {
        joinResultSet = await this.withQueryTimeout(store.query(joinPredicates), 'RELATION_LOAD')
      } catch (e) {
        this.logRelationWarn(
          `MANY_TO_MANY(中间表) 查询失败: relation=${relation.propertyName}, batch=${batchIndex + 1}/${pkBatches.length}`,
          e
        )
        continue
      }

      try {
        while (joinResultSet !== null && joinResultSet.goToNextRow()) {
          const sourceKeyIndex = joinResultSet.getColumnIndex(relation.joinSourceKey)
          const targetKeyIndex = joinResultSet.getColumnIndex(relation.joinTargetKey)
          if (sourceKeyIndex >= 0 && targetKeyIndex >= 0) {
            let sourceId: ValueType = null
            let targetId: ValueType = null

            if (!joinResultSet.isColumnNull(sourceKeyIndex)) {
              const rawSourceId = ResultSetUtils.getValueByRuntimeType(joinResultSet, sourceKeyIndex)
              if (rawSourceId !== null && !(rawSourceId instanceof Uint8Array)) {
                sourceId = rawSourceId
              }
            }
            if (!joinResultSet.isColumnNull(targetKeyIndex)) {
              const rawTargetId = ResultSetUtils.getValueByRuntimeType(joinResultSet, targetKeyIndex)
              if (rawTargetId !== null && !(rawTargetId instanceof Uint8Array)) {
                targetId = rawTargetId
              }
            }

            if (sourceId !== null && targetId !== null) {
              const sourceKey = String(sourceId)
              const targetKey = String(targetId)
              let targetIds = sourceToTargetIds.get(sourceKey)
              if (!targetIds) {
                targetIds = []
                sourceToTargetIds.set(sourceKey, targetIds)
              }
              targetIds.push(targetId)
              if (!targetIdSet.has(targetKey)) {
                targetIdSet.add(targetKey)
                allTargetIds.push(targetId)
              }
            }
          }
        }
      } catch (e) {
        this.logRelationWarn(
          `MANY_TO_MANY(中间表) 结果集遍历失败: relation=${relation.propertyName}, batch=${batchIndex + 1}/${pkBatches.length}`,
          e
        )
      } finally {
        this.closeResultSet(joinResultSet)
      }
    }

    if (allTargetIds.length === 0) {
      for (let i = 0; i < entities.length; i++) {
        entities[i].setRelatedArray(relation.propertyName, [])
      }
      return entities
    }

    const targetMapper = new DataMapper(relation.targetEntity)
    const targetEntitiesByPk: Map<string, EntityData> = new Map()
    const targetIdBatches = splitIntoBatchesUtil(allTargetIds, this.resolveInClauseLimit())

    for (let batchIndex = 0; batchIndex < targetIdBatches.length; batchIndex++) {
      const batch = targetIdBatches[batchIndex]
      const targetPredicates = new relationalStore.RdbPredicates(targetMetadata.tableName)
      this.applyRelationQueryToPredicates(targetPredicates, targetMetadata, options)

      const rdbTargetIds: Array<relationalStore.ValueType> = []
      for (let i = 0; i < batch.length; i++) {
        rdbTargetIds.push(this.toRdbValue(batch[i]))
      }

      try {
        targetPredicates.in(targetPkColumn.columnName, rdbTargetIds)
      } catch (e) {
        this.logRelationWarn(
          `MANY_TO_MANY(目标表) 构建查询条件失败: relation=${relation.propertyName}, batch=${batchIndex + 1}/${targetIdBatches.length}`,
          e
        )
        continue
      }

      let targetResultSet: relationalStore.ResultSet | null = null
      try {
        targetResultSet = await this.withQueryTimeout(store.query(targetPredicates), 'RELATION_LOAD')
      } catch (e) {
        this.logRelationWarn(
          `MANY_TO_MANY(目标表) 查询失败: relation=${relation.propertyName}, batch=${batchIndex + 1}/${targetIdBatches.length}`,
          e
        )
        continue
      }

      try {
        while (targetResultSet !== null && targetResultSet.goToNextRow()) {
          const row = this.resultSetToRow(targetResultSet, targetMetadata)
          const targetEntity = targetMapper.fromResultSetRow(row)
          const pkProp = targetEntity.getProperty(targetPkColumn.propertyName)
          if (pkProp !== null && pkProp.value !== null) {
            targetEntitiesByPk.set(String(pkProp.value), targetEntity)
          }
        }
      } catch (e) {
        this.logRelationWarn(
          `MANY_TO_MANY(目标表) 结果集遍历失败: relation=${relation.propertyName}, batch=${batchIndex + 1}/${targetIdBatches.length}`,
          e
        )
      } finally {
        this.closeResultSet(targetResultSet)
      }
    }

    for (let i = 0; i < entities.length; i++) {
      const entity = entities[i]
      const pkProp = entity.getProperty(sourcePkColumn.propertyName)
      if (pkProp !== null && pkProp.value !== null) {
        const sourceKey = String(pkProp.value)
        const targetIds = sourceToTargetIds.get(sourceKey)
        if (targetIds && targetIds.length > 0) {
          const relatedEntities: Array<EntityData> = []
          for (let j = 0; j < targetIds.length; j++) {
            const targetEntity = targetEntitiesByPk.get(String(targetIds[j]))
            if (targetEntity) {
              relatedEntities.push(targetEntity)
            }
          }
          entity.setRelatedArray(relation.propertyName, this.applyCollectionQueryOptions(relatedEntities, options))
        } else {
          entity.setRelatedArray(relation.propertyName, [])
        }
      } else {
        entity.setRelatedArray(relation.propertyName, [])
      }
    }

    return entities
  }
}
