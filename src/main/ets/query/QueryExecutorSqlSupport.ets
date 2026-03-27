import { relationalStore } from '@kit.ArkData'
import { QueryBuilder } from './QueryBuilder'
import { WhereCondition, LogicalOperator } from './WhereCondition'
import { ConditionOperator } from '../types/ConditionOperator'
import { ValueType } from '../types/ValueTypes'
import { ExecutionError } from '../errors/DatabaseError'

type ToRdbValue = (value: ValueType | Array<ValueType> | null) => relationalStore.ValueType

export class QueryExecutorWhereClauseResult {
  whereClause: string
  args: Array<relationalStore.ValueType>

  constructor(whereClause: string, args: Array<relationalStore.ValueType>) {
    this.whereClause = whereClause
    this.args = args
  }
}

export class QueryExecutorSqlResult {
  sql: string
  args: Array<relationalStore.ValueType>

  constructor(sql: string, args: Array<relationalStore.ValueType>) {
    this.sql = sql
    this.args = args
  }
}

export class QueryExecutorSqlSupport {
  private queryBuilder: QueryBuilder
  private toRdbValue: ToRdbValue

  constructor(queryBuilder: QueryBuilder, toRdbValue: ToRdbValue) {
    this.queryBuilder = queryBuilder
    this.toRdbValue = toRdbValue
  }

  buildSelectSql(): QueryExecutorSqlResult {
    const tableName = this.escapeIdentifier(this.queryBuilder.getTableName())
    const selectClause = this.buildSelectClause()
    const whereResult = this.buildWhereClause(this.queryBuilder.getAllConditions())
    const groupByClause = this.buildGroupByClause()
    const orderByClause = this.buildOrderByClause()
    const limit = this.queryBuilder.getLimitValue()
    const offset = this.queryBuilder.getOffsetValue()
    let sql = `SELECT ${selectClause} FROM ${tableName}${whereResult.whereClause}${groupByClause}`
    const havingClause = this.queryBuilder.getHavingClause()
    if (havingClause.length > 0) {
      sql += ` HAVING ${havingClause}`
      const havingArgs = this.queryBuilder.getHavingArgs()
      for (let i = 0; i < havingArgs.length; i++) {
        whereResult.args.push(this.toRdbValue(havingArgs[i]))
      }
    }
    sql += orderByClause
    if (limit > 0) {
      sql += ` LIMIT ${limit}`
    }
    if (offset > 0) {
      sql += ` OFFSET ${offset}`
    }
    return new QueryExecutorSqlResult(sql, whereResult.args)
  }

  buildWhereClause(conditions: Array<WhereCondition>): QueryExecutorWhereClauseResult {
    const whereParts: Array<string> = []
    const args: Array<relationalStore.ValueType> = []

    for (let i = 0; i < conditions.length; i++) {
      const cond = conditions[i]
      if (i > 0) {
        whereParts.push(cond.logicalOperator === LogicalOperator.OR ? 'OR' : 'AND')
      }

      const column = this.escapeIdentifier(cond.column)

      if (cond.operator === ConditionOperator.IN || cond.operator === ConditionOperator.NOT_IN) {
        if (!Array.isArray(cond.value) || cond.value.length === 0) {
          whereParts.push(cond.operator === ConditionOperator.IN ? '1=0' : '1=1')
          continue
        }
        const placeholders = cond.value.map(() => '?').join(',')
        whereParts.push(`${column} ${cond.operator === ConditionOperator.IN ? 'IN' : 'NOT IN'} (${placeholders})`)
        for (let j = 0; j < cond.value.length; j++) {
          args.push(this.toRdbValue(cond.value[j]))
        }
        continue
      }

      switch (cond.operator) {
        case ConditionOperator.EQUAL:
          whereParts.push(`${column} = ?`)
          args.push(this.toRdbValue(cond.value))
          break
        case ConditionOperator.NOT_EQUAL:
          whereParts.push(`${column} != ?`)
          args.push(this.toRdbValue(cond.value))
          break
        case ConditionOperator.GREATER:
          whereParts.push(`${column} > ?`)
          args.push(this.toRdbValue(cond.value))
          break
        case ConditionOperator.LESS:
          whereParts.push(`${column} < ?`)
          args.push(this.toRdbValue(cond.value))
          break
        case ConditionOperator.GREATER_EQUAL:
          whereParts.push(`${column} >= ?`)
          args.push(this.toRdbValue(cond.value))
          break
        case ConditionOperator.LESS_EQUAL:
          whereParts.push(`${column} <= ?`)
          args.push(this.toRdbValue(cond.value))
          break
        case ConditionOperator.LIKE:
          whereParts.push(`${column} LIKE ?`)
          args.push(cond.value === null || Array.isArray(cond.value) ? '' : String(cond.value))
          break
        case ConditionOperator.BETWEEN:
          whereParts.push(`${column} BETWEEN ? AND ?`)
          args.push(this.toRdbValue(cond.value))
          args.push(this.toRdbValue(cond.secondValue))
          break
        case ConditionOperator.IS_NULL:
          whereParts.push(`${column} IS NULL`)
          break
        case ConditionOperator.IS_NOT_NULL:
          whereParts.push(`${column} IS NOT NULL`)
          break
        default:
          throw new ExecutionError('WHERE', `不支持的条件操作符: ${String(cond.operator)}`)
      }
    }

    const whereClause = whereParts.length > 0 ? ` WHERE ${whereParts.join(' ')}` : ''
    return new QueryExecutorWhereClauseResult(whereClause, args)
  }

  escapeIdentifier(identifier: string): string {
    if (identifier === '*') {
      return identifier
    }
    const parts = identifier.split('.')
    const escapedParts: Array<string> = []
    for (let i = 0; i < parts.length; i++) {
      const part = parts[i].replace(/"/g, '""')
      escapedParts.push(`"${part}"`)
    }
    return escapedParts.join('.')
  }

  normalizeOrderDirection(direction: string): string {
    const normalized = direction.trim().toUpperCase()
    if (normalized === 'ASC' || normalized === 'DESC') {
      return normalized
    }
    throw new ExecutionError('ORDER BY', `非法排序方向: ${direction}`)
  }

  private buildSelectClause(): string {
    if (this.queryBuilder.hasSelectRaw()) {
      const expressions = this.queryBuilder.getSelectRawExpressions()
      return expressions.join(', ')
    }
    const selectedColumns = this.queryBuilder.getSelectedColumns()
    if (selectedColumns.length === 0) {
      return '*'
    }
    const escapedColumns: Array<string> = []
    for (let i = 0; i < selectedColumns.length; i++) {
      escapedColumns.push(this.escapeIdentifier(selectedColumns[i]))
    }
    return escapedColumns.join(', ')
  }

  private buildGroupByClause(): string {
    const groupByColumns = this.queryBuilder.getGroupByColumns()
    if (groupByColumns.length === 0) {
      return ''
    }
    return ` GROUP BY ${groupByColumns.map((column) => this.escapeIdentifier(column)).join(', ')}`
  }

  private buildOrderByClause(): string {
    const orderByColumns = this.queryBuilder.getOrderByColumns()
    if (orderByColumns.length === 0) {
      return ''
    }
    const parts = orderByColumns.map((orderBy) =>
      `${this.escapeIdentifier(orderBy.column)} ${this.normalizeOrderDirection(orderBy.direction)}`
    )
    return ` ORDER BY ${parts.join(', ')}`
  }
}
