import { relationalStore } from '@kit.ArkData'
import { DatabaseManager } from '../database/DatabaseManager'
import { SchemaDiffer, SchemaDiffResult } from '../schema/SchemaDiffer'

export interface MigrationGeneratorOptions {
  includeJoinTables?: boolean
  classNamePrefix?: string
  fileExtension?: string
  schemaDiffer?: SchemaDiffer
}

export class GeneratedMigration {
  hasChanges: boolean = false
  version: number = 0
  fileName: string = ''
  className: string = ''
  description: string = ''
  upSql: Array<string> = []
  downSql: Array<string> = []
  content: string = ''
}

export class MigrationGenerator {
  static async generate(options?: MigrationGeneratorOptions): Promise<GeneratedMigration> {
    const store = DatabaseManager.getInstance().getStore()
    return await MigrationGenerator.generateWithStore(store, options)
  }

  static async generateWithStore(
    store: relationalStore.RdbStore,
    options?: MigrationGeneratorOptions
  ): Promise<GeneratedMigration> {
    const differ = options?.schemaDiffer ? options.schemaDiffer : new SchemaDiffer()
    const diff = await differ.diff(store, { includeJoinTables: options?.includeJoinTables !== false })
    return MigrationGenerator.buildFromDiff(diff, options)
  }

  private static buildFromDiff(diff: SchemaDiffResult, options?: MigrationGeneratorOptions): GeneratedMigration {
    const result = new GeneratedMigration()
    result.hasChanges = diff.hasChanges()
    result.upSql = diff.plannedSql.slice()
    result.downSql = diff.rollbackSql.slice()
    result.version = MigrationGenerator.createVersionNumber()
    const prefix = options?.classNamePrefix ? options.classNamePrefix : 'Migration'
    result.className = `${prefix}_${result.version}`
    const extension = options?.fileExtension ? options.fileExtension : 'ets'
    result.fileName = `${result.className}.${extension}`
    result.description = result.hasChanges ? `Auto generated migration (${diff.changes.length} changes)` : 'No schema changes'
    result.content = MigrationGenerator.buildMigrationContent(result)
    return result
  }

  private static createVersionNumber(): number {
    const now = new Date()
    const yyyy = now.getFullYear()
    const mm = MigrationGenerator.pad2(now.getMonth() + 1)
    const dd = MigrationGenerator.pad2(now.getDate())
    const hh = MigrationGenerator.pad2(now.getHours())
    const min = MigrationGenerator.pad2(now.getMinutes())
    const ss = MigrationGenerator.pad2(now.getSeconds())
    return Number(`${yyyy}${mm}${dd}${hh}${min}${ss}`)
  }

  private static pad2(value: number): string {
    return value < 10 ? `0${value}` : String(value)
  }

  private static buildMigrationContent(migration: GeneratedMigration): string {
    const lines: Array<string> = []
    lines.push(`import { relationalStore } from '@kit.ArkData'`)
    lines.push(`import { Migration } from 'ocorm'`)
    lines.push('')
    lines.push(`export class ${migration.className} implements Migration {`)
    lines.push(`  version: number = ${migration.version}`)
    lines.push(`  description: string = '${MigrationGenerator.escapeString(migration.description)}'`)
    lines.push('')
    lines.push('  async up(store: relationalStore.RdbStore): Promise<void> {')
    MigrationGenerator.appendSqlExecutionLines(lines, migration.upSql, '    ')
    lines.push('  }')
    lines.push('')
    lines.push('  async down(store: relationalStore.RdbStore): Promise<void> {')
    MigrationGenerator.appendSqlExecutionLines(lines, migration.downSql, '    ')
    lines.push('  }')
    lines.push('}')
    return lines.join('\n')
  }

  private static appendSqlExecutionLines(lines: Array<string>, sqlList: Array<string>, indent: string): void {
    if (sqlList.length === 0) {
      lines.push(`${indent}// no-op`)
      return
    }
    for (let i = 0; i < sqlList.length; i++) {
      const sql = sqlList[i]
      if (sql.trim().startsWith('--')) {
        lines.push(`${indent}// ${sql}`)
      } else {
        lines.push(`${indent}await store.executeSql('${MigrationGenerator.escapeString(sql)}')`)
      }
    }
  }

  private static escapeString(value: string): string {
    return value
      .replace(/\\/g, '\\\\')
      .replace(/'/g, "\\'")
      .replace(/\r/g, '\\r')
      .replace(/\n/g, '\\n')
  }
}
