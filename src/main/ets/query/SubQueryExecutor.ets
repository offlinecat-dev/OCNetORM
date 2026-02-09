import { relationalStore } from '@kit.ArkData'
import { QueryBuilder } from './QueryBuilder'
import { SubQuery } from './SubQuery'
import { Logger } from '../logging/Logger'
import { MetadataStorage } from '../core/MetadataStorage'
import { ValueType } from '../types/ValueTypes'

export interface SubQueryExecutorOptions {
  queryBuilder: QueryBuilder
  logger: Logger
  getStore: () => relationalStore.RdbStore
  executeOneSubQuery: (
    subQuery: SubQuery,
    store: relationalStore.RdbStore,
    entityName: string,
    sourcePkColumn: string
  ) => Promise<Array<ValueType>>
}

export class SubQueryExecutor {
  private options: SubQueryExecutorOptions

  constructor(options: SubQueryExecutorOptions) {
    this.options = options
  }

  async executeSubQueries(): Promise<Array<ValueType>> {
    const subQueries = this.options.queryBuilder.getSubQueries()
    if (subQueries.length === 0) {
      return []
    }

    let store: relationalStore.RdbStore
    try {
      store = this.options.getStore()
    } catch (e) {
      this.options.logger.logError('子查询执行失败: 无法获取数据库连接')
      return []
    }

    const entityName = this.options.queryBuilder.getEntityName()
    const sourceMetadata = MetadataStorage.getInstance().getEntityMetadata(entityName)
    if (sourceMetadata === null) {
      return []
    }

    const sourcePkColumn = sourceMetadata.getPrimaryKeyColumn()
    if (sourcePkColumn === null) {
      return []
    }

    let resultIds: Set<string> | null = null
    for (let i = 0; i < subQueries.length; i++) {
      const subQueryIds = await this.options.executeOneSubQuery(
        subQueries[i],
        store,
        entityName,
        sourcePkColumn.columnName
      )
      if (resultIds === null) {
        resultIds = new Set<string>()
        for (let j = 0; j < subQueryIds.length; j++) {
          resultIds.add(String(subQueryIds[j]))
        }
      } else {
        const merged = new Set<string>()
        for (let j = 0; j < subQueryIds.length; j++) {
          const id = String(subQueryIds[j])
          if (resultIds.has(id)) {
            merged.add(id)
          }
        }
        resultIds = merged
      }
      if (resultIds.size === 0) {
        return []
      }
    }

    const finalIds: Array<ValueType> = []
    if (resultIds !== null) {
      resultIds.forEach((id: string) => {
        const asNum = Number(id)
        finalIds.push(isNaN(asNum) ? id : asNum)
      })
    }
    return finalIds
  }
}
