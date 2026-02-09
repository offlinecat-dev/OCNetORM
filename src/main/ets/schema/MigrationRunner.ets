import { relationalStore } from '@kit.ArkData'
import { Migration, MigrationDirection, MigrationResult } from './Migration'
import { MigrationLogRecord } from './MigrationLogManager'
import { MigrationExecutionResult } from './MigrationManagerTypes'
import { MigrationLogService } from './MigrationLogService'
import { MigrationRegistry } from './MigrationRegistry'
import { MigrationStepExecutor } from './MigrationStepExecutor'
import { MigrationVersionStore } from './MigrationVersionStore'

export class MigrationRunner {
  private registry: MigrationRegistry
  private logService: MigrationLogService
  private stepExecutor: MigrationStepExecutor
  private versionStore: MigrationVersionStore

  constructor(registry: MigrationRegistry, logService: MigrationLogService, versionStore: MigrationVersionStore) {
    this.registry = registry
    this.logService = logService
    this.stepExecutor = new MigrationStepExecutor(logService)
    this.versionStore = versionStore
  }

  async getCurrentVersionFromDb(store: relationalStore.RdbStore): Promise<number> {
    return await this.versionStore.getCurrentVersionFromDb(store)
  }

  async migrateTo(store: relationalStore.RdbStore, targetVersion: number): Promise<MigrationExecutionResult> {
    const currentVersion = await this.getCurrentVersionFromDb(store)
    const results: Array<MigrationResult> = []
    const successLogs: Array<MigrationLogRecord> = []
    let transactionActive = false
    if (targetVersion === currentVersion) {
      return MigrationExecutionResult.createSuccess(currentVersion, targetVersion, results)
    }
    try {
      store.beginTransaction()
      transactionActive = true
      const failure = targetVersion > currentVersion
        ? await this.runUpgrade(store, currentVersion, targetVersion, results, successLogs)
        : await this.runRollback(store, currentVersion, targetVersion, results, successLogs)
      if (failure !== null) {
        return failure
      }
      await this.versionStore.updateVersionInDb(store, targetVersion)
      store.commit()
      transactionActive = false
      await this.logService.safeLogBatch(store, successLogs)
      return MigrationExecutionResult.createSuccess(currentVersion, targetVersion, results)
    } catch (error) {
      const rollbackError = transactionActive ? this.stepExecutor.rollbackSafely(store) : ''
      const errorMessage = error instanceof Error ? error.message : String(error)
      const finalError = this.stepExecutor.mergeFailureMessage(errorMessage, rollbackError)
      await this.logService.safeLog(store, {
        type: 'MIGRATION',
        direction: targetVersion > currentVersion ? MigrationDirection.UP : MigrationDirection.DOWN,
        summary: '迁移事务执行失败',
        success: false,
        errorMessage: finalError
      })
      return MigrationExecutionResult.createFailure(currentVersion, targetVersion, currentVersion, results, finalError)
    }
  }

  async migrateToLatest(store: relationalStore.RdbStore): Promise<MigrationExecutionResult> {
    return await this.migrateTo(store, this.registry.getLatestVersion())
  }

  private async runUpgrade(
    store: relationalStore.RdbStore,
    currentVersion: number,
    targetVersion: number,
    results: Array<MigrationResult>,
    successLogs: Array<MigrationLogRecord>
  ): Promise<MigrationExecutionResult | null> {
    const pending = this.registry.getPendingMigrations(currentVersion)
    for (let i = 0; i < pending.length; i++) {
      const migration = pending[i]
      if (migration.version > targetVersion) {
        continue
      }
      const failed = await this.stepExecutor.runOneMigration(store, migration, MigrationDirection.UP, results, successLogs)
      if (failed === null) {
        continue
      }
      return MigrationExecutionResult.createFailure(
        currentVersion, targetVersion, currentVersion, results,
        `迁移 v${migration.version} 失败: ${failed}`
      )
    }
    return null
  }

  private async runRollback(
    store: relationalStore.RdbStore,
    currentVersion: number,
    targetVersion: number,
    results: Array<MigrationResult>,
    successLogs: Array<MigrationLogRecord>
  ): Promise<MigrationExecutionResult | null> {
    const rollback = this.registry.getRollbackMigrations(currentVersion, targetVersion)
    for (let i = 0; i < rollback.length; i++) {
      const migration = rollback[i]
      const failed = await this.stepExecutor.runOneMigration(store, migration, MigrationDirection.DOWN, results, successLogs)
      if (failed === null) {
        continue
      }
      return MigrationExecutionResult.createFailure(
        currentVersion, targetVersion, currentVersion, results,
        `回滚 v${migration.version} 失败: ${failed}`
      )
    }
    return null
  }
}

