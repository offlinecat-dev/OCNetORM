import { QueryBuilder } from './QueryBuilder'
import { EntityData } from '../mapping/EntityData'
import { ResultSetRow } from '../mapping/ResultSetRow'
import { ValueType } from '../types/ValueTypes'
import { compareOrderValues as compareOrderValuesUtil } from './QueryExecutionUtils'

class QueryExecutorOrderDefinition {
  propertyName: string
  direction: string

  constructor(propertyName: string, direction: string) {
    this.propertyName = propertyName
    this.direction = direction
  }
}

export class QueryExecutorOrderSupport {
  private queryBuilder: QueryBuilder

  constructor(queryBuilder: QueryBuilder) {
    this.queryBuilder = queryBuilder
  }

  ensurePrimaryKeySelected(selectedColumns: Array<string>): Array<string> {
    if (selectedColumns.length === 0) {
      return selectedColumns
    }
    const metadata = this.queryBuilder.getEntityMetadata()
    const pkColumn = metadata.getPrimaryKeyColumn()
    if (pkColumn === null) {
      return selectedColumns
    }
    if (selectedColumns.includes(pkColumn.columnName)) {
      return selectedColumns
    }
    const columns: Array<string> = []
    for (let i = 0; i < selectedColumns.length; i++) {
      columns.push(selectedColumns[i])
    }
    columns.push(pkColumn.columnName)
    return columns
  }

  ensureOrderBySelected(selectedColumns: Array<string>): Array<string> {
    if (selectedColumns.length === 0) {
      return selectedColumns
    }
    const orderByColumns = this.queryBuilder.getOrderByColumns()
    if (orderByColumns.length === 0) {
      return selectedColumns
    }
    const columns: Array<string> = []
    for (let i = 0; i < selectedColumns.length; i++) {
      columns.push(selectedColumns[i])
    }
    for (let i = 0; i < orderByColumns.length; i++) {
      const columnName = orderByColumns[i].column
      if (!columns.includes(columnName)) {
        columns.push(columnName)
      }
    }
    return columns
  }

  sortResultsByOrder(results: Array<EntityData>): Array<EntityData> {
    const orderByColumns = this.queryBuilder.getOrderByColumns()
    if (orderByColumns.length === 0 || results.length <= 1) {
      return results
    }
    const metadata = this.queryBuilder.getEntityMetadata()
    const orderDefs: Array<QueryExecutorOrderDefinition> = []
    for (let i = 0; i < orderByColumns.length; i++) {
      const columnName = orderByColumns[i].column
      const columnMeta = metadata.getColumnByName(columnName) ?? metadata.getColumnByProperty(columnName)
      const propertyName = columnMeta ? columnMeta.propertyName : columnName
      orderDefs.push(new QueryExecutorOrderDefinition(propertyName, String(orderByColumns[i].direction)))
    }
    results.sort((left, right) => {
      for (let i = 0; i < orderDefs.length; i++) {
        const def = orderDefs[i]
        const aValue = left.getPropertyValue(def.propertyName)
        const bValue = right.getPropertyValue(def.propertyName)
        const cmp = compareOrderValuesUtil(aValue, bValue, def.direction)
        if (cmp !== 0) {
          return cmp
        }
      }
      return 0
    })
    return results
  }

  sortRowsByOrder(rows: Array<ResultSetRow>): Array<ResultSetRow> {
    const orderByColumns = this.queryBuilder.getOrderByColumns()
    if (orderByColumns.length === 0 || rows.length <= 1) {
      return rows
    }
    rows.sort((left, right) => {
      for (let i = 0; i < orderByColumns.length; i++) {
        const columnName = orderByColumns[i].column
        const aValue = left.get(columnName) as ValueType
        const bValue = right.get(columnName) as ValueType
        const cmp = compareOrderValuesUtil(aValue, bValue, String(orderByColumns[i].direction))
        if (cmp !== 0) {
          return cmp
        }
      }
      return 0
    })
    return rows
  }

  canSortRawByOrder(): boolean {
    const orderByColumns = this.queryBuilder.getOrderByColumns()
    if (orderByColumns.length === 0) {
      return true
    }
    const selectedColumns = this.queryBuilder.getSelectedColumns()
    if (selectedColumns.length === 0) {
      return true
    }
    for (let i = 0; i < orderByColumns.length; i++) {
      if (!selectedColumns.includes(orderByColumns[i].column)) {
        return false
      }
    }
    return true
  }
}
