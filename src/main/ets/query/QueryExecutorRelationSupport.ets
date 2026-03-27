import { relationalStore } from '@kit.ArkData'
import { QueryBuilder } from './QueryBuilder'
import { RelationLoader } from './RelationLoader'
import { EntityData, RelatedDataValue } from '../mapping/EntityData'
import { MetadataStorage } from '../core/MetadataStorage'
import { RelationType } from '../types/RelationType'
import { ExecutionError } from '../errors/DatabaseError'
import { RelationQueryOptions } from './RelationQueryOptions'
import { OrderByClause } from '../types/ValueTypes'
import { WhereCondition } from './WhereCondition'
import { DatabaseManager } from '../database/DatabaseManager'

type RelationPathObserver = (phase: string, relationPath: string) => Promise<void> | void

interface QueryExecutorRelationSupportOptions {
  queryBuilder: QueryBuilder
  relationLoader: RelationLoader
  getStore: () => relationalStore.RdbStore
  notifyRelationPath: RelationPathObserver
}

export class QueryExecutorRelationSupport {
  private queryBuilder: QueryBuilder
  private relationLoader: RelationLoader
  private getStore: () => relationalStore.RdbStore
  private notifyRelationPath: RelationPathObserver

  constructor(options: QueryExecutorRelationSupportOptions) {
    this.queryBuilder = options.queryBuilder
    this.relationLoader = options.relationLoader
    this.getStore = options.getStore
    this.notifyRelationPath = options.notifyRelationPath
  }

  async loadRelations(entities: Array<EntityData>): Promise<Array<EntityData>> {
    const relationNames = this.queryBuilder.getRelationNames()
    if (relationNames.length === 0) {
      return entities
    }

    const result = entities
    const concurrency = this.resolveRelationLoadConcurrency()
    if (concurrency <= 1 || relationNames.length <= 1) {
      for (let i = 0; i < relationNames.length; i++) {
        const relationPath = relationNames[i]
        const segments = this.splitRelationPath(relationPath)
        if (segments.length === 0) {
          continue
        }
        try {
          await this.loadRelationPathWithObserver(result, this.queryBuilder.getEntityName(), segments, 0, '')
        } catch (e) {
          const errorMessage = e instanceof Error ? e.message : String(e)
          throw new ExecutionError('RELATION_LOAD', errorMessage)
        }
      }
      return result
    }

    await this.runWithConcurrency(relationNames, concurrency, async (relationPath: string): Promise<void> => {
      const segments = this.splitRelationPath(relationPath)
      if (segments.length === 0) {
        return
      }
      await this.loadRelationPathWithObserver(result, this.queryBuilder.getEntityName(), segments, 0, '')
    })
    return result
  }

  splitRelationPath(relationPath: string): Array<string> {
    const normalized = relationPath.trim()
    if (normalized.length === 0) {
      return []
    }
    const parts = normalized.split('.')
    const result: Array<string> = []
    for (let i = 0; i < parts.length; i++) {
      const part = parts[i].trim()
      if (part.length > 0) {
        result.push(part)
      }
    }
    return result
  }

  async loadRelationPath(
    entities: Array<EntityData>,
    sourceEntityName: string,
    segments: Array<string>,
    index: number,
    prefix: string
  ): Promise<void> {
    if (index >= segments.length || entities.length === 0) {
      return
    }

    const relationName = segments[index]
    const fullPath = prefix.length > 0 ? `${prefix}.${relationName}` : relationName
    const relation = MetadataStorage.getInstance().getRelation(sourceEntityName, relationName)
    if (relation === null) {
      throw new ExecutionError('RELATION_LOAD', `关联 '${fullPath}' 未注册`)
    }

    const loader = sourceEntityName === this.queryBuilder.getEntityName()
      ? this.relationLoader
      : new RelationLoader(sourceEntityName, this.getStore)
    let options = this.queryBuilder.getRelationQueryOptions(fullPath)
    const morphCallback = this.queryBuilder.getMorphRelationQueryCallback(fullPath)
    if (options === null && morphCallback !== null && relation.targetEntity.length > 0) {
      options = this.buildRelationQueryOptionsFromCallback(relation.targetEntity, morphCallback)
    }
    try {
      await loader.loadRelation(entities, relationName, options, morphCallback)
    } catch (e) {
      if (e instanceof Error) {
        throw e
      }
      throw new Error(String(e))
    }

    if (index >= segments.length - 1) {
      return
    }

    if (relation.type === RelationType.MORPH_TO) {
      const morphChildren = this.collectMorphChildrenByEntity(entities, relationName)
      if (morphChildren.size === 0) {
        return
      }
      const nextRelationName = segments[index + 1]
      let hasSupportedTarget = false
      const entries = Array.from(morphChildren.entries())
      for (let i = 0; i < entries.length; i++) {
        const targetEntityName = entries[i][0]
        const targetChildren = entries[i][1]
        const nextRelation = MetadataStorage.getInstance().getRelation(targetEntityName, nextRelationName)
        if (nextRelation === null) {
          continue
        }
        hasSupportedTarget = true
        await this.loadRelationPath(targetChildren, targetEntityName, segments, index + 1, fullPath)
      }
      if (!hasSupportedTarget) {
        throw new ExecutionError('RELATION_LOAD', `关联 '${fullPath}.${nextRelationName}' 未注册`)
      }
      return
    }

    const children = this.collectRelationChildren(entities, relationName, relation.type)
    if (children.length === 0) {
      return
    }
    await this.loadRelationPath(children, relation.targetEntity, segments, index + 1, fullPath)
  }

