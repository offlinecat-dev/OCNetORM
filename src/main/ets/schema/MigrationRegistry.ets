import { Migration } from './Migration'

export class MigrationRegistry {
  private migrations: Array<Migration> = []

  register(migration: Migration): void {
    for (let i = 0; i < this.migrations.length; i++) {
      if (this.migrations[i].version === migration.version) {
        throw new Error(`迁移版本 ${migration.version} 已存在`)
      }
    }
    this.migrations.push(migration)
  }

  registerAll(migrations: Array<Migration>): void {
    for (let i = 0; i < migrations.length; i++) {
      try {
        this.register(migrations[i])
      } catch (e) {
        // ignore duplicate
      }
    }
  }

  getMigrationsByOrder(): Array<Migration> {
    const sorted = this.migrations.slice()
    sorted.sort((left, right) => left.version - right.version)
    return sorted
  }

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

  getRollbackMigrations(currentVersion: number, targetVersion: number): Array<Migration> {
    const sorted = this.getMigrationsByOrder()
    const rollback: Array<Migration> = []
    for (let i = 0; i < sorted.length; i++) {
      const migration = sorted[i]
      if (migration.version > targetVersion && migration.version <= currentVersion) {
        rollback.push(migration)
      }
    }
    const reversed: Array<Migration> = []
    for (let i = rollback.length - 1; i >= 0; i--) {
      reversed.push(rollback[i])
    }
    return reversed
  }

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

  getMigration(version: number): Migration | null {
    for (let i = 0; i < this.migrations.length; i++) {
      if (this.migrations[i].version === version) {
        return this.migrations[i]
      }
    }
    return null
  }

  getMigrationCount(): number {
    return this.migrations.length
  }

  hasPendingMigrations(currentVersion: number): boolean {
    return this.getPendingMigrations(currentVersion).length > 0
  }

  clear(): void {
    this.migrations = []
  }
}

