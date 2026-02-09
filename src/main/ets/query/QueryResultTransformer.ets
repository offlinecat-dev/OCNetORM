import { relationalStore } from '@kit.ArkData'
import { DataMapper } from '../mapping/DataMapper'
import { EntityData } from '../mapping/EntityData'
import { ResultSetRow } from '../mapping/ResultSetRow'
import { Logger } from '../logging/Logger'

export type ResultSetRowMapper = (resultSet: relationalStore.ResultSet) => ResultSetRow

export class QueryResultTransformer {
  private dataMapper: DataMapper
  private logger: Logger
  private rowMapper: ResultSetRowMapper

  constructor(dataMapper: DataMapper, logger: Logger, rowMapper: ResultSetRowMapper) {
    this.dataMapper = dataMapper
    this.logger = logger
    this.rowMapper = rowMapper
  }

  transformInMainThread(resultSet: relationalStore.ResultSet): Array<EntityData> {
    const results: Array<EntityData> = []
    try {
      while (resultSet.goToNextRow()) {
        const row = this.rowMapper(resultSet)
        results.push(this.dataMapper.fromResultSetRow(row))
      }
    } catch (e) {
      const errorMessage = e instanceof Error ? e.message : String(e)
      this.logger.logError(`遍历结果集失败: ${errorMessage}`)
    }
    return results
  }

  async transformWithTaskPool(resultSet: relationalStore.ResultSet): Promise<Array<EntityData>> {
    const startTime = Date.now()
    try {
      const rawData = this.extractRawData(resultSet)
      const results: Array<EntityData> = []
      for (let i = 0; i < rawData.length; i++) {
        results.push(this.dataMapper.fromResultSetRow(rawData[i]))
      }

      const duration = Date.now() - startTime
      this.logger.logDebug(`TaskPool 数据转换完成，耗时: ${duration}ms`)
      return results
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      this.logger.logError(`TaskPool 执行失败，回退到主线程: ${errorMessage}`)

      try {
        resultSet.goToFirstRow()
      } catch (e) {
        return []
      }

      const results: Array<EntityData> = []
      if (resultSet.rowCount > 0) {
        const firstRow = this.rowMapper(resultSet)
        results.push(this.dataMapper.fromResultSetRow(firstRow))
        try {
          while (resultSet.goToNextRow()) {
            const row = this.rowMapper(resultSet)
            results.push(this.dataMapper.fromResultSetRow(row))
          }
        } catch (e) {
          const fallbackMessage = e instanceof Error ? e.message : String(e)
          this.logger.logError(`遍历结果集失败: ${fallbackMessage}`)
        }
      }
      return results
    }
  }

  private extractRawData(resultSet: relationalStore.ResultSet): Array<ResultSetRow> {
    const rows: Array<ResultSetRow> = []
    try {
      while (resultSet.goToNextRow()) {
        rows.push(this.rowMapper(resultSet))
      }
    } catch (e) {
      const errorMessage = e instanceof Error ? e.message : String(e)
      this.logger.logError(`提取原始数据失败: ${errorMessage}`)
    }
    return rows
  }
}
