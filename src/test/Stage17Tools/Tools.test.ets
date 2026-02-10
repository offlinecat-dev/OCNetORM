import { describe, beforeEach, it, expect } from '@ohos/hypium'
import { relationalStore } from '@kit.ArkData'
import { MetadataStorage } from '../../main/ets/core/MetadataStorage'
import { defineEntity } from '../../main/ets/core/EntitySchema'
import { ColumnType } from '../../main/ets/types/ColumnType'
import { Repository } from '../../main/ets/repository/Repository'
import { Seeder, SeederManager } from '../../main/ets/tools/SeederManager'
import { defineFactory } from '../../main/ets/tools/Factory'
import { MigrationGenerator } from '../../main/ets/tools/MigrationGenerator'
import { SchemaDiffResult, SchemaDiffer, SchemaChangeType } from '../../main/ets/schema/SchemaDiffer'

class UserSeeder implements Seeder {
  static count: number = 0
  async run(_repo: Repository): Promise<void> {
    UserSeeder.count += 1
  }
}

class MockSchemaDiffer extends SchemaDiffer {
  private diffResult: SchemaDiffResult
  constructor(diffResult: SchemaDiffResult) {
    super()
    this.diffResult = diffResult
  }
  async diff(_store: relationalStore.RdbStore): Promise<SchemaDiffResult> {
    return this.diffResult
  }
}

export default function toolsTest() {
  describe('toolsTest', () => {
    beforeEach(() => {
      MetadataStorage.resetInstance()
      UserSeeder.count = 0
    })

    it('SeederManager should infer entity name from class name', 0, async () => {
      defineEntity('User', {
        columns: [
          { property: 'id', type: ColumnType.INTEGER, primaryKey: true },
          { property: 'name', type: ColumnType.TEXT }
        ]
      })
      const result = await SeederManager.run([new UserSeeder()])
      expect(result.success).assertEqual(true)
      expect(result.successCount).assertEqual(1)
      expect(UserSeeder.count).assertEqual(1)
    })

    it('defineFactory should create EntityData with metadata properties', 0, async () => {
      defineEntity('User', {
        columns: [
          { property: 'id', type: ColumnType.INTEGER, primaryKey: true },
          { property: 'name', type: ColumnType.TEXT },
          { property: 'email', type: ColumnType.TEXT }
        ]
      })
      const factory = defineFactory('User', (faker) => ({
        name: faker.name(),
        email: faker.email(),
        age: faker.number({ min: 18, max: 60 })
      }))
      const entity = await factory.make({ name: 'OverrideName' })
      expect(entity.hasProperty('name')).assertEqual(true)
      expect(entity.hasProperty('email')).assertEqual(true)
      expect(entity.hasProperty('age')).assertEqual(false)
      expect(entity.getPropertyValue('name')).assertEqual('OverrideName')
    })

    it('MigrationGenerator should generate migration content from diff', 0, async () => {
      const diff = new SchemaDiffResult()
      diff.addChange({
        type: SchemaChangeType.CREATE_TABLE,
        tableName: 'users',
        sql: ['CREATE TABLE users (id INTEGER PRIMARY KEY)'],
        rollbackSql: ['DROP TABLE users'],
        summary: 'create users',
        destructive: false
      })
      const generated = await MigrationGenerator.generateWithStore(
        {} as relationalStore.RdbStore,
        { schemaDiffer: new MockSchemaDiffer(diff), classNamePrefix: 'Migration', fileExtension: 'ets' }
      )
      expect(generated.hasChanges).assertEqual(true)
      expect(generated.fileName.indexOf('Migration_') >= 0).assertEqual(true)
      expect(generated.content.indexOf('await store.executeSql') >= 0).assertEqual(true)
    })
  })
}