  attachLazyRelations(entities: Array<EntityData>): void {
    const relationNames = this.queryBuilder.getLazyRelationNames()
    if (relationNames.length === 0 || entities.length === 0) {
      return
    }

    const storage = MetadataStorage.getInstance()
    for (let i = 0; i < relationNames.length; i++) {
      const relationName = relationNames[i]
      const relation = storage.getRelation(this.queryBuilder.getEntityName(), relationName)
      if (relation === null) {
        continue
      }
      for (let j = 0; j < entities.length; j++) {
        const entity = entities[j]
        if (entity.hasRelated(relationName) || entity.hasLazyRelation(relationName)) {
          continue
        }

        entity.setLazyRelation(relationName, async () => {
          await this.relationLoader.loadRelation([entity], relationName)
          const loaded = entity.getRelatedValue(relationName)
          if (loaded) {
            return loaded
          }

          let fallback: RelatedDataValue
          if (relation.type === RelationType.ONE_TO_MANY || relation.type === RelationType.MANY_TO_MANY) {
            fallback = RelatedDataValue.fromArray([])
          } else {
            fallback = RelatedDataValue.fromSingle(null)
          }
          entity.setRelated(relationName, fallback)
          return fallback
        })
      }
    }
  }

  private async loadRelationPathWithObserver(
    entities: Array<EntityData>,
    entityName: string,
    segments: Array<string>,
    index: number,
    prefix: string
  ): Promise<void> {
    const relationPath = segments.join('.')
    await this.notifyRelationPath('start', relationPath)
    try {
      await this.loadRelationPath(entities, entityName, segments, index, prefix)
    } finally {
      await this.notifyRelationPath('end', relationPath)
    }
  }

  private resolveRelationLoadConcurrency(): number {
    const config = DatabaseManager.getInstance().getConfig()
    if (config === null) {
      return 1
    }
    return config.relationLoadConcurrency > 0 ? config.relationLoadConcurrency : 1
  }

  private async runWithConcurrency<T>(
    items: Array<T>,
    concurrency: number,
    handler: (item: T) => Promise<void>
  ): Promise<void> {
    const total = items.length
    if (total === 0) {
      return
    }
    const limit = concurrency > 0 ? concurrency : 1
    let index = 0
    let firstErrorMessage: string | null = null

    const runner = async (): Promise<void> => {
      while (index < total && firstErrorMessage === null) {
        const currentIndex = index
        index += 1
        try {
          await handler(items[currentIndex])
        } catch (e) {
          const errorMessage = e instanceof Error ? e.message : String(e)
          firstErrorMessage = errorMessage
          break
        }
      }
    }

    const runners: Array<Promise<void>> = []
    for (let i = 0; i < Math.min(limit, total); i++) {
      runners.push(runner())
    }
    await Promise.all(runners)
    if (firstErrorMessage !== null) {
      throw new Error(firstErrorMessage)
    }
  }

  private collectRelationChildren(
    entities: Array<EntityData>,
    relationName: string,
    relationType: RelationType
  ): Array<EntityData> {
    const children: Array<EntityData> = []
    for (let i = 0; i < entities.length; i++) {
      if (relationType === RelationType.ONE_TO_MANY || relationType === RelationType.MANY_TO_MANY) {
        const related = entities[i].getRelatedArray(relationName)
        for (let j = 0; j < related.length; j++) {
          children.push(related[j])
        }
      } else {
        const related = entities[i].getRelatedSingle(relationName)
        if (related !== null) {
          children.push(related)
        }
      }
    }
    return children
  }

  private collectMorphChildrenByEntity(
    entities: Array<EntityData>,
    relationName: string
  ): Map<string, Array<EntityData>> {
    const groupedChildren: Map<string, Array<EntityData>> = new Map()
    for (let i = 0; i < entities.length; i++) {
      const child = entities[i].getRelatedSingle(relationName)
      if (child === null) {
        continue
      }
      let grouped = groupedChildren.get(child.entityName)
      if (grouped === undefined) {
        grouped = []
        groupedChildren.set(child.entityName, grouped)
      }
      grouped.push(child)
    }
    return groupedChildren
  }

  private buildRelationQueryOptionsFromCallback(
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
