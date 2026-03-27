import { MetadataStorage } from '../core/MetadataStorage'
import { RelationType } from '../types/RelationType'
import { EntityData } from '../mapping/EntityData'
import { RelationLoadResult, ParallelRelationLoadResult } from './RelationLoadResult'
import { Logger } from '../logging/Logger'

type AsyncFailure = Error | object | string | number | boolean | null | undefined
type LoadRelationCallback = (entities: Array<EntityData>, relationName: string) => Promise<Array<EntityData>>
type ResolveErrorMessageCallback = (error: AsyncFailure) => string
type LogWarnMessageCallback = (context: string, message: string) => void

export class RelationLoaderParallelSupport {
  private sourceEntityName: string
  private loadRelation: LoadRelationCallback
  private resolveErrorMessage: ResolveErrorMessageCallback
  private logWarnMessage: LogWarnMessageCallback

  constructor(
    sourceEntityName: string,
    loadRelation: LoadRelationCallback,
    resolveErrorMessage: ResolveErrorMessageCallback,
    logWarnMessage: LogWarnMessageCallback
  ) {
    this.sourceEntityName = sourceEntityName
    this.loadRelation = loadRelation
    this.resolveErrorMessage = resolveErrorMessage
    this.logWarnMessage = logWarnMessage
  }

  async loadRelationsParallel(
    entities: Array<EntityData>,
    relationNames: Array<string>
  ): Promise<Array<EntityData>> {
    if (entities.length === 0 || relationNames.length === 0) {
      return entities
    }

    const startTime = Date.now()
    const logger = Logger.getInstance()

    if (relationNames.length === 1) {
      try {
        const result = await this.loadRelation(entities, relationNames[0])
        const duration = Date.now() - startTime
        logger.logDebug(`并行关联加载完成: 1 个关联, 耗时 ${duration}ms`)
        return result
      } catch (e) {
        const message = this.resolveErrorMessage(e)
        this.logWarnMessage(`关联 '${relationNames[0]}' 加载失败`, message)
        return entities
      }
    }

    const loadTasks: Array<Promise<RelationLoadResult>> = []
    for (let i = 0; i < relationNames.length; i++) {
      loadTasks.push(this.loadRelationWithResult(entities, relationNames[i]))
    }
    const results = await Promise.all(loadTasks)

    const parallelResult = new ParallelRelationLoadResult()
    parallelResult.totalDuration = Date.now() - startTime

    let successCount = 0
    let failureCount = 0
    for (let i = 0; i < results.length; i++) {
      parallelResult.addResult(results[i])
      if (results[i].success) {
        successCount += 1
      } else {
        failureCount += 1
        this.logWarnMessage(`关联 '${results[i].relationName}' 加载失败`, results[i].errorMessage)
      }
    }

    logger.logDebug(
      `并行关联加载完成: ${relationNames.length} 个关联, 成功 ${successCount}, 失败 ${failureCount}, 总耗时 ${parallelResult.totalDuration}ms`
    )

    return entities
  }

  private async loadRelationWithResult(
    entities: Array<EntityData>,
    relationName: string
  ): Promise<RelationLoadResult> {
    const startTime = Date.now()
    try {
      const relation = MetadataStorage.getInstance().getRelation(this.sourceEntityName, relationName)
      if (relation === null) {
        const duration = Date.now() - startTime
        return RelationLoadResult.createFailure(relationName, `关联 '${relationName}' 未注册`, duration)
      }

      await this.loadRelation(entities, relationName)

      let loadedCount = 0
      if (relation.type === RelationType.ONE_TO_MANY || relation.type === RelationType.MANY_TO_MANY) {
        for (let i = 0; i < entities.length; i++) {
          const relatedData = entities[i].getRelatedArray(relationName)
          if (relatedData !== null) {
            loadedCount += relatedData.length
          }
        }
      } else {
        for (let i = 0; i < entities.length; i++) {
          const relatedData = entities[i].getRelatedSingle(relationName)
          if (relatedData !== null) {
            loadedCount += 1
          }
        }
      }

      const duration = Date.now() - startTime
      return RelationLoadResult.createSuccess(relationName, loadedCount, duration)
    } catch (e) {
      const duration = Date.now() - startTime
      const errorMessage = this.resolveErrorMessage(e)
      return RelationLoadResult.createFailure(relationName, errorMessage, duration)
    }
  }
}
