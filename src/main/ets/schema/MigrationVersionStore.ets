import { relationalStore } from '@kit.ArkData'
import { ExecutionError } from '../errors/DatabaseError'

type VersionSetter = (version: number) => void

export class MigrationVersionStore {
  private static readonly VERSION_TABLE = '_orm_version'
  private setVersion: VersionSetter

  constructor(setVersion: VersionSetter) {
    this.setVersion = setVersion
  }

  async getCurrentVersionFromDb(store: relationalStore.RdbStore): Promise<number> {
    try {
      await this.ensureVersionTable(store)
      const predicates = new relationalStore.RdbPredicates(MigrationVersionStore.VERSION_TABLE)
      let resultSet: relationalStore.ResultSet | null = null
      try {
        resultSet = await store.query(predicates)
        if (resultSet.goToFirstRow()) {
          const versionIndex = resultSet.getColumnIndex('version')
          const version = resultSet.getLong(versionIndex)
          this.setVersion(version)
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

  async updateVersionInDb(store: relationalStore.RdbStore, version: number): Promise<void> {
    try {
      const predicates = new relationalStore.RdbPredicates(MigrationVersionStore.VERSION_TABLE)
      predicates.equalTo('id', 1)
      const updateValues: relationalStore.ValuesBucket = {
        'version': version,
        'updated_at': Date.now()
      }
      await store.update(updateValues, predicates)
      this.setVersion(version)
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      throw new ExecutionError('UPDATE', `更新数据库版本失败: ${errorMessage}`)
    }
  }

  private async ensureVersionTable(store: relationalStore.RdbStore): Promise<void> {
    const createSql = `CREATE TABLE IF NOT EXISTS ${MigrationVersionStore.VERSION_TABLE} (
      id INTEGER PRIMARY KEY,
      version INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER NOT NULL
    )`
    try {
      await store.executeSql(createSql)
      const predicates = new relationalStore.RdbPredicates(MigrationVersionStore.VERSION_TABLE)
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
        await store.insert(MigrationVersionStore.VERSION_TABLE, insertValues)
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      throw new ExecutionError('CREATE TABLE', `创建版本表失败: ${errorMessage}`)
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
}
