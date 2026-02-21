import { relationalStore } from '@kit.ArkData'
import { QueryBuilder } from './QueryBuilder'
import { WhereCondition } from './WhereCondition'
import { EntityMetadata } from '../core/EntityMetadata'
import { ValueType } from '../types/ValueTypes'
import { ExecutionError } from '../errors/DatabaseError'
import { ResultSetUtils } from '../mapping/ResultSetUtils'
import { AggregateResult, AggregateRow } from './AggregateResult'

export interface AggregateWhereClauseResult {
  whereClause: string
  args: Array<relationalStore.ValueType>
}

export interface AggregateExecutorOptions {
  queryBuilder: QueryBuilder
  acquireQuerySlot: () => Promise<void>
  releaseQuerySlot: () => void
  getStore: () => relationalStore.RdbStore
  withQueryTimeout: (
    task: Promise<relationalStore.ResultSet>,
    operation: string
  ) => Promise<relationalStore.ResultSet>
  closeResultSet: (resultSet: relationalStore.ResultSet | null) => void
  buildWhereClause: (conditions: Array<WhereCondition>) => AggregateWhereClauseResult
  escapeIdentifier: (identifier: string) => string
  resolveColumnName: (metadata: EntityMetadata, column: string) => string | null
  toRdbValue: (value: ValueType | Array<ValueType> | null) => relationalStore.ValueType
}

export class AggregateExecutor {
  private options: AggregateExecutorOptions

  constructor(options: AggregateExecutorOptions) {
    this.options = options
  }

  async sum(column: string): Promise<number> {
    return await this.executeAggregateFunction('SUM', column)
  }

  async avg(column: string): Promise<number> {
    return await this.executeAggregateFunction('AVG', column)
  }

  async max(column: string): Promise<ValueType> {
    return await this.executeAggregateFunctionRaw('MAX', column)
  }

  async min(column: string): Promise<ValueType> {
    return await this.executeAggregateFunctionRaw('MIN', column)
  }

  async aggregate(): Promise<AggregateResult> {
    let querySlotAcquired = false
    await this.options.acquireQuerySlot()
    querySlotAcquired = true
    try {
      const store = this.options.getStore()
      const tableName = this.options.escapeIdentifier(this.options.queryBuilder.getTableName())
      const selectExpressions = this.options.queryBuilder.getSelectRawExpressions()
      const selectPart = selectExpressions.length > 0 ? selectExpressions.join(', ') : '*'
      const conditions = this.options.queryBuilder.getAllConditions()
      let wherePart = ''
      let args: Array<relationalStore.ValueType> = []
      if (conditions.length > 0) {
        const whereResult = this.options.buildWhereClause(conditions)
        wherePart = whereResult.whereClause
        args = whereResult.args
      }
      const groupByColumns = this.options.queryBuilder.getGroupByColumns()
      const groupByPart = groupByColumns.length > 0 ? ` GROUP BY ${groupByColumns.map((c) => this.options.escapeIdentifier(c)).join(', ')}` : ''
      const havingClause = this.options.queryBuilder.getHavingClause()
      const havingArgs = this.options.queryBuilder.getHavingArgs()
      let havingPart = ''
      if (havingClause.length > 0) {
        havingPart = ` HAVING ${havingClause}`
        for (let i = 0; i < havingArgs.length; i++) {
          args.push(this.options.toRdbValue(havingArgs[i]))
        }
      }
      const orderByColumns = this.options.queryBuilder.getOrderByColumns()
      const orderByPart = orderByColumns.length > 0
        ? ` ORDER BY ${orderByColumns.map((o) => `${this.options.escapeIdentifier(o.column)} ${this.normalizeOrderDirection(o.direction)}`).join(', ')}`
        : ''
      const sql = `SELECT ${selectPart} FROM ${tableName}${wherePart}${groupByPart}${havingPart}${orderByPart}`
      let resultSet: relationalStore.ResultSet | null = null
      const result = new AggregateResult()
      try {
        resultSet = await this.options.withQueryTimeout(store.querySql(sql, args), 'AGGREGATE')
        while (resultSet !== null && resultSet.goToNextRow()) {
          const row = new AggregateRow()
          const columnNames = resultSet.columnNames
          for (let i = 0; i < columnNames.length; i++) {
            const index = resultSet.getColumnIndex(columnNames[i])
            row.set(columnNames[i], !resultSet.isColumnNull(index) ? ResultSetUtils.getValueByRuntimeType(resultSet, index) as ValueType : null)
          }
          result.addRow(row)
        }
      } finally {
        this.options.closeResultSet(resultSet)
      }
      return result
    } catch (error) {
      if (error instanceof ExecutionError) {
        throw error
      }
      const errorMessage = error instanceof Error ? error.message : String(error)
      throw new ExecutionError('AGGREGATE', errorMessage)
    } finally {
      if (querySlotAcquired) {
        this.options.releaseQuerySlot()
      }
    }
  }

  private normalizeOrderDirection(direction: string): string {
    const normalized = direction.trim().toUpperCase()
    if (normalized === 'ASC' || normalized === 'DESC') {
      return normalized
    }
    throw new ExecutionError('ORDER BY', `非法排序方向: ${direction}`)
  }

  private async executeAggregateFunction(func: string, column: string): Promise<number> {
    const result = await this.executeAggregateFunctionRaw(func, column)
    if (result === null) {
      return 0
    }
    if (typeof result === 'number') {
      return result
    }
    const num = Number(result)
    return isNaN(num) ? 0 : num
  }

  private async executeAggregateFunctionRaw(func: string, column: string): Promise<ValueType> {
    let querySlotAcquired = false
    await this.options.acquireQuerySlot()
    querySlotAcquired = true
    try {
      const store = this.options.getStore()
      const metadata = this.options.queryBuilder.getEntityMetadata()
      const resolvedColumn = this.options.resolveColumnName(metadata, column)
      if (resolvedColumn === null) {
        throw new ExecutionError(func, `列 '${column}' 在实体中不存在`)
      }

      const tableName = this.options.escapeIdentifier(this.options.queryBuilder.getTableName())
      const escapedColumn = this.options.escapeIdentifier(resolvedColumn)
      const conditions = this.options.queryBuilder.getAllConditions()

      let sql: string
      let args: Array<relationalStore.ValueType> = []
      if (conditions.length === 0) {
        sql = `SELECT ${func}(${escapedColumn}) AS result FROM ${tableName}`
      } else {
        const whereResult = this.options.buildWhereClause(conditions)
        sql = `SELECT ${func}(${escapedColumn}) AS result FROM ${tableName}${whereResult.whereClause}`
        args = whereResult.args
      }

      let resultSet: relationalStore.ResultSet | null = null
      try {
        resultSet = await this.options.withQueryTimeout(store.querySql(sql, args), func)
        if (resultSet.goToFirstRow()) {
          const index = resultSet.getColumnIndex('result')
          if (index >= 0 && !resultSet.isColumnNull(index)) {
            return ResultSetUtils.getValueByRuntimeType(resultSet, index) as ValueType
          }
        }
        return null
      } finally {
        this.options.closeResultSet(resultSet)
      }
    } catch (error) {
      if (error instanceof ExecutionError) {
        throw error
      }
      const errorMessage = error instanceof Error ? error.message : String(error)
      throw new ExecutionError(func, errorMessage)
    } finally {
      if (querySlotAcquired) {
        this.options.releaseQuerySlot()
      }
    }
  }
}
