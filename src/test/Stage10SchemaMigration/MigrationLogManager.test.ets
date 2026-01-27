import { describe, beforeEach, it, expect } from '@ohos/hypium';
import { MigrationLogManager, MigrationLogRecord } from '../../main/ets/schema/MigrationLogManager';

export default function migrationLogManagerTest() {
  describe('migrationLogManagerTest', () => {
    let logManager: MigrationLogManager;

    beforeEach(() => {
      logManager = new MigrationLogManager();
    });

    // ==================== 10.5 MigrationLogManager ====================

    // 构造函数测试
    it('MigrationLogManager should use default table name', 0, () => {
      const manager = new MigrationLogManager();
      expect(manager.getTableName()).assertEqual('_migrations');
    });

    it('MigrationLogManager should accept custom table name', 0, () => {
      const manager = new MigrationLogManager('custom_migrations');
      expect(manager.getTableName()).assertEqual('custom_migrations');
    });

    it('MigrationLogManager should use default when empty string passed', 0, () => {
      const manager = new MigrationLogManager('');
      expect(manager.getTableName()).assertEqual('_migrations');
    });

    // MigrationLogRecord 接口测试
    it('MigrationLogRecord should support all fields', 0, () => {
      const record: MigrationLogRecord = {
        version: 1,
        name: 'Create users table',
        type: 'MIGRATION',
        direction: 'UP',
        tableName: 'users',
        columnName: undefined,
        sql: 'CREATE TABLE users (id INTEGER)',
        summary: 'Created users table',
        success: true,
        errorMessage: undefined,
        createdAt: Date.now()
      };

      expect(record.version).assertEqual(1);
      expect(record.name).assertEqual('Create users table');
      expect(record.type).assertEqual('MIGRATION');
      expect(record.direction).assertEqual('UP');
      expect(record.tableName).assertEqual('users');
      expect(record.success).assertEqual(true);
    });

    it('MigrationLogRecord should support minimal fields', 0, () => {
      const record: MigrationLogRecord = {
        type: 'AUTO_SCHEMA'
      };

      expect(record.type).assertEqual('AUTO_SCHEMA');
      expect(record.version).assertEqual(undefined);
      expect(record.name).assertEqual(undefined);
    });

    it('MigrationLogRecord should support MIGRATION type', 0, () => {
      const record: MigrationLogRecord = {
        type: 'MIGRATION',
        version: 2,
        direction: 'UP'
      };

      expect(record.type).assertEqual('MIGRATION');
      expect(record.version).assertEqual(2);
    });

    it('MigrationLogRecord should support AUTO_SCHEMA type', 0, () => {
      const record: MigrationLogRecord = {
        type: 'AUTO_SCHEMA',
        tableName: 'posts',
        columnName: 'title'
      };

      expect(record.type).assertEqual('AUTO_SCHEMA');
      expect(record.tableName).assertEqual('posts');
      expect(record.columnName).assertEqual('title');
    });

    it('MigrationLogRecord should support DOWN direction', 0, () => {
      const record: MigrationLogRecord = {
        type: 'MIGRATION',
        direction: 'DOWN',
        version: 3
      };

      expect(record.direction).assertEqual('DOWN');
    });

    it('MigrationLogRecord should support failure with error message', 0, () => {
      const record: MigrationLogRecord = {
        type: 'MIGRATION',
        success: false,
        errorMessage: 'Table already exists'
      };

      expect(record.success).assertEqual(false);
      expect(record.errorMessage).assertEqual('Table already exists');
    });

    it('MigrationLogRecord should support SQL storage', 0, () => {
      const sql = 'ALTER TABLE users ADD COLUMN email TEXT NOT NULL';
      const record: MigrationLogRecord = {
        type: 'AUTO_SCHEMA',
        sql: sql
      };

      expect(record.sql).assertEqual(sql);
    });

    it('MigrationLogRecord should support summary field', 0, () => {
      const record: MigrationLogRecord = {
        type: 'MIGRATION',
        summary: '新增列 users.email'
      };

      expect(record.summary).assertEqual('新增列 users.email');
    });

    // 输入清洗测试（验证接口设计）
    it('MigrationLogRecord should handle long table name', 0, () => {
      const longName = 'a'.repeat(200);
      const record: MigrationLogRecord = {
        type: 'AUTO_SCHEMA',
        tableName: longName
      };

      expect(record.tableName?.length).assertEqual(200);
    });

    it('MigrationLogRecord should handle long column name', 0, () => {
      const longName = 'column_' + 'x'.repeat(150);
      const record: MigrationLogRecord = {
        type: 'AUTO_SCHEMA',
        columnName: longName
      };

      expect(record.columnName !== undefined).assertEqual(true);
      if (record.columnName) {
        expect(record.columnName.length > 100).assertEqual(true);
      }
    });

    it('MigrationLogRecord should handle special characters in name', 0, () => {
      const record: MigrationLogRecord = {
        type: 'MIGRATION',
        name: "Migration with 'quotes' and \"double quotes\""
      };

      expect(record.name?.indexOf("'") !== -1).assertEqual(true);
      expect(record.name?.indexOf('"') !== -1).assertEqual(true);
    });

    it('MigrationLogRecord should handle unicode in summary', 0, () => {
      const record: MigrationLogRecord = {
        type: 'MIGRATION',
        summary: '创建用户表 - 包含中文说明'
      };

      expect(record.summary?.indexOf('中文') !== -1).assertEqual(true);
    });

    // createdAt 字段测试
    it('MigrationLogRecord should support createdAt timestamp', 0, () => {
      const now = Date.now();
      const record: MigrationLogRecord = {
        type: 'MIGRATION',
        createdAt: now
      };

      expect(record.createdAt).assertEqual(now);
    });

    it('MigrationLogRecord should allow undefined createdAt', 0, () => {
      const record: MigrationLogRecord = {
        type: 'MIGRATION'
      };

      expect(record.createdAt).assertEqual(undefined);
    });

    // 复杂记录测试
    it('MigrationLogRecord should support complete migration log', 0, () => {
      const record: MigrationLogRecord = {
        version: 5,
        name: 'Add email column to users',
        type: 'MIGRATION',
        direction: 'UP',
        tableName: 'users',
        columnName: 'email',
        sql: 'ALTER TABLE users ADD COLUMN email TEXT',
        summary: '新增列 users.email',
        success: true,
        errorMessage: undefined,
        createdAt: 1700000000000
      };

      expect(record.version).assertEqual(5);
      expect(record.name).assertEqual('Add email column to users');
      expect(record.type).assertEqual('MIGRATION');
      expect(record.direction).assertEqual('UP');
      expect(record.tableName).assertEqual('users');
      expect(record.columnName).assertEqual('email');
      expect(record.sql?.indexOf('ALTER TABLE') !== -1).assertEqual(true);
      expect(record.success).assertEqual(true);
      expect(record.createdAt).assertEqual(1700000000000);
    });

    it('MigrationLogRecord should support complete schema change log', 0, () => {
      const record: MigrationLogRecord = {
        type: 'AUTO_SCHEMA',
        direction: 'UP',
        tableName: 'products',
        columnName: 'price',
        sql: 'ALTER TABLE products ADD COLUMN price REAL DEFAULT 0',
        summary: '自动迁移: 新增列 products.price',
        success: true,
        createdAt: Date.now()
      };

      expect(record.type).assertEqual('AUTO_SCHEMA');
      expect(record.tableName).assertEqual('products');
      expect(record.columnName).assertEqual('price');
      expect(record.summary?.indexOf('自动迁移') !== -1).assertEqual(true);
    });

    // 错误场景记录测试
    it('MigrationLogRecord should support failed migration log', 0, () => {
      const record: MigrationLogRecord = {
        version: 3,
        name: 'Failed migration',
        type: 'MIGRATION',
        direction: 'UP',
        sql: 'CREATE TABLE invalid syntax',
        summary: '迁移失败',
        success: false,
        errorMessage: 'SQLite error: near "syntax": syntax error',
        createdAt: Date.now()
      };

      expect(record.success).assertEqual(false);
      expect(record.errorMessage?.indexOf('syntax error') !== -1).assertEqual(true);
    });

    // 回滚记录测试
    it('MigrationLogRecord should support rollback log', 0, () => {
      const record: MigrationLogRecord = {
        version: 2,
        name: 'Rollback add posts table',
        type: 'MIGRATION',
        direction: 'DOWN',
        tableName: 'posts',
        sql: 'DROP TABLE IF EXISTS posts',
        summary: '回滚: 删除 posts 表',
        success: true
      };

      expect(record.direction).assertEqual('DOWN');
      expect(record.sql?.indexOf('DROP TABLE') !== -1).assertEqual(true);
    });

    // 表名获取测试
    it('getTableName should return configured table name', 0, () => {
      expect(logManager.getTableName()).assertEqual('_migrations');
    });

    it('getTableName should return custom table name when configured', 0, () => {
      const customManager = new MigrationLogManager('my_migration_logs');
      expect(customManager.getTableName()).assertEqual('my_migration_logs');
    });

    // 多实例测试
    it('MigrationLogManager instances should be independent', 0, () => {
      const manager1 = new MigrationLogManager('table1');
      const manager2 = new MigrationLogManager('table2');

      expect(manager1.getTableName()).assertEqual('table1');
      expect(manager2.getTableName()).assertEqual('table2');
    });

    // 边界值测试
    it('MigrationLogRecord should handle version 0', 0, () => {
      const record: MigrationLogRecord = {
        type: 'MIGRATION',
        version: 0
      };

      expect(record.version).assertEqual(0);
    });

    it('MigrationLogRecord should handle large version number', 0, () => {
      const record: MigrationLogRecord = {
        type: 'MIGRATION',
        version: 999999999
      };

      expect(record.version).assertEqual(999999999);
    });

    it('MigrationLogRecord should handle empty sql', 0, () => {
      const record: MigrationLogRecord = {
        type: 'AUTO_SCHEMA',
        sql: ''
      };

      expect(record.sql).assertEqual('');
    });

    it('MigrationLogRecord should handle multiline sql', 0, () => {
      const multilineSql = `CREATE TABLE users (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        email TEXT UNIQUE
      )`;
      const record: MigrationLogRecord = {
        type: 'MIGRATION',
        sql: multilineSql
      };

      expect(record.sql?.indexOf('\n') !== -1).assertEqual(true);
    });

    // 表名特殊字符测试
    it('MigrationLogManager should handle underscore in table name', 0, () => {
      const manager = new MigrationLogManager('_custom_migrations_log');
      expect(manager.getTableName()).assertEqual('_custom_migrations_log');
    });

    it('MigrationLogManager should handle numbers in table name', 0, () => {
      const manager = new MigrationLogManager('migrations_v2');
      expect(manager.getTableName()).assertEqual('migrations_v2');
    });
  });
}
