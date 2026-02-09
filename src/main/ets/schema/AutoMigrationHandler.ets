import { relationalStore } from '@kit.ArkData'
import { MigrationLogService } from './MigrationLogService'
import { AutoMigrationMode, AutoMigrationOptions, SchemaMigrationExecutionResult } from './MigrationManagerTypes'
import { SchemaChange, SchemaDiffResult, SchemaDiffer } from './SchemaDiffer'

type DefaultModeProvider = () => AutoMigrationMode

export class AutoMigrationHandler {
  private schemaDiffer: SchemaDiffer
  private logService: MigrationLogService
  private getDefaultMode: DefaultModeProvider

  constructor(schemaDiffer: SchemaDiffer, logService: MigrationLogService, getDefaultMode: DefaultModeProvider) {
    this.schemaDiffer = schemaDiffer
    this.logService = logService
    this.getDefaultMode = getDefaultMode
  }

  async autoMigrate(store: relationalStore.RdbStore, options?: AutoMigrationOptions): Promise<SchemaMigrationExecutionResult> {
    const includeJoinTables = options?.includeJoinTables !== false
    const mode = options?.mode ? options.mode : this.getDefaultMode()
    const logChanges = options?.logChanges !== undefined ? options.logChanges : this.logService.isEnabled()
    const diff = await this.schemaDiffer.diff(store, { includeJoinTables })
    const executedSql: Array<string> = []
    if (!diff.hasChanges()) {
      return SchemaMigrationExecutionResult.createSuccess(diff, executedSql, [])
    }
    const changesToApply = mode === AutoMigrationMode.SAFE
      ? diff.changes.filter((change) => !change.destructive)
      : diff.changes
    const skippedChanges = diff.changes.filter((change) => changesToApply.indexOf(change) < 0)
    if (changesToApply.length === 0) {
      if (logChanges) {
        for (let i = 0; i < skippedChanges.length; i++) {
          await this.logService.safeLogSchemaChange(store, skippedChanges[i], false, '自动迁移跳过（破坏性变更）')
        }
      }
      return SchemaMigrationExecutionResult.createSuccess(diff, executedSql, skippedChanges)
    }
    let currentChange: SchemaChange | null = null
    let currentSql = ''
    try {
      store.beginTransaction()
      for (let i = 0; i < changesToApply.length; i++) {
        const change = changesToApply[i]
        currentChange = change
        for (let j = 0; j < change.sql.length; j++) {
          currentSql = change.sql[j]
          await store.executeSql(currentSql)
          executedSql.push(currentSql)
        }
      }
      store.commit()
      if (logChanges) {
        for (let i = 0; i < changesToApply.length; i++) {
          await this.logService.safeLogSchemaChange(store, changesToApply[i], true)
        }
        for (let i = 0; i < skippedChanges.length; i++) {
          await this.logService.safeLogSchemaChange(store, skippedChanges[i], false, '自动迁移跳过（破坏性变更）')
        }
      }
      return SchemaMigrationExecutionResult.createSuccess(diff, executedSql, skippedChanges)
    } catch (error) {
      const rollbackError = this.rollbackSafely(store)
      const errorMessage = error instanceof Error ? error.message : String(error)
      const finalError = this.mergeFailureMessage(errorMessage, rollbackError)
      if (logChanges && currentChange !== null) {
        await this.logService.safeLogSchemaChange(
          store, currentChange, false, '自动迁移执行失败', currentSql, finalError
        )
      }
      return SchemaMigrationExecutionResult.createFailure(diff, executedSql, skippedChanges, finalError)
    }
  }

  createFailureResult(errorMessage: string): SchemaMigrationExecutionResult {
    return SchemaMigrationExecutionResult.createFailure(new SchemaDiffResult(), [], [], errorMessage)
  }

  private rollbackSafely(store: relationalStore.RdbStore): string {
    try {
      store.rollBack()
      return ''
    } catch (error) {
      return error instanceof Error ? error.message : String(error)
    }
  }

  private mergeFailureMessage(errorMessage: string, rollbackErrorMessage: string): string {
    return rollbackErrorMessage ? `${errorMessage}; 回滚失败: ${rollbackErrorMessage}` : errorMessage
  }
}

