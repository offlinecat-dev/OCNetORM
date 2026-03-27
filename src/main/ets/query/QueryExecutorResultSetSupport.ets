import { relationalStore } from '@kit.ArkData'
import { QueryBuilder } from './QueryBuilder'
import { EntityData } from '../mapping/EntityData'
import { ResultSetRow } from '../mapping/ResultSetRow'
import { ResultSetUtils } from '../mapping/ResultSetUtils'
import { ColumnType } from '../types/ColumnType'
import { ValueType } from '../types/ValueTypes'

export class QueryExecutorResultSetSupport {
  private queryBuilder: QueryBuilder

  constructor(queryBuilder: QueryBuilder) {
    this.queryBuilder = queryBuilder
  }

  resultSetToRow(resultSet: relationalStore.ResultSet): ResultSetRow {
    const row = new ResultSetRow()
    const columnNames = resultSet.columnNames
    const metadata = this.queryBuilder.getEntityMetadata()

    for (let i = 0; i < columnNames.length; i++) {
      const columnName = columnNames[i]
      try {
        const columnIndex = resultSet.getColumnIndex(columnName)
        if (resultSet.isColumnNull(columnIndex)) {
          row.set(columnName, null)
        } else {
          const columnMetadata = metadata.getColumnByName(columnName)
          if (columnMetadata !== null) {
            switch (columnMetadata.columnType) {
              case ColumnType.INTEGER:
                row.set(columnName, resultSet.getLong(columnIndex))
                break
              case ColumnType.REAL:
                row.set(columnName, resultSet.getDouble(columnIndex))
                break
              case ColumnType.TEXT:
                row.set(columnName, resultSet.getString(columnIndex))
                break
              case ColumnType.BLOB:
                row.set(columnName, resultSet.getBlob(columnIndex))
                break
              default:
                row.set(columnName, resultSet.getString(columnIndex))
            }
          } else {
            row.set(columnName, resultSet.getString(columnIndex))
          }
        }
      } catch (e) {
        row.set(columnName, null)
      }
    }

    return row
  }

  resultSetToRawRow(resultSet: relationalStore.ResultSet): ResultSetRow {
    const row = new ResultSetRow()
    const columnNames = resultSet.columnNames
    for (let i = 0; i < columnNames.length; i++) {
      const columnName = columnNames[i]
      try {
        const columnIndex = resultSet.getColumnIndex(columnName)
        row.set(columnName, ResultSetUtils.getValueByRuntimeType(resultSet, columnIndex))
      } catch (e) {
        row.set(columnName, null)
      }
    }
    return row
  }

  resultSetToDynamicEntity(resultSet: relationalStore.ResultSet, entityName: string): EntityData {
    const entity = new EntityData(entityName)
    const columnNames = resultSet.columnNames
    for (let i = 0; i < columnNames.length; i++) {
      const columnName = columnNames[i]
      let value: ValueType = null
      try {
        const columnIndex = resultSet.getColumnIndex(columnName)
        if (!resultSet.isColumnNull(columnIndex)) {
          value = ResultSetUtils.getValueByRuntimeType(resultSet, columnIndex) as ValueType
        }
      } catch (e) {
        value = null
      }
      entity.addProperty(columnName, value, this.resolveValueTypeName(value))
    }
    return entity
  }

  private resolveValueTypeName(value: ValueType): string {
    if (value === null) {
      return 'null'
    }
    if (value instanceof Uint8Array) {
      return 'blob'
    }
    return typeof value
  }
}
