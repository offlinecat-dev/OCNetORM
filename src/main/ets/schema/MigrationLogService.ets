import { relationalStore } from '@kit.ArkData'
import { MigrationDirection } from './Migration'
import { MigrationLogManager, MigrationLogRecord } from './MigrationLogManager'
import { SchemaChange } from './SchemaDiffer'

export class MigrationLogService {
  private enableLog: boolean = true
  private logManager: MigrationLogManager | null = null

  constructor(enableLog: boolean, logTableName?: string) {
    this.enableLog = enableLog
    if (enableLog) {
      this.logManager = new MigrationLogManager(logTableName)
    }
  }

  isEnabled(): boolean {
    return this.enableLog
  }

  async safeLog(store: relationalStore.RdbStore, record: MigrationLogRecord): Promise<void> {
    if (!this.enableLog || this.logManager === null) {
      return
    }
    try {
      await this.logManager.log(store, record)
    } catch (error) {
      // ignore log failure
    }
  }

  async safeLogBatch(store: relationalStore.RdbStore, records: Array<MigrationLogRecord>): Promise<void> {
    if (records.length === 0) {
      return
    }
    for (let i = 0; i < records.length; i++) {
      await this.safeLog(store, records[i])
    }
  }

  async safeLogSchemaChange(
    store: relationalStore.RdbStore,
    change: SchemaChange,
    success: boolean,
    summaryOverride?: string,
    sqlOverride?: string,
    errorMessage?: string
  ): Promise<void> {
    const summary = summaryOverride ? summaryOverride : change.summary
    const sql = sqlOverride ? sqlOverride : change.sql.join(' \n')
    await this.safeLog(store, {
      type: 'AUTO_SCHEMA',
      direction: MigrationDirection.UP,
      tableName: change.tableName,
      columnName: change.columnName,
      sql,
      summary,
      success,
      errorMessage
    })
  }
}

