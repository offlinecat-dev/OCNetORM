import { relationalStore } from '@kit.ArkData'
import { EntityData } from '../mapping/EntityData'
import { ResultSetRow } from '../mapping/ResultSetRow'
import { ValueType } from '../types/ValueTypes'
import { QueryExecutorSqlResult } from './QueryExecutorSqlSupport'

interface QueryExecutorSubQueryBatchSupportOptions {
  taskPoolThreshold: number
  applySubQueryFilter: (sourceIds: Array<ValueType>) => boolean
  buildPredicatesOrThrow: (operation: string) => relationalStore.RdbPredicates
  queryEntities: (
    store: relationalStore.RdbStore,
    predicates: relationalStore.RdbPredicates,
    selectedColumns: Array<string>
  ) => Promise<Array<EntityData>>
  queryResultSet: (
    store: relationalStore.RdbStore,
    predicates: relationalStore.RdbPredicates,
    selectedColumns: Array<string>,
    operation: string
  ) => Promise<relationalStore.ResultSet>
  transformWithTaskPool: (resultSet: relationalStore.ResultSet) => Promise<Array<EntityData>>
  transformInMainThread: (resultSet: relationalStore.ResultSet) => Array<EntityData>
  closeResultSet: (resultSet: relationalStore.ResultSet | null) => void
  restoreConditions: (originalCount: number) => void
  countByPredicates: (store: relationalStore.RdbStore) => Promise<number>
  buildSelectSql: () => QueryExecutorSqlResult
  withQueryTimeout: (
    task: Promise<relationalStore.ResultSet>,
    operation: string
  ) => Promise<relationalStore.ResultSet>
  resultSetToRawRow: (resultSet: relationalStore.ResultSet) => ResultSetRow
}

export class QueryExecutorSubQueryBatchSupport {
  private options: QueryExecutorSubQueryBatchSupportOptions

  constructor(options: QueryExecutorSubQueryBatchSupportOptions) {
    this.options = options
  }

  async queryEntitiesBySubQueryBatches(
    store: relationalStore.RdbStore,
    selectedColumns: Array<string>,
    batches: Array<Array<ValueType>>,
    originalConditionCount: number
  ): Promise<Array<EntityData>> {
    const results: Array<EntityData> = []
    for (let i = 0; i < batches.length; i++) {
      const batch = batches[i]
      try {
        if (!this.options.applySubQueryFilter(batch)) {
          return []
        }
        const predicates = this.options.buildPredicatesOrThrow('SELECT')
        const batchResults = await this.options.queryEntities(store, predicates, selectedColumns)
        for (let j = 0; j < batchResults.length; j++) {
          results.push(batchResults[j])
        }
      } finally {
        this.options.restoreConditions(originalConditionCount)
      }
    }
    return results
  }

  async queryEntitiesBySubQueryBatchesAsync(
    store: relationalStore.RdbStore,
    selectedColumns: Array<string>,
    batches: Array<Array<ValueType>>,
    originalConditionCount: number
  ): Promise<Array<EntityData>> {
    const results: Array<EntityData> = []
    for (let i = 0; i < batches.length; i++) {
      const batch = batches[i]
      let resultSet: relationalStore.ResultSet | null = null
      try {
        if (!this.options.applySubQueryFilter(batch)) {
          return []
        }
        const predicates = this.options.buildPredicatesOrThrow('SELECT')
        const queriedResultSet = await this.options.queryResultSet(store, predicates, selectedColumns, 'SELECT')
        resultSet = queriedResultSet
        const rowCount = queriedResultSet.rowCount
        let batchResults: Array<EntityData> = []
        if (rowCount > this.options.taskPoolThreshold) {
          batchResults = await this.options.transformWithTaskPool(queriedResultSet)
        } else {
          batchResults = this.options.transformInMainThread(queriedResultSet)
        }
        for (let j = 0; j < batchResults.length; j++) {
          results.push(batchResults[j])
        }
      } finally {
        this.options.closeResultSet(resultSet)
        this.options.restoreConditions(originalConditionCount)
      }
    }
    return results
  }

  async countBySubQueryBatches(
    store: relationalStore.RdbStore,
    batches: Array<Array<ValueType>>,
    originalConditionCount: number
  ): Promise<number> {
    let total = 0
    for (let i = 0; i < batches.length; i++) {
      const batch = batches[i]
      try {
        if (!this.options.applySubQueryFilter(batch)) {
          return 0
        }
        total += await this.options.countByPredicates(store)
      } finally {
        this.options.restoreConditions(originalConditionCount)
      }
    }
    return total
  }

  async queryRawBySubQueryBatches(
    store: relationalStore.RdbStore,
    batches: Array<Array<ValueType>>,
    originalConditionCount: number
  ): Promise<Array<ResultSetRow>> {
    const rows: Array<ResultSetRow> = []
    for (let i = 0; i < batches.length; i++) {
      const batch = batches[i]
      let resultSet: relationalStore.ResultSet | null = null
      try {
        if (!this.options.applySubQueryFilter(batch)) {
          return []
        }
        const sqlResult = this.options.buildSelectSql()
        resultSet = await this.options.withQueryTimeout(store.querySql(sqlResult.sql, sqlResult.args), 'RAW_SELECT')
        while (resultSet.goToNextRow()) {
          rows.push(this.options.resultSetToRawRow(resultSet))
        }
      } finally {
        this.options.closeResultSet(resultSet)
        this.options.restoreConditions(originalConditionCount)
      }
    }
    return rows
  }
}
