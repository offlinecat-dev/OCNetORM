import { relationalStore } from '@kit.ArkData'
import { Migration, MigrationDirection, MigrationResult } from './Migration'
import { MigrationLogRecord } from './MigrationLogManager'
import { MigrationLogService } from './MigrationLogService'

export class MigrationStepExecutor {
  private logService: MigrationLogService

  constructor(logService: MigrationLogService) {
    this.logService = logService
  }

  async runOneMigration(
    store: relationalStore.RdbStore,
    migration: Migration,
    direction: MigrationDirection,
    results: Array<MigrationResult>,
    successLogs: Array<MigrationLogRecord>
  ): Promise<string | null> {
    const startTime = Date.now()
    try {
      if (direction === MigrationDirection.UP) {
        await migration.up(store)
      } else {
        await migration.down(store)
      }
      results.push(new MigrationResult(migration.version, true, Date.now() - startTime))
      successLogs.push({
        version: migration.version,
        name: migration.description,
        type: 'MIGRATION',
        direction,
        summary: `${direction === MigrationDirection.UP ? '迁移' : '回滚'} v${migration.version} 执行成功`,
        success: true
      })
      return null
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      results.push(new MigrationResult(migration.version, false, Date.now() - startTime, errorMessage))
      const rollbackError = this.rollbackSafely(store)
      const finalError = this.mergeFailureMessage(errorMessage, rollbackError)
      await this.logService.safeLog(store, {
        version: migration.version,
        name: migration.description,
        type: 'MIGRATION',
        direction,
        summary: `${direction === MigrationDirection.UP ? '迁移' : '回滚'} v${migration.version} 执行失败`,
        success: false,
        errorMessage: finalError
      })
      return finalError
    }
  }

  rollbackSafely(store: relationalStore.RdbStore): string {
    try {
      store.rollBack()
      return ''
    } catch (error) {
      return error instanceof Error ? error.message : String(error)
    }
  }

  mergeFailureMessage(errorMessage: string, rollbackErrorMessage: string): string {
    return rollbackErrorMessage ? `${errorMessage}; 回滚失败: ${rollbackErrorMessage}` : errorMessage
  }
}

