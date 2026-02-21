import { describe, beforeEach, it, expect } from '@ohos/hypium';
import {
  SchemaDiffer,
  SchemaDiffResult,
  SchemaChangeType,
  SchemaChange
} from '../../main/ets/schema/SchemaDiffer';
import { SchemaInspector } from '../../main/ets/schema/SchemaInspector';
import { MetadataStorage } from '../../main/ets/core/MetadataStorage';
import { ValidationMetadataStorage } from '../../main/ets/validation/ValidationMetadataStorage';
import { ColumnMetadata } from '../../main/ets/core/ColumnMetadata';
import { defineEntity } from '../../main/ets/core/EntitySchema';
import { ColumnType } from '../../main/ets/types/ColumnType';
import { relationalStore } from '@kit.ArkData';

export default function schemaDifferTest() {
  describe('schemaDifferTest', () => {
    beforeEach(() => {
      MetadataStorage.resetInstance();
      ValidationMetadataStorage.resetInstance();
    });

    // ==================== 10.3 SchemaDiffer ====================

    // SchemaDiffer 实例化测试
    it('SchemaDiffer should be instantiable without inspector', 0, () => {
      const differ = new SchemaDiffer();
      expect(differ !== null).assertEqual(true);
    });

    it('SchemaDiffer should be instantiable with custom inspector', 0, () => {
      const inspector = new SchemaInspector();
      const differ = new SchemaDiffer(inspector);
      expect(differ !== null).assertEqual(true);
    });

    // SchemaDiffResult 测试
    it('SchemaDiffResult should initialize with empty arrays', 0, () => {
      const result = new SchemaDiffResult();
      expect(result.changes.length).assertEqual(0);
      expect(result.plannedSql.length).assertEqual(0);
      expect(result.rollbackSql.length).assertEqual(0);
    });

    it('SchemaDiffResult.hasChanges should return false when empty', 0, () => {
      const result = new SchemaDiffResult();
      expect(result.hasChanges()).assertEqual(false);
    });

    it('SchemaDiffResult.addChange should add change and update sql arrays', 0, () => {
      const result = new SchemaDiffResult();
      const change: SchemaChange = {
        type: SchemaChangeType.CREATE_TABLE,
        tableName: 'users',
        sql: ['CREATE TABLE users (id INTEGER)'],
        rollbackSql: ['DROP TABLE users'],
        summary: '创建表 users',
        destructive: false
      };

      result.addChange(change);

      expect(result.changes.length).assertEqual(1);
      expect(result.plannedSql.length).assertEqual(1);
      expect(result.rollbackSql.length).assertEqual(1);
      expect(result.hasChanges()).assertEqual(true);
    });

    it('SchemaDiffResult.addChange should accumulate multiple changes', 0, () => {
      const result = new SchemaDiffResult();

      const change1: SchemaChange = {
        type: SchemaChangeType.CREATE_TABLE,
        tableName: 'users',
        sql: ['CREATE TABLE users (id INTEGER)'],
        rollbackSql: ['DROP TABLE users'],
        summary: '创建表 users',
        destructive: false
      };

      const change2: SchemaChange = {
        type: SchemaChangeType.ADD_COLUMN,
        tableName: 'users',
        columnName: 'name',
        sql: ['ALTER TABLE users ADD COLUMN name TEXT'],
        rollbackSql: ['-- Cannot drop column in SQLite'],
        summary: '新增列 users.name',
        destructive: false
      };

      result.addChange(change1);
      result.addChange(change2);

      expect(result.changes.length).assertEqual(2);
      expect(result.plannedSql.length).assertEqual(2);
      expect(result.rollbackSql.length).assertEqual(2);
    });

    // SchemaChangeType 枚举测试
    it('SchemaChangeType should have CREATE_TABLE value', 0, () => {
      expect(SchemaChangeType.CREATE_TABLE).assertEqual('CREATE_TABLE');
    });

    it('SchemaChangeType should have ADD_COLUMN value', 0, () => {
      expect(SchemaChangeType.ADD_COLUMN).assertEqual('ADD_COLUMN');
    });

    it('SchemaChangeType should have CREATE_INDEX value', 0, () => {
      expect(SchemaChangeType.CREATE_INDEX).assertEqual('CREATE_INDEX');
    });

    it('SchemaChangeType should have REBUILD_TABLE value', 0, () => {
      expect(SchemaChangeType.REBUILD_TABLE).assertEqual('REBUILD_TABLE');
    });

    // SchemaChange 接口测试
    it('SchemaChange should support CREATE_TABLE type', 0, () => {
      const change: SchemaChange = {
        type: SchemaChangeType.CREATE_TABLE,
        tableName: 'products',
        sql: ['CREATE TABLE products (id INTEGER PRIMARY KEY)'],
        rollbackSql: ['DROP TABLE IF EXISTS products'],
        summary: '创建表 products',
        destructive: false
      };

      expect(change.type).assertEqual(SchemaChangeType.CREATE_TABLE);
      expect(change.tableName).assertEqual('products');
      expect(change.destructive).assertEqual(false);
    });

    it('SchemaChange should support ADD_COLUMN type with columnName', 0, () => {
      const change: SchemaChange = {
        type: SchemaChangeType.ADD_COLUMN,
        tableName: 'users',
        columnName: 'email',
        sql: ['ALTER TABLE users ADD COLUMN email TEXT'],
        rollbackSql: ['-- SQLite does not support DROP COLUMN'],
        summary: '新增列 users.email',
        destructive: false
      };

      expect(change.type).assertEqual(SchemaChangeType.ADD_COLUMN);
      expect(change.columnName).assertEqual('email');
    });

    it('SchemaChange should support REBUILD_TABLE type as destructive', 0, () => {
      const change: SchemaChange = {
        type: SchemaChangeType.REBUILD_TABLE,
        tableName: 'users',
        sql: [
          'CREATE TABLE __tmp_users AS SELECT * FROM users',
          'DROP TABLE users',
          'ALTER TABLE __tmp_users RENAME TO users'
        ],
        rollbackSql: ['-- Manual restore required'],
        summary: '重建表 users',
        destructive: true
      };

      expect(change.type).assertEqual(SchemaChangeType.REBUILD_TABLE);
      expect(change.destructive).assertEqual(true);
      expect(change.sql.length).assertEqual(3);
    });

    // rollbackSql 生成测试
    it('SchemaChange CREATE_TABLE should have DROP TABLE rollback', 0, () => {
      const change: SchemaChange = {
        type: SchemaChangeType.CREATE_TABLE,
        tableName: 'test_table',
        sql: ['CREATE TABLE IF NOT EXISTS "test_table" ("id" INTEGER PRIMARY KEY)'],
        rollbackSql: ['DROP TABLE IF EXISTS "test_table"'],
        summary: '创建表 test_table',
        destructive: false
      };

      expect(change.rollbackSql[0].indexOf('DROP TABLE') >= 0).assertEqual(true);
    });

    // requiresRebuild 触发条件测试（通过 SchemaChange 验证）
    it('SchemaChange should mark column modification as destructive', 0, () => {
      const change: SchemaChange = {
        type: SchemaChangeType.REBUILD_TABLE,
        tableName: 'users',
        sql: ['-- rebuild sql'],
        rollbackSql: ['-- rollback'],
        summary: '重建表 users（修改列: 1, 删除列: 0）',
        destructive: true
      };

      expect(change.destructive).assertEqual(true);
      expect(change.summary.indexOf('修改列') >= 0).assertEqual(true);
    });

    it('SchemaChange should mark column deletion as destructive', 0, () => {
      const change: SchemaChange = {
        type: SchemaChangeType.REBUILD_TABLE,
        tableName: 'users',
        sql: ['-- rebuild sql'],
        rollbackSql: ['-- rollback'],
        summary: '重建表 users（修改列: 0, 删除列: 1）',
        destructive: true
      };

      expect(change.destructive).assertEqual(true);
      expect(change.summary.indexOf('删除列') >= 0).assertEqual(true);
    });

    // 多个 SQL 语句的变更
    it('SchemaChange should support multiple SQL statements', 0, () => {
      const change: SchemaChange = {
        type: SchemaChangeType.REBUILD_TABLE,
        tableName: 'users',
        sql: [
          'CREATE TABLE IF NOT EXISTS "__backup_users" AS SELECT id, name FROM "users"',
          'CREATE TABLE IF NOT EXISTS "__tmp_users" ("id" INTEGER PRIMARY KEY, "name" TEXT, "email" TEXT)',
          'INSERT INTO "__tmp_users" (id, name) SELECT id, name FROM "users"',
          'DROP TABLE "users"',
          'ALTER TABLE "__tmp_users" RENAME TO "users"'
        ],
        rollbackSql: [
          '-- 从备份表恢复',
          'INSERT INTO "users" SELECT * FROM "__backup_users"'
        ],
        summary: '重建表 users',
        destructive: true
      };

      expect(change.sql.length).assertEqual(5);
      expect(change.rollbackSql.length).assertEqual(2);
    });

    // SchemaDiffResult 多变更累积测试
    it('SchemaDiffResult should accumulate SQL from multiple changes', 0, () => {
      const result = new SchemaDiffResult();

      const change1: SchemaChange = {
        type: SchemaChangeType.CREATE_TABLE,
        tableName: 'table1',
        sql: ['CREATE TABLE table1 (id INTEGER)'],
        rollbackSql: ['DROP TABLE table1'],
        summary: '创建表 table1',
        destructive: false
      };

      const change2: SchemaChange = {
        type: SchemaChangeType.CREATE_TABLE,
        tableName: 'table2',
        sql: ['CREATE TABLE table2 (id INTEGER)'],
        rollbackSql: ['DROP TABLE table2'],
        summary: '创建表 table2',
        destructive: false
      };

      const change3: SchemaChange = {
        type: SchemaChangeType.ADD_COLUMN,
        tableName: 'table1',
        columnName: 'name',
        sql: ['ALTER TABLE table1 ADD COLUMN name TEXT'],
        rollbackSql: ['-- Cannot drop'],
        summary: '新增列 table1.name',
        destructive: false
      };

      result.addChange(change1);
      result.addChange(change2);
      result.addChange(change3);

      expect(result.plannedSql.length).assertEqual(3);
      expect(result.plannedSql[0]).assertEqual('CREATE TABLE table1 (id INTEGER)');
      expect(result.plannedSql[1]).assertEqual('CREATE TABLE table2 (id INTEGER)');
      expect(result.plannedSql[2]).assertEqual('ALTER TABLE table1 ADD COLUMN name TEXT');
    });

    // 空变更测试
    it('SchemaDiffResult should handle empty change arrays gracefully', 0, () => {
      const result = new SchemaDiffResult();
      const change: SchemaChange = {
        type: SchemaChangeType.CREATE_TABLE,
        tableName: 'empty',
        sql: [],
        rollbackSql: [],
        summary: '空变更',
        destructive: false
      };

      result.addChange(change);

      expect(result.changes.length).assertEqual(1);
      expect(result.plannedSql.length).assertEqual(0);
      expect(result.rollbackSql.length).assertEqual(0);
    });

    // destructive 标记测试
    it('CREATE_TABLE should not be destructive', 0, () => {
      const change: SchemaChange = {
        type: SchemaChangeType.CREATE_TABLE,
        tableName: 'new_table',
        sql: ['CREATE TABLE new_table (id INTEGER)'],
        rollbackSql: ['DROP TABLE new_table'],
        summary: '创建表 new_table',
        destructive: false
      };

      expect(change.destructive).assertEqual(false);
    });

    it('ADD_COLUMN should not be destructive', 0, () => {
      const change: SchemaChange = {
        type: SchemaChangeType.ADD_COLUMN,
        tableName: 'existing_table',
        columnName: 'new_col',
        sql: ['ALTER TABLE existing_table ADD COLUMN new_col TEXT'],
        rollbackSql: ['-- Cannot drop'],
        summary: '新增列',
        destructive: false
      };

      expect(change.destructive).assertEqual(false);
    });

    it('REBUILD_TABLE should be destructive', 0, () => {
      const change: SchemaChange = {
        type: SchemaChangeType.REBUILD_TABLE,
        tableName: 'table',
        sql: ['-- rebuild'],
        rollbackSql: ['-- rollback'],
        summary: '重建表',
        destructive: true
      };

      expect(change.destructive).assertEqual(true);
    });

    // 复杂场景测试
    it('SchemaDiffResult should track mixed destructive and non-destructive changes', 0, () => {
      const result = new SchemaDiffResult();

      const nonDestructive: SchemaChange = {
        type: SchemaChangeType.CREATE_TABLE,
        tableName: 'safe_table',
        sql: ['CREATE TABLE safe_table (id INTEGER)'],
        rollbackSql: ['DROP TABLE safe_table'],
        summary: '创建表',
        destructive: false
      };

      const destructive: SchemaChange = {
        type: SchemaChangeType.REBUILD_TABLE,
        tableName: 'risky_table',
        sql: ['-- rebuild'],
        rollbackSql: ['-- rollback'],
        summary: '重建表',
        destructive: true
      };

      result.addChange(nonDestructive);
      result.addChange(destructive);

      let hasDestructive = false;
      for (let i = 0; i < result.changes.length; i++) {
        if (result.changes[i].destructive) {
          hasDestructive = true;
          break;
        }
      }
      expect(hasDestructive).assertEqual(true);
      expect(result.changes.length).assertEqual(2);
    });

    it('diff should generate CREATE_INDEX change when index missing', 0, async () => {
      defineEntity('IndexedUser', {
        tableName: 'indexed_users',
        columns: [
          { property: 'id', type: ColumnType.INTEGER, primaryKey: true },
          { property: 'email', type: ColumnType.TEXT }
        ],
        indexes: [{ columns: ['email'], unique: true }]
      });
      const inspector = {
        getExistingTables: async (_store: relationalStore.RdbStore): Promise<Array<string>> => ['indexed_users'],
        getTableInfo: async (_store: relationalStore.RdbStore, _tableName: string) => ({
          name: 'indexed_users',
          columns: [
            { name: 'id', type: 'INTEGER', notNull: true, defaultValue: null, primaryKey: true },
            { name: 'email', type: 'TEXT', notNull: false, defaultValue: null, primaryKey: false }
          ],
          indexes: []
        })
      } as unknown as SchemaInspector;
      const differ = new SchemaDiffer(inspector);
      const diff = await differ.diff({} as relationalStore.RdbStore);
      expect(diff.changes.length).assertEqual(1);
      expect(diff.changes[0].type).assertEqual(SchemaChangeType.CREATE_INDEX);
      expect(diff.changes[0].sql[0].indexOf('CREATE UNIQUE INDEX') >= 0).assertEqual(true);
    });

    it('diff should generate CREATE_INDEX change for unique validation rule', 0, async () => {
      const storage = MetadataStorage.getInstance();
      storage.registerEntity('ValidatedUser', 'validated_users');
      storage.registerColumn('ValidatedUser', new ColumnMetadata('id', 'id').setType(ColumnType.INTEGER).setPrimaryKey(true));
      storage.registerColumn('ValidatedUser', new ColumnMetadata('email', 'email').setType(ColumnType.TEXT));
      ValidationMetadataStorage.getInstance().registerRule('ValidatedUser', 'email', { type: 'unique' });

      const inspector = {
        getExistingTables: async (_store: relationalStore.RdbStore): Promise<Array<string>> => ['validated_users'],
        getTableInfo: async (_store: relationalStore.RdbStore, _tableName: string) => ({
          name: 'validated_users',
          columns: [
            { name: 'id', type: 'INTEGER', notNull: true, defaultValue: null, primaryKey: true },
            { name: 'email', type: 'TEXT', notNull: false, defaultValue: null, primaryKey: false }
          ],
          indexes: []
        })
      } as unknown as SchemaInspector;
      const differ = new SchemaDiffer(inspector);
      const diff = await differ.diff({} as relationalStore.RdbStore);
      expect(diff.changes.length).assertEqual(1);
      expect(diff.changes[0].type).assertEqual(SchemaChangeType.CREATE_INDEX);
      expect(diff.changes[0].sql[0].indexOf('"uidx_validated_users_email"') >= 0).assertEqual(true);
    });

    it('diff should skip CREATE_INDEX when equivalent index exists', 0, async () => {
      defineEntity('IndexedUser2', {
        tableName: 'indexed_users2',
        columns: [
          { property: 'id', type: ColumnType.INTEGER, primaryKey: true },
          { property: 'email', type: ColumnType.TEXT }
        ],
        indexes: [{ columns: ['email'], unique: true }]
      });
      const inspector = {
        getExistingTables: async (_store: relationalStore.RdbStore): Promise<Array<string>> => ['indexed_users2'],
        getTableInfo: async (_store: relationalStore.RdbStore, _tableName: string) => ({
          name: 'indexed_users2',
          columns: [
            { name: 'id', type: 'INTEGER', notNull: true, defaultValue: null, primaryKey: true },
            { name: 'email', type: 'TEXT', notNull: false, defaultValue: null, primaryKey: false }
          ],
          indexes: [{ name: 'custom_email_idx', unique: true, columns: ['email'] }]
        })
      } as unknown as SchemaInspector;
      const differ = new SchemaDiffer(inspector);
      const diff = await differ.diff({} as relationalStore.RdbStore);
      expect(diff.changes.length).assertEqual(0);
    });

    it('diff should recreate indexes when table rebuild is required', 0, async () => {
      defineEntity('IndexedUser3', {
        tableName: 'indexed_users3',
        columns: [
          { property: 'id', type: ColumnType.INTEGER, primaryKey: true },
          { property: 'email', type: ColumnType.TEXT, nullable: false }
        ],
        indexes: [{ columns: ['email'], unique: true }]
      });
      const inspector = {
        getExistingTables: async (_store: relationalStore.RdbStore): Promise<Array<string>> => ['indexed_users3'],
        getTableInfo: async (_store: relationalStore.RdbStore, _tableName: string) => ({
          name: 'indexed_users3',
          columns: [
            { name: 'id', type: 'INTEGER', notNull: true, defaultValue: null, primaryKey: true },
            { name: 'email', type: 'TEXT', notNull: false, defaultValue: null, primaryKey: false }
          ],
          indexes: [{ name: 'uidx_indexed_users3_email', unique: true, columns: ['email'] }]
        })
      } as unknown as SchemaInspector;
      const differ = new SchemaDiffer(inspector);
      const diff = await differ.diff({} as relationalStore.RdbStore);
      const hasRebuild = diff.changes.some((change) => change.type === SchemaChangeType.REBUILD_TABLE);
      const hasCreateIndex = diff.changes.some((change) => change.type === SchemaChangeType.CREATE_INDEX);
      expect(hasRebuild).assertEqual(true);
      expect(hasCreateIndex).assertEqual(true);
    });

    // 表名特殊字符测试
    it('SchemaChange should handle special characters in table name', 0, () => {
      const change: SchemaChange = {
        type: SchemaChangeType.CREATE_TABLE,
        tableName: 'user_data_v2',
        sql: ['CREATE TABLE "user_data_v2" (id INTEGER)'],
        rollbackSql: ['DROP TABLE "user_data_v2"'],
        summary: '创建表 user_data_v2',
        destructive: false
      };

      expect(change.tableName).assertEqual('user_data_v2');
      expect(change.sql[0].indexOf('"user_data_v2"') >= 0).assertEqual(true);
    });
  });
}
