import { relationalStore } from '@kit.ArkData'
import { DatabaseManager } from '../database/DatabaseManager'
import { Migration } from './Migration'
import { AutoMigrationHandler } from './AutoMigrationHandler'
import { MigrationLogService } from './MigrationLogService'
import { MigrationRegistry } from './MigrationRegistry'
import {
  AutoMigrationMode,
  AutoMigrationOptions,
  MigrationExecutionResult,
  MigrationManagerOptions,
  SchemaMigrationExecutionResult
} from './MigrationManagerTypes'
import { MigrationRunner } from './MigrationRunner'
import { MigrationVersionStore } from './MigrationVersionStore'
import { SchemaDiffer } from './SchemaDiffer'

export class MigrationManager {
  private currentVersion: number = 0
  private autoMigrationMode: AutoMigrationMode = AutoMigrationMode.SAFE
  private schemaDiffer: SchemaDiffer
  private registry: MigrationRegistry
  private runner: MigrationRunner
  private autoMigrationHandler: AutoMigrationHandler

  constructor(options?: MigrationManagerOptions) {
    if (options?.autoMigrationMode !== undefined) {
      this.autoMigrationMode = options.autoMigrationMode
    }
    this.schemaDiffer = options?.schemaDiffer ? options.schemaDiffer : new SchemaDiffer()
    this.registry = new MigrationRegistry()
    const logService = new MigrationLogService(options?.enableLog !== false, options?.logTableName)
    const versionStore = new MigrationVersionStore((version) => this.currentVersion = version)
    this.runner = new MigrationRunner(this.registry, logService, versionStore)
    this.autoMigrationHandler = new AutoMigrationHandler(this.schemaDiffer, logService, () => this.autoMigrationMode)
  }

  register(migration: Migration): void {
    this.registry.register(migration)
  }

  registerAll(migrations: Array<Migration>): void {
    this.registry.registerAll(migrations)
  }

  getMigrationsByOrder(): Array<Migration> {
    return this.registry.getMigrationsByOrder()
  }

  getPendingMigrations(currentVersion: number): Array<Migration> {
    return this.registry.getPendingMigrations(currentVersion)
  }

  getRollbackMigrations(currentVersion: number, targetVersion: number): Array<Migration> {
    return this.registry.getRollbackMigrations(currentVersion, targetVersion)
  }

  getLatestVersion(): number {
    return this.registry.getLatestVersion()
  }

  getMigration(version: number): Migration | null {
    return this.registry.getMigration(version)
  }

  getMigrationCount(): number {
    return this.registry.getMigrationCount()
  }

  hasPendingMigrations(currentVersion: number): boolean {
    return this.registry.hasPendingMigrations(currentVersion)
  }

  setCurrentVersion(version: number): void {
    this.currentVersion = version
  }

  getCurrentVersion(): number {
    return this.currentVersion
  }

  clear(): void {
    this.registry.clear()
    this.currentVersion = 0
  }

  getSummary(): string {
    const sorted = this.registry.getMigrationsByOrder()
    let summary = `已注册 ${this.registry.getMigrationCount()} 个迁移脚本\n`
    summary += `最新版本: ${this.registry.getLatestVersion()}\n`
    summary += `当前版本: ${this.currentVersion}\n\n迁移列表:\n`
    for (let i = 0; i < sorted.length; i++) {
      summary += `  v${sorted[i].version}: ${sorted[i].description}\n`
    }
    return summary
  }

  async getCurrentVersionFromDb(store: relationalStore.RdbStore): Promise<number> {
    return await this.runner.getCurrentVersionFromDb(store)
  }

  async migrateTo(store: relationalStore.RdbStore, targetVersion: number): Promise<MigrationExecutionResult> {
    return await this.runner.migrateTo(store, targetVersion)
  }

  async migrateToLatest(store: relationalStore.RdbStore): Promise<MigrationExecutionResult> {
    return await this.runner.migrateToLatest(store)
  }

  async autoMigrate(store: relationalStore.RdbStore, options?: AutoMigrationOptions): Promise<SchemaMigrationExecutionResult> {
    return await this.autoMigrationHandler.autoMigrate(store, options)
  }

  async migrateToWithManager(targetVersion: number): Promise<MigrationExecutionResult> {
    try {
      return await this.migrateTo(DatabaseManager.getInstance().getStore(), targetVersion)
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      return MigrationExecutionResult.createFailure(0, targetVersion, 0, [], errorMessage)
    }
  }

  async migrateToLatestWithManager(): Promise<MigrationExecutionResult> {
    try {
      return await this.migrateToLatest(DatabaseManager.getInstance().getStore())
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      return MigrationExecutionResult.createFailure(0, 0, 0, [], errorMessage)
    }
  }

  async autoMigrateWithManager(options?: AutoMigrationOptions): Promise<SchemaMigrationExecutionResult> {
    try {
      return await this.autoMigrate(DatabaseManager.getInstance().getStore(), options)
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      return this.autoMigrationHandler.createFailureResult(errorMessage)
    }
  }
}

export {
  MigrationExecutionResult,
  MigrationManagerOptions,
  AutoMigrationMode,
  AutoMigrationOptions,
  SchemaMigrationExecutionResult
} from './MigrationManagerTypes'
