import { SchemaChange, SchemaDiffResult, SchemaDiffer } from './SchemaDiffer'
import { MigrationResult } from './Migration'

export class MigrationExecutionResult {
  success: boolean = false
  fromVersion: number = 0
  toVersion: number = 0
  actualVersion: number = 0
  executedCount: number = 0
  results: Array<MigrationResult> = []
  errorMessage: string = ''

  static createSuccess(fromVersion: number, toVersion: number, results: Array<MigrationResult>): MigrationExecutionResult {
    const result = new MigrationExecutionResult()
    result.success = true
    result.fromVersion = fromVersion
    result.toVersion = toVersion
    result.actualVersion = toVersion
    result.executedCount = results.length
    result.results = results
    return result
  }

  static createFailure(
    fromVersion: number,
    toVersion: number,
    actualVersion: number,
    results: Array<MigrationResult>,
    errorMessage: string
  ): MigrationExecutionResult {
    const result = new MigrationExecutionResult()
    result.success = false
    result.fromVersion = fromVersion
    result.toVersion = toVersion
    result.actualVersion = actualVersion
    result.executedCount = results.length
    result.results = results
    result.errorMessage = errorMessage
    return result
  }
}

export enum AutoMigrationMode {
  SAFE = 'SAFE',
  FULL = 'FULL'
}

export interface AutoMigrationOptions {
  includeJoinTables?: boolean
  mode?: AutoMigrationMode
  logChanges?: boolean
}

export class SchemaMigrationExecutionResult {
  success: boolean = false
  executedCount: number = 0
  skippedCount: number = 0
  changes: Array<SchemaChange> = []
  skippedChanges: Array<SchemaChange> = []
  executedSql: Array<string> = []
  rollbackSql: Array<string> = []
  errorMessage: string = ''

  static createSuccess(
    diff: SchemaDiffResult,
    executedSql: Array<string>,
    skippedChanges: Array<SchemaChange>
  ): SchemaMigrationExecutionResult {
    const result = new SchemaMigrationExecutionResult()
    result.success = true
    result.executedCount = executedSql.length
    result.skippedCount = skippedChanges.length
    result.changes = diff.changes
    result.skippedChanges = skippedChanges
    result.executedSql = executedSql
    result.rollbackSql = diff.rollbackSql
    return result
  }

  static createFailure(
    diff: SchemaDiffResult,
    executedSql: Array<string>,
    skippedChanges: Array<SchemaChange>,
    errorMessage: string
  ): SchemaMigrationExecutionResult {
    const result = new SchemaMigrationExecutionResult()
    result.success = false
    result.executedCount = executedSql.length
    result.skippedCount = skippedChanges.length
    result.changes = diff.changes
    result.skippedChanges = skippedChanges
    result.executedSql = executedSql
    result.rollbackSql = diff.rollbackSql
    result.errorMessage = errorMessage
    return result
  }
}

export interface MigrationManagerOptions {
  enableLog?: boolean
  logTableName?: string
  autoMigrationMode?: AutoMigrationMode
  schemaDiffer?: SchemaDiffer
}
