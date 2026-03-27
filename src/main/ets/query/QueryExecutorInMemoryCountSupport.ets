import { relationalStore } from '@kit.ArkData'
import { QueryBuilder } from './QueryBuilder'
import { ExecutionError } from '../errors/DatabaseError'

type RunWithClearedLimitOffset = (operation: string, task: () => Promise<number>) => Promise<number>
type BuildPredicatesOrThrow = (operation: string) => relationalStore.RdbPredicates
type QueryResultSet = (
  store: relationalStore.RdbStore,
  predicates: relationalStore.RdbPredicates,
  selectedColumns: Array<string>,
  operation: string
) => Promise<relationalStore.ResultSet>
type CountIdsFromResultSet = (
  resultSet: relationalStore.ResultSet,
  idColumn: string,
  idSet: Set<string>
) => number
type CloseResultSet = (resultSet: relationalStore.ResultSet | null) => void

export class QueryExecutorInMemoryCountSupport {
  private queryBuilder: QueryBuilder
  private runWithClearedLimitOffset: RunWithClearedLimitOffset
  private buildPredicatesOrThrow: BuildPredicatesOrThrow
  private queryResultSet: QueryResultSet
  private countIdsFromResultSet: CountIdsFromResultSet
  private closeResultSet: CloseResultSet

  constructor(
    queryBuilder: QueryBuilder,
    runWithClearedLimitOffset: RunWithClearedLimitOffset,
    buildPredicatesOrThrow: BuildPredicatesOrThrow,
    queryResultSet: QueryResultSet,
    countIdsFromResultSet: CountIdsFromResultSet,
    closeResultSet: CloseResultSet
  ) {
    this.queryBuilder = queryBuilder
    this.runWithClearedLimitOffset = runWithClearedLimitOffset
    this.buildPredicatesOrThrow = buildPredicatesOrThrow
    this.queryResultSet = queryResultSet
    this.countIdsFromResultSet = countIdsFromResultSet
    this.closeResultSet = closeResultSet
  }

  async countWithInMemoryFilter(
    store: relationalStore.RdbStore,
    idSet: Set<string>
  ): Promise<number> {
    const metadata = this.queryBuilder.getEntityMetadata()
    const pkColumn = metadata.getPrimaryKeyColumn()
    if (pkColumn === null) {
      return 0
    }

    let resultSet: relationalStore.ResultSet | null = null
    try {
      return await this.runWithClearedLimitOffset('COUNT', async (): Promise<number> => {
        const predicates = this.buildPredicatesOrThrow('COUNT')
        try {
          const queriedResultSet = await this.queryResultSet(store, predicates, [pkColumn.columnName], 'COUNT')
          resultSet = queriedResultSet
          return this.countIdsFromResultSet(queriedResultSet, pkColumn.columnName, idSet)
        } catch (e) {
          const errorMessage = e instanceof Error ? e.message : String(e)
          throw new ExecutionError('COUNT', `执行统计查询失败: ${errorMessage}`)
        }
      })
    } catch (error) {
      if (error instanceof ExecutionError) {
        throw error
      }
      const errorMessage = error instanceof Error ? error.message : String(error)
      throw new ExecutionError('COUNT', errorMessage)
    } finally {
      this.closeResultSet(resultSet)
    }
  }
}
