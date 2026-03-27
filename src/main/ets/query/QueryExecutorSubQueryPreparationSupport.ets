import { QueryBuilder } from './QueryBuilder'
import { ValueType } from '../types/ValueTypes'
import {
  buildIdSetFromValues,
  hasOrConditions,
  normalizeSubQueryIds,
  splitIntoBatches as splitIntoBatchesUtil
} from './QueryExecutionUtils'

type ExecuteSubQueries = () => Promise<Array<ValueType>>
type ApplySubQueryFilter = (sourceIds: Array<ValueType>) => boolean
type GetSubQueryInLimit = () => number

export class QueryExecutorSubQueryPreparationResult {
  noMatch: boolean = false
  inMemoryFilterIds: Set<string> | null = null
  subQueryIdBatches: Array<Array<ValueType>> | null = null
  subQueryFilterApplied: boolean = false
  requiresClearLimitOffset: boolean = false
}

export class QueryExecutorSubQueryPreparationSupport {
  private queryBuilder: QueryBuilder
  private executeSubQueries: ExecuteSubQueries
  private applySubQueryFilter: ApplySubQueryFilter
  private getSubQueryInLimit: GetSubQueryInLimit

  constructor(
    queryBuilder: QueryBuilder,
    executeSubQueries: ExecuteSubQueries,
    applySubQueryFilter: ApplySubQueryFilter,
    getSubQueryInLimit: GetSubQueryInLimit
  ) {
    this.queryBuilder = queryBuilder
    this.executeSubQueries = executeSubQueries
    this.applySubQueryFilter = applySubQueryFilter
    this.getSubQueryInLimit = getSubQueryInLimit
  }

  async prepare(): Promise<QueryExecutorSubQueryPreparationResult> {
    const result = new QueryExecutorSubQueryPreparationResult()
    if (!this.queryBuilder.hasSubQueries()) {
      return result
    }

    const subQueryIds = normalizeSubQueryIds(await this.executeSubQueries())
    if (subQueryIds.length === 0) {
      result.noMatch = true
      return result
    }

    if (hasOrConditions(this.queryBuilder.getConditions())) {
      result.inMemoryFilterIds = buildIdSetFromValues(subQueryIds)
      result.requiresClearLimitOffset = true
      return result
    }

    const subQueryInLimit = this.getSubQueryInLimit()
    if (subQueryIds.length > subQueryInLimit) {
      result.subQueryIdBatches = splitIntoBatchesUtil(subQueryIds, subQueryInLimit)
      result.requiresClearLimitOffset = true
      return result
    }

    result.subQueryFilterApplied = this.applySubQueryFilter(subQueryIds)
    return result
  }
}
