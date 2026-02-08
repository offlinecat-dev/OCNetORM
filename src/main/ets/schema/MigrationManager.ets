/**
 * 数据库迁移管理器
 * 负责注册、排序和执行迁移脚本
 */

import { relationalStore } from '@kit.ArkData'
import { Migration, MigrationDirection, MigrationResult } from './Migration'
import { MigrationLogManager, MigrationLogRecord } from './MigrationLogManager'
import { SchemaChange, SchemaDiffResult, SchemaDiffer } from './SchemaDiffer'
import { DatabaseManager } from '../database/DatabaseManager'
import { ExecutionError } from '../errors/DatabaseError'

/**
 * 迁移执行结果汇总
 */
export class MigrationExecutionResult {
  /** 是否全部成功 */
  success: boolean = false
  /** 起始版本 */
  fromVersion: number = 0
  /** 目标版本 */
  toVersion: number = 0
  /** 实际到达的版本 */
  actualVersion: number = 0
  /** 执行的迁移数量 */
  executedCount: number = 0
  /** 各迁移的执行结果 */
  results: Array<MigrationResult> = []
  /** 错误信息 */
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

  static createFailure(fromVersion: number, toVersion: number, actualVersion: number,
    results: Array<MigrationResult>, errorMessage: string): MigrationExecutionResult {
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

/**
 * 自动迁移模式
 */
export enum AutoMigrationMode {
  /** 仅允许非破坏性变更（新增表/列） */
  SAFE = 'SAFE',
  /** 允许重建表等破坏性变更 */
  FULL = 'FULL'
}

/**
 * 自动迁移选项
 */
export interface AutoMigrationOptions {
  /** 是否包含多对多中间表 */
  includeJoinTables?: boolean
  /** 自动迁移模式 */
  mode?: AutoMigrationMode
  /** 是否记录日志（默认跟随 MigrationManager.enableLog） */
  logChanges?: boolean
}

/**
 * 自动迁移执行结果
 */
export class SchemaMigrationExecutionResult {
  /** 是否全部成功 */
  success: boolean = false
  /** 执行的 SQL 数量 */
  executedCount: number = 0
  /** 跳过的变更数量 */
  skippedCount: number = 0
  /** 全部变更 */
  changes: Array<SchemaChange> = []
  /** 跳过的变更 */
  skippedChanges: Array<SchemaChange> = []
  /** 执行的 SQL */
  executedSql: Array<string> = []
  /** 回滚建议 SQL */
  rollbackSql: Array<string> = []
  /** 错误信息 */
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

/**
 * 迁移管理器配置
 */
export interface MigrationManagerOptions {
  /** 是否记录迁移日志，默认 true */
  enableLog?: boolean
  /** 自定义日志表名 */
  logTableName?: string
  /** 默认自动迁移模式 */
  autoMigrationMode?: AutoMigrationMode
  /** 自定义 SchemaDiffer */
  schemaDiffer?: SchemaDiffer
}

/**
 * 迁移管理器
 * 管理数据库版本迁移
 */
export class MigrationManager {
  /** 已注册的迁移脚本列表 */
  private migrations: Array<Migration> = []

  /** 当前数据库版本（内存中的版本，实际版本需要从数据库读取） */
  private currentVersion: number = 0

  /** 是否启用迁移日志 */
  private enableLog: boolean = true

  /** 迁移日志管理器 */
  private logManager: MigrationLogManager | null = null

  /** Schema 差异分析器 */
  private schemaDiffer: SchemaDiffer

  /** 默认自动迁移模式 */
  private autoMigrationMode: AutoMigrationMode = AutoMigrationMode.SAFE

  constructor(options?: MigrationManagerOptions) {
    this.enableLog = options?.enableLog !== false
    if (this.enableLog) {
      this.logManager = new MigrationLogManager(options?.logTableName)
    }
    this.schemaDiffer = options?.schemaDiffer ? options.schemaDiffer : new SchemaDiffer()
    if (options?.autoMigrationMode !== undefined) {
      this.autoMigrationMode = options.autoMigrationMode
    }
  }

  private closeResultSet(resultSet: relationalStore.ResultSet | null): void {
    if (resultSet === null) {
      return
    }
    try {
      resultSet.close()
    } catch (e) {
      // ignore
    }
  }

  /**
   * 注册迁移脚本
   * @param migration 迁移脚本
   * @throws Error 如果版本号已存在
   */
  register(migration: Migration): void {
    // 检查版本号是否已存在
    for (let i = 0; i < this.migrations.length; i++) {
      if (this.migrations[i].version === migration.version) {
        throw new Error(`迁移版本 ${migration.version} 已存在`)
      }
    }

    this.migrations.push(migration)
  }

  /**
   * 批量注册迁移脚本
   * @param migrations 迁移脚本数组
   */
  registerAll(migrations: Array<Migration>): void {
    for (let i = 0; i < migrations.length; i++) {
      try {
        this.register(migrations[i])
      } catch (e) {
        // 忽略重复版本错误，继续注册其他迁移
      }
    }
  }

  /**
   * 获取按版本号升序排列的迁移脚本
   * @returns 排序后的迁移脚本数组
   */
  getMigrationsByOrder(): Array<Migration> {
    const sorted = this.migrations.slice()
    sorted.sort((left: Migration, right: Migration) => left.version - right.version)

    return sorted
  }

  /**
   * 获取待执行的迁移脚本（版本号大于当前版本）
   * @param currentVersion 当前数据库版本
   * @returns 待执行的迁移脚本数组（已排序）
   */
  getPendingMigrations(currentVersion: number): Array<Migration> {
    const sorted = this.getMigrationsByOrder()
    const pending: Array<Migration> = []

    for (let i = 0; i < sorted.length; i++) {
      if (sorted[i].version > currentVersion) {
        pending.push(sorted[i])
      }
    }

    return pending
  }

  /**
   * 获取需要回滚的迁移脚本（版本号大于目标版本且小于等于当前版本）
   * @param currentVersion 当前数据库版本
   * @param targetVersion 目标版本
   * @returns 需要回滚的迁移脚本数组（按版本号降序）
   */
  getRollbackMigrations(currentVersion: number, targetVersion: number): Array<Migration> {
    const sorted = this.getMigrationsByOrder()
    const rollback: Array<Migration> = []

    // 收集需要回滚的迁移
    for (let i = 0; i < sorted.length; i++) {
      const migration = sorted[i]
      if (migration.version > targetVersion && migration.version <= currentVersion) {
        rollback.push(migration)
      }
    }

    // 反转数组，使其按版本号降序排列
    const reversed: Array<Migration> = []
    for (let i = rollback.length - 1; i >= 0; i--) {
      reversed.push(rollback[i])
    }

    return reversed
  }

  /**
   * 获取最新版本号
   * @returns 最新版本号，如果没有迁移脚本返回 0
   */
  getLatestVersion(): number {
    if (this.migrations.length === 0) {
      return 0
    }

    let maxVersion = 0
    for (let i = 0; i < this.migrations.length; i++) {
      if (this.migrations[i].version > maxVersion) {
        maxVersion = this.migrations[i].version
      }
    }

    return maxVersion
  }

  /**
   * 获取指定版本的迁移脚本
   * @param version 版本号
   * @returns 迁移脚本，如果不存在返回 null
   */
  getMigration(version: number): Migration | null {
    for (let i = 0; i < this.migrations.length; i++) {
      if (this.migrations[i].version === version) {
        return this.migrations[i]
      }
    }
    return null
  }

  /**
   * 获取已注册的迁移脚本数量
   * @returns 迁移脚本数量
   */
  getMigrationCount(): number {
    return this.migrations.length
  }

  /**
   * 检查是否有待执行的迁移
   * @param currentVersion 当前数据库版本
   * @returns 是否有待执行的迁移
   */
  hasPendingMigrations(currentVersion: number): boolean {
    return this.getPendingMigrations(currentVersion).length > 0
  }

  /**
   * 设置当前版本（用于测试）
   * @param version 版本号
   */
  setCurrentVersion(version: number): void {
    this.currentVersion = version
  }

  /**
   * 获取当前版本
   * @returns 当前版本号
   */
  getCurrentVersion(): number {
    return this.currentVersion
  }

  /**
   * 清除所有已注册的迁移脚本（主要用于测试）
   */
  clear(): void {
    this.migrations = []
    this.currentVersion = 0
  }

  /**
   * 获取迁移信息摘要
   * @returns 迁移信息字符串
   */
  getSummary(): string {
    const sorted = this.getMigrationsByOrder()
    let summary = `已注册 ${this.migrations.length} 个迁移脚本\n`
    summary += `最新版本: ${this.getLatestVersion()}\n`
    summary += `当前版本: ${this.currentVersion}\n\n`
    summary += '迁移列表:\n'

    for (let i = 0; i < sorted.length; i++) {
      const m = sorted[i]
      summary += `  v${m.version}: ${m.description}\n`
    }

    return summary
  }

  // ==================== 数据库执行方法 ====================

  /** 版本表名 */
  private static readonly VERSION_TABLE = '_orm_version'

  /**
   * 从数据库获取当前版本号
   * @param store RdbStore 实例
   * @returns Promise<number> 当前版本号
   */
  async getCurrentVersionFromDb(store: relationalStore.RdbStore): Promise<number> {
    try {
      // 确保版本表存在
      await this.ensureVersionTable(store)

      // 查询当前版本
      const predicates = new relationalStore.RdbPredicates(MigrationManager.VERSION_TABLE)
      let resultSet: relationalStore.ResultSet | null = null
      try {
        resultSet = await store.query(predicates)

        if (resultSet.goToFirstRow()) {
          const versionIndex = resultSet.getColumnIndex('version')
          const version = resultSet.getLong(versionIndex)
          this.currentVersion = version
          return version
        }

        return 0
      } finally {
        this.closeResultSet(resultSet)
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      throw new ExecutionError('SELECT', `获取数据库版本失败: ${errorMessage}`)
    }
  }

  /**
   * 确保版本表存在
   * @param store RdbStore 实例
   */
  private async ensureVersionTable(store: relationalStore.RdbStore): Promise<void> {
    const createTableSql = `CREATE TABLE IF NOT EXISTS ${MigrationManager.VERSION_TABLE} (
      id INTEGER PRIMARY KEY,
      version INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER NOT NULL
    )`

    try {
      await store.executeSql(createTableSql)

      // 检查是否有记录，如果没有则插入初始记录
      const predicates = new relationalStore.RdbPredicates(MigrationManager.VERSION_TABLE)
      let resultSet: relationalStore.ResultSet | null = null
      let hasRecord = false
      try {
        resultSet = await store.query(predicates)
        hasRecord = resultSet.goToFirstRow()
      } finally {
        this.closeResultSet(resultSet)
      }

      if (!hasRecord) {
        const insertValues: relationalStore.ValuesBucket = {
          'id': 1,
          'version': 0,
          'updated_at': Date.now()
        }
        await store.insert(MigrationManager.VERSION_TABLE, insertValues)
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      throw new ExecutionError('CREATE TABLE', `创建版本表失败: ${errorMessage}`)
    }
  }

  /**
   * 更新数据库版本号
   * @param store RdbStore 实例
   * @param version 新版本号
   */
  private async updateVersionInDb(store: relationalStore.RdbStore, version: number): Promise<void> {
    try {
      const predicates = new relationalStore.RdbPredicates(MigrationManager.VERSION_TABLE)
      predicates.equalTo('id', 1)

      const updateValues: relationalStore.ValuesBucket = {
        'version': version,
        'updated_at': Date.now()
      }

      await store.update(updateValues, predicates)
      this.currentVersion = version
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      throw new ExecutionError('UPDATE', `更新数据库版本失败: ${errorMessage}`)
    }
  }

  /**
   * 执行迁移到指定版本
   * @param store RdbStore 实例
   * @param targetVersion 目标版本号
   * @returns Promise<MigrationExecutionResult>
   */
  async migrateTo(store: relationalStore.RdbStore, targetVersion: number): Promise<MigrationExecutionResult> {
    const currentVersion = await this.getCurrentVersionFromDb(store)
    const results: Array<MigrationResult> = []
    const successLogRecords: Array<MigrationLogRecord> = []
    let transactionActive = false

    if (targetVersion === currentVersion) {
      return MigrationExecutionResult.createSuccess(currentVersion, targetVersion, results)
    }

    try {
      // 开始事务
      store.beginTransaction()
      transactionActive = true

      if (targetVersion > currentVersion) {
        // 升级
        const pendingMigrations = this.getPendingMigrations(currentVersion)
        const migrationsToRun: Array<Migration> = []

        for (let i = 0; i < pendingMigrations.length; i++) {
          if (pendingMigrations[i].version <= targetVersion) {
            migrationsToRun.push(pendingMigrations[i])
          }
        }

        for (let i = 0; i < migrationsToRun.length; i++) {
          const migration = migrationsToRun[i]
          const startTime = Date.now()

          try {
            await migration.up(store)
            const executionTime = Date.now() - startTime
            results.push(new MigrationResult(migration.version, true, executionTime))
            successLogRecords.push({
              version: migration.version,
              name: migration.description,
              type: 'MIGRATION',
              direction: MigrationDirection.UP,
              summary: `迁移 v${migration.version} 执行成功`,
              success: true
            })
          } catch (error) {
            const executionTime = Date.now() - startTime
            const errorMessage = error instanceof Error ? error.message : String(error)
            results.push(new MigrationResult(migration.version, false, executionTime, errorMessage))

            const rollbackErrorMessage = this.rollbackSafely(store)
            const finalErrorMessage = this.mergeFailureMessage(errorMessage, rollbackErrorMessage)
            await this.safeLog(store, {
              version: migration.version,
              name: migration.description,
              type: 'MIGRATION',
              direction: MigrationDirection.UP,
              summary: `迁移 v${migration.version} 执行失败`,
              success: false,
              errorMessage: finalErrorMessage
            })
            return MigrationExecutionResult.createFailure(
              currentVersion, targetVersion, currentVersion, results,
              `迁移 v${migration.version} 失败: ${finalErrorMessage}`
            )
          }
        }
      } else {
        // 回滚
        const rollbackMigrations = this.getRollbackMigrations(currentVersion, targetVersion)

        for (let i = 0; i < rollbackMigrations.length; i++) {
          const migration = rollbackMigrations[i]
          const startTime = Date.now()

          try {
            await migration.down(store)
            const executionTime = Date.now() - startTime
            results.push(new MigrationResult(migration.version, true, executionTime))
            successLogRecords.push({
              version: migration.version,
              name: migration.description,
              type: 'MIGRATION',
              direction: MigrationDirection.DOWN,
              summary: `回滚 v${migration.version} 执行成功`,
              success: true
            })
          } catch (error) {
            const executionTime = Date.now() - startTime
            const errorMessage = error instanceof Error ? error.message : String(error)
            results.push(new MigrationResult(migration.version, false, executionTime, errorMessage))

            const rollbackErrorMessage = this.rollbackSafely(store)
            const finalErrorMessage = this.mergeFailureMessage(errorMessage, rollbackErrorMessage)
            await this.safeLog(store, {
              version: migration.version,
              name: migration.description,
              type: 'MIGRATION',
              direction: MigrationDirection.DOWN,
              summary: `回滚 v${migration.version} 执行失败`,
              success: false,
              errorMessage: finalErrorMessage
            })
            return MigrationExecutionResult.createFailure(
              currentVersion, targetVersion, currentVersion, results,
              `回滚 v${migration.version} 失败: ${finalErrorMessage}`
            )
          }
        }
      }

      // 更新版本号
      await this.updateVersionInDb(store, targetVersion)

      // 提交事务
      store.commit()
      transactionActive = false
      await this.safeLogBatch(store, successLogRecords)

      return MigrationExecutionResult.createSuccess(currentVersion, targetVersion, results)
    } catch (error) {
      const rollbackErrorMessage = transactionActive ? this.rollbackSafely(store) : ''
      const errorMessage = error instanceof Error ? error.message : String(error)
      const finalErrorMessage = this.mergeFailureMessage(errorMessage, rollbackErrorMessage)
      await this.safeLog(store, {
        type: 'MIGRATION',
        direction: targetVersion > currentVersion ? MigrationDirection.UP : MigrationDirection.DOWN,
        summary: '迁移事务执行失败',
        success: false,
        errorMessage: finalErrorMessage
      })
      return MigrationExecutionResult.createFailure(
        currentVersion, targetVersion, currentVersion, results, finalErrorMessage
      )
    }
  }

  /**
   * 执行所有待执行的迁移（迁移到最新版本）
   * @param store RdbStore 实例
   * @returns Promise<MigrationExecutionResult>
   */
  async migrateToLatest(store: relationalStore.RdbStore): Promise<MigrationExecutionResult> {
    const latestVersion = this.getLatestVersion()
    return await this.migrateTo(store, latestVersion)
  }

  /**
   * 自动执行 Schema 迁移
   * @param store RdbStore 实例
   * @param options 自动迁移选项
   */
  async autoMigrate(store: relationalStore.RdbStore, options?: AutoMigrationOptions): Promise<SchemaMigrationExecutionResult> {
    const includeJoinTables = options?.includeJoinTables !== false
    const mode = options?.mode ? options.mode : this.autoMigrationMode
    const logChanges = options?.logChanges !== undefined ? options.logChanges : this.enableLog
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
          await this.safeLogSchemaChange(store, skippedChanges[i], false, '自动迁移跳过（破坏性变更）')
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
          const sql = change.sql[j]
          currentSql = sql
          await store.executeSql(sql)
          executedSql.push(sql)
        }
      }

      store.commit()

      if (logChanges) {
        for (let i = 0; i < changesToApply.length; i++) {
          const change = changesToApply[i]
          await this.safeLogSchemaChange(store, change, true)
        }
        for (let i = 0; i < skippedChanges.length; i++) {
          await this.safeLogSchemaChange(store, skippedChanges[i], false, '自动迁移跳过（破坏性变更）')
        }
      }

      return SchemaMigrationExecutionResult.createSuccess(diff, executedSql, skippedChanges)
    } catch (error) {
      const rollbackErrorMessage = this.rollbackSafely(store)
      const errorMessage = error instanceof Error ? error.message : String(error)
      const finalErrorMessage = this.mergeFailureMessage(errorMessage, rollbackErrorMessage)
      if (logChanges && currentChange !== null) {
        await this.safeLogSchemaChange(store, currentChange, false, '自动迁移执行失败', currentSql, finalErrorMessage)
      }
      return SchemaMigrationExecutionResult.createFailure(diff, executedSql, skippedChanges, finalErrorMessage)
    }
  }

  /**
   * 使用 DatabaseManager 执行迁移到指定版本
   * @param targetVersion 目标版本号
   * @returns Promise<MigrationExecutionResult>
   */
  async migrateToWithManager(targetVersion: number): Promise<MigrationExecutionResult> {
    try {
      const store = DatabaseManager.getInstance().getStore()
      return await this.migrateTo(store, targetVersion)
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      return MigrationExecutionResult.createFailure(0, targetVersion, 0, [], errorMessage)
    }
  }

  /**
   * 使用 DatabaseManager 执行所有待执行的迁移
   * @returns Promise<MigrationExecutionResult>
   */
  async migrateToLatestWithManager(): Promise<MigrationExecutionResult> {
    try {
      const store = DatabaseManager.getInstance().getStore()
      return await this.migrateToLatest(store)
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      return MigrationExecutionResult.createFailure(0, 0, 0, [], errorMessage)
    }
  }

  /**
   * 使用 DatabaseManager 执行自动迁移
   */
  async autoMigrateWithManager(options?: AutoMigrationOptions): Promise<SchemaMigrationExecutionResult> {
    try {
      const store = DatabaseManager.getInstance().getStore()
      return await this.autoMigrate(store, options)
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      return SchemaMigrationExecutionResult.createFailure(new SchemaDiffResult(), [], [], errorMessage)
    }
  }

  private async safeLog(store: relationalStore.RdbStore, record: MigrationLogRecord): Promise<void> {
    if (!this.enableLog || this.logManager === null) {
      return
    }
    try {
      await this.logManager.log(store, record)
    } catch (error) {
      // 忽略日志写入错误
    }
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
    if (!rollbackErrorMessage) {
      return errorMessage
    }
    return `${errorMessage}; 回滚失败: ${rollbackErrorMessage}`
  }

  private async safeLogBatch(store: relationalStore.RdbStore, records: Array<MigrationLogRecord>): Promise<void> {
    if (records.length === 0) {
      return
    }
    for (let i = 0; i < records.length; i++) {
      await this.safeLog(store, records[i])
    }
  }

  private async safeLogSchemaChange(
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
