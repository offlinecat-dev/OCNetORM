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

    let resultIds: Map<string, ValueType> | null = null
    for (let i = 0; i < subQueries.length; i++) {
      const subQueryIds = await this.options.executeOneSubQuery(
        subQueries[i],
        store,
        entityName,
        sourcePkColumn.columnName
      )
      const currentIds: Map<string, ValueType> = new Map()
      for (let j = 0; j < subQueryIds.length; j++) {
        const value = subQueryIds[j]
        if (value === null || value === undefined) {
          continue
        }
        const key = this.toIdKey(value)
        if (!currentIds.has(key)) {
          currentIds.set(key, value)
        }
      }
      if (resultIds === null) {
        resultIds = currentIds
      } else {
        const merged: Map<string, ValueType> = new Map()
        currentIds.forEach((value, key) => {
          if (resultIds !== null && resultIds.has(key)) {
            const existed = resultIds.get(key)
            merged.set(key, existed !== undefined ? existed : value)
          }
        })
        resultIds = merged
      }
      if (resultIds.size === 0) {
        return []
      }
    }

    const finalIds: Array<ValueType> = []
    if (resultIds !== null) {
      resultIds.forEach((id) => {
        finalIds.push(id)
      })
    }
    return finalIds
  }

  private toIdKey(id: ValueType): string {
    if (typeof id === 'number') {
      return `n:${id}`
    }
    if (typeof id === 'boolean') {
      return `b:${id ? 1 : 0}`
    }
    return `s:${String(id)}`
  }
}
