import { describe, beforeEach, it, expect } from '@ohos/hypium';
import { SchemaBuilder, CreateTableResult, CreateAllTablesResult } from '../../main/ets/schema/SchemaBuilder';
import { EntityMetadata } from '../../main/ets/core/EntityMetadata';
import { ColumnMetadata } from '../../main/ets/core/ColumnMetadata';
import { IndexMetadata } from '../../main/ets/core/IndexMetadata';
import { MetadataStorage } from '../../main/ets/core/MetadataStorage';
import { ValidationMetadataStorage } from '../../main/ets/validation/ValidationMetadataStorage';
import { ColumnType } from '../../main/ets/types/ColumnType';
import { RelationType } from '../../main/ets/types/RelationType';

export default function schemaBuilderTest() {
  describe('schemaBuilderTest', () => {
    let builder: SchemaBuilder;

    beforeEach(() => {
      MetadataStorage.resetInstance();
      ValidationMetadataStorage.resetInstance();
      builder = new SchemaBuilder();
    });

    // ==================== 10.1 SchemaBuilder ====================

    // generateCreateTableSql - 基础列定义
    it('generateCreateTableSql should generate basic column definition', 0, () => {
      const metadata = new EntityMetadata('User', 'users');
      const idColumn = new ColumnMetadata('id', 'id');
      idColumn.columnType = ColumnType.INTEGER;
      idColumn.isPrimaryKey = true;
      idColumn.isAutoIncrement = true;
      metadata.addColumn(idColumn);

      const nameColumn = new ColumnMetadata('name', 'name');
      nameColumn.columnType = ColumnType.TEXT;
      metadata.addColumn(nameColumn);

      const sql = builder.generateCreateTableSql(metadata);
      expect(sql.indexOf('CREATE TABLE IF NOT EXISTS') >= 0).assertEqual(true);
      expect(sql.indexOf('"users"') >= 0).assertEqual(true);
      expect(sql.indexOf('"id"') >= 0).assertEqual(true);
      expect(sql.indexOf('INTEGER') >= 0).assertEqual(true);
      expect(sql.indexOf('PRIMARY KEY') >= 0).assertEqual(true);
      expect(sql.indexOf('AUTOINCREMENT') >= 0).assertEqual(true);
    });

    // generateCreateTableSql - 默认值处理
    it('generateCreateTableSql should handle default values', 0, () => {
      const metadata = new EntityMetadata('Config', 'configs');
      const idColumn = new ColumnMetadata('id', 'id');
      idColumn.columnType = ColumnType.INTEGER;
      idColumn.isPrimaryKey = true;
      metadata.addColumn(idColumn);

      const statusColumn = new ColumnMetadata('status', 'status');
      statusColumn.columnType = ColumnType.INTEGER;
      statusColumn.defaultValue = 1;
      metadata.addColumn(statusColumn);

      const nameColumn = new ColumnMetadata('name', 'name');
      nameColumn.columnType = ColumnType.TEXT;
      nameColumn.defaultValue = 'default_name';
      metadata.addColumn(nameColumn);

      const sql = builder.generateCreateTableSql(metadata);
      expect(sql.indexOf('DEFAULT 1') >= 0).assertEqual(true);
      expect(sql.indexOf("DEFAULT 'default_name'") >= 0).assertEqual(true);
    });

    it('generateCreateTableSql should handle boolean default values', 0, () => {
      const metadata = new EntityMetadata('FeatureConfig', 'feature_configs');
      const idColumn = new ColumnMetadata('id', 'id');
      idColumn.columnType = ColumnType.INTEGER;
      idColumn.isPrimaryKey = true;
      metadata.addColumn(idColumn);

      const enabledColumn = new ColumnMetadata('enabled', 'enabled');
      enabledColumn.columnType = ColumnType.INTEGER;
      enabledColumn.defaultValue = true;
      metadata.addColumn(enabledColumn);

      const archivedColumn = new ColumnMetadata('archived', 'archived');
      archivedColumn.columnType = ColumnType.INTEGER;
      archivedColumn.defaultValue = false;
      metadata.addColumn(archivedColumn);

      const sql = builder.generateCreateTableSql(metadata);
      expect(sql.indexOf('"enabled" INTEGER DEFAULT 1') >= 0).assertEqual(true);
      expect(sql.indexOf('"archived" INTEGER DEFAULT 0') >= 0).assertEqual(true);
    });

    // generateCreateTableSql - 唯一约束
    it('generateCreateTableSql should handle unique constraint', 0, () => {
      const metadata = new EntityMetadata('User', 'users');
      const idColumn = new ColumnMetadata('id', 'id');
      idColumn.columnType = ColumnType.INTEGER;
      idColumn.isPrimaryKey = true;
      metadata.addColumn(idColumn);

      const emailColumn = new ColumnMetadata('email', 'email');
      emailColumn.columnType = ColumnType.TEXT;
      emailColumn.isUnique = true;
      metadata.addColumn(emailColumn);

      const sql = builder.generateCreateTableSql(metadata);
      expect(sql.indexOf('UNIQUE') >= 0).assertEqual(true);
    });

    it('generateCreateIndexSql should generate index statements', 0, () => {
      const metadata = new EntityMetadata('User', 'users');
      const idColumn = new ColumnMetadata('id', 'id');
      idColumn.columnType = ColumnType.INTEGER;
      idColumn.isPrimaryKey = true;
      metadata.addColumn(idColumn);
      const emailColumn = new ColumnMetadata('email', 'email');
      emailColumn.columnType = ColumnType.TEXT;
      metadata.addColumn(emailColumn);
      metadata.addIndex(new IndexMetadata('uidx_users_email', ['email'], true));
      const indexSql = builder.generateCreateIndexSql(metadata);
      expect(indexSql.length).assertEqual(1);
      expect(indexSql[0].indexOf('CREATE UNIQUE INDEX IF NOT EXISTS') >= 0).assertEqual(true);
      expect(indexSql[0].indexOf('"uidx_users_email"') >= 0).assertEqual(true);
    });

    it('generateCreateIndexSql should include unique index from validation rule', 0, () => {
      const storage = MetadataStorage.getInstance();
      storage.registerEntity('User', 'users');
      const idColumn = new ColumnMetadata('id', 'id');
      idColumn.columnType = ColumnType.INTEGER;
      idColumn.isPrimaryKey = true;
      storage.registerColumn('User', idColumn);
      const emailColumn = new ColumnMetadata('email', 'email');
      emailColumn.columnType = ColumnType.TEXT;
      storage.registerColumn('User', emailColumn);
      ValidationMetadataStorage.getInstance().registerRule('User', 'email', { type: 'unique' });

      const metadata = storage.getEntityMetadata('User');
      expect(metadata !== null).assertEqual(true);
      if (metadata !== null) {
        const indexSql = builder.generateCreateIndexSql(metadata);
        expect(indexSql.length).assertEqual(1);
        expect(indexSql[0].indexOf('CREATE UNIQUE INDEX IF NOT EXISTS') >= 0).assertEqual(true);
        expect(indexSql[0].indexOf('"uidx_users_email"') >= 0).assertEqual(true);
      }
    });

    // generateCreateTableSql - 非空约束
    it('generateCreateTableSql should handle not null constraint', 0, () => {
      const metadata = new EntityMetadata('User', 'users');
      const idColumn = new ColumnMetadata('id', 'id');
      idColumn.columnType = ColumnType.INTEGER;
      idColumn.isPrimaryKey = true;
      metadata.addColumn(idColumn);

      const nameColumn = new ColumnMetadata('name', 'name');
      nameColumn.columnType = ColumnType.TEXT;
      nameColumn.isNullable = false;
      metadata.addColumn(nameColumn);

      const sql = builder.generateCreateTableSql(metadata);
      expect(sql.indexOf('NOT NULL') >= 0).assertEqual(true);
    });

    // escapeIdentifier - SQL 注入保护
    it('generateCreateTableSql should escape special characters in table name', 0, () => {
      const metadata = new EntityMetadata('Test"Entity', 'test"table');
      const idColumn = new ColumnMetadata('id', 'id');
      idColumn.columnType = ColumnType.INTEGER;
      idColumn.isPrimaryKey = true;
      metadata.addColumn(idColumn);

      const sql = builder.generateCreateTableSql(metadata);
      expect(sql.indexOf('test""table') >= 0).assertEqual(true);
    });

    it('generateCreateTableSql should escape special characters in column name', 0, () => {
      const metadata = new EntityMetadata('User', 'users');
      const idColumn = new ColumnMetadata('id"col', 'id"col');
      idColumn.columnType = ColumnType.INTEGER;
      idColumn.isPrimaryKey = true;
      metadata.addColumn(idColumn);

      const sql = builder.generateCreateTableSql(metadata);
      expect(sql.indexOf('id""col') >= 0).assertEqual(true);
    });

    // generateCreateTableSqlByName - 实体未注册返回空字符串
    it('generateCreateTableSqlByName should return empty string for unregistered entity', 0, () => {
      const sql = builder.generateCreateTableSqlByName('NonExistent');
      expect(sql).assertEqual('');
    });

    // generateCreateTableSqlByName - 正常返回 SQL
    it('generateCreateTableSqlByName should return SQL for registered entity', 0, () => {
      const storage = MetadataStorage.getInstance();
      storage.registerEntity('User', 'users');
      const idColumn = new ColumnMetadata('id', 'id');
      idColumn.columnType = ColumnType.INTEGER;
      idColumn.isPrimaryKey = true;
      storage.registerColumn('User', idColumn);

      const sql = builder.generateCreateTableSqlByName('User');
      expect(sql.indexOf('CREATE TABLE IF NOT EXISTS') >= 0).assertEqual(true);
      expect(sql.indexOf('"users"') >= 0).assertEqual(true);
    });

    // generateAllCreateTableSql - includeJoinTables false
    it('generateAllCreateTableSql should not include join tables when false', 0, () => {
      const storage = MetadataStorage.getInstance();
      storage.registerEntity('User', 'users');
      const idColumn = new ColumnMetadata('id', 'id');
      idColumn.columnType = ColumnType.INTEGER;
      idColumn.isPrimaryKey = true;
      storage.registerColumn('User', idColumn);

      storage.registerEntity('Tag', 'tags');
      const tagIdColumn = new ColumnMetadata('id', 'id');
      tagIdColumn.columnType = ColumnType.INTEGER;
      tagIdColumn.isPrimaryKey = true;
      storage.registerColumn('Tag', tagIdColumn);

      storage.registerManyToMany('User', 'Tag', 'tags', 'user_tags', 'user_id', 'tag_id');

      const sqlStatements = builder.generateAllCreateTableSql(false);
      expect(sqlStatements.length).assertEqual(2);

      let hasJoinTable = false;
      for (let i = 0; i < sqlStatements.length; i++) {
        if (sqlStatements[i].indexOf('user_tags') >= 0) {
          hasJoinTable = true;
        }
      }
      expect(hasJoinTable).assertEqual(false);
    });

    // generateAllCreateTableSql - includeJoinTables true
    it('generateAllCreateTableSql should include join tables when true', 0, () => {
      const storage = MetadataStorage.getInstance();
      storage.registerEntity('User', 'users');
      const idColumn = new ColumnMetadata('id', 'id');
      idColumn.columnType = ColumnType.INTEGER;
      idColumn.isPrimaryKey = true;
      storage.registerColumn('User', idColumn);

      storage.registerEntity('Tag', 'tags');
      const tagIdColumn = new ColumnMetadata('id', 'id');
      tagIdColumn.columnType = ColumnType.INTEGER;
      tagIdColumn.isPrimaryKey = true;
      storage.registerColumn('Tag', tagIdColumn);

      storage.registerManyToMany('User', 'Tag', 'tags', 'user_tags', 'user_id', 'tag_id');

      const sqlStatements = builder.generateAllCreateTableSql(true);
      expect(sqlStatements.length).assertEqual(3);

      let hasJoinTable = false;
      for (let i = 0; i < sqlStatements.length; i++) {
        if (sqlStatements[i].indexOf('user_tags') >= 0) {
          hasJoinTable = true;
        }
      }
      expect(hasJoinTable).assertEqual(true);
    });

    // joinTable 生成测试
    it('generateAllCreateTableSql should generate correct join table SQL', 0, () => {
      const storage = MetadataStorage.getInstance();
      storage.registerEntity('User', 'users');
      const idColumn = new ColumnMetadata('id', 'id');
      idColumn.columnType = ColumnType.INTEGER;
      idColumn.isPrimaryKey = true;
      storage.registerColumn('User', idColumn);

      storage.registerEntity('Tag', 'tags');
      const tagIdColumn = new ColumnMetadata('id', 'id');
      tagIdColumn.columnType = ColumnType.INTEGER;
      tagIdColumn.isPrimaryKey = true;
      storage.registerColumn('Tag', tagIdColumn);

      storage.registerManyToMany('User', 'Tag', 'tags', 'user_tags', 'user_id', 'tag_id');

      const sqlStatements = builder.generateAllCreateTableSql(true);
      let joinTableSql = '';
      for (let i = 0; i < sqlStatements.length; i++) {
        if (sqlStatements[i].indexOf('user_tags') >= 0) {
          joinTableSql = sqlStatements[i];
        }
      }
      expect(joinTableSql.indexOf('"user_id"') >= 0).assertEqual(true);
      expect(joinTableSql.indexOf('"tag_id"') >= 0).assertEqual(true);
      expect(joinTableSql.indexOf('NOT NULL') >= 0).assertEqual(true);
      expect(joinTableSql.indexOf('UNIQUE') >= 0).assertEqual(true);
    });

    // CreateTableResult 静态方法测试
    it('CreateTableResult.createSuccess should create success result', 0, () => {
      const result = CreateTableResult.createSuccess('users', 'CREATE TABLE users');
      expect(result.success).assertEqual(true);
      expect(result.tableName).assertEqual('users');
      expect(result.sql).assertEqual('CREATE TABLE users');
      expect(result.errorMessage).assertEqual('');
    });

    it('CreateTableResult.createFailure should create failure result', 0, () => {
      const result = CreateTableResult.createFailure('users', 'CREATE TABLE users', 'Table exists');
      expect(result.success).assertEqual(false);
      expect(result.tableName).assertEqual('users');
      expect(result.sql).assertEqual('CREATE TABLE users');
      expect(result.errorMessage).assertEqual('Table exists');
    });

    // CreateAllTablesResult 测试
    it('CreateAllTablesResult.create should calculate counts correctly', 0, () => {
      const results: Array<CreateTableResult> = [];
      results.push(CreateTableResult.createSuccess('users', 'sql1'));
      results.push(CreateTableResult.createSuccess('posts', 'sql2'));
      results.push(CreateTableResult.createFailure('tags', 'sql3', 'error'));

      const allResult = CreateAllTablesResult.create(results);
      expect(allResult.success).assertEqual(false);
      expect(allResult.successCount).assertEqual(2);
      expect(allResult.failureCount).assertEqual(1);
      expect(allResult.results.length).assertEqual(3);
    });

    it('CreateAllTablesResult.create should be success when all tables succeed', 0, () => {
      const results: Array<CreateTableResult> = [];
      results.push(CreateTableResult.createSuccess('users', 'sql1'));
      results.push(CreateTableResult.createSuccess('posts', 'sql2'));

      const allResult = CreateAllTablesResult.create(results);
      expect(allResult.success).assertEqual(true);
      expect(allResult.successCount).assertEqual(2);
      expect(allResult.failureCount).assertEqual(0);
    });

    // 各种列类型测试
    it('generateCreateTableSql should handle REAL column type', 0, () => {
      const metadata = new EntityMetadata('Product', 'products');
      const idColumn = new ColumnMetadata('id', 'id');
      idColumn.columnType = ColumnType.INTEGER;
      idColumn.isPrimaryKey = true;
      metadata.addColumn(idColumn);

      const priceColumn = new ColumnMetadata('price', 'price');
      priceColumn.columnType = ColumnType.REAL;
      metadata.addColumn(priceColumn);

      const sql = builder.generateCreateTableSql(metadata);
      expect(sql.indexOf('REAL') >= 0).assertEqual(true);
    });

    it('generateCreateTableSql should handle BLOB column type', 0, () => {
      const metadata = new EntityMetadata('File', 'files');
      const idColumn = new ColumnMetadata('id', 'id');
      idColumn.columnType = ColumnType.INTEGER;
      idColumn.isPrimaryKey = true;
      metadata.addColumn(idColumn);

      const dataColumn = new ColumnMetadata('data', 'data');
      dataColumn.columnType = ColumnType.BLOB;
      metadata.addColumn(dataColumn);

      const sql = builder.generateCreateTableSql(metadata);
      expect(sql.indexOf('BLOB') >= 0).assertEqual(true);
    });

    // 默认值转义测试
    it('generateCreateTableSql should escape single quotes in default value', 0, () => {
      const metadata = new EntityMetadata('Config', 'configs');
      const idColumn = new ColumnMetadata('id', 'id');
      idColumn.columnType = ColumnType.INTEGER;
      idColumn.isPrimaryKey = true;
      metadata.addColumn(idColumn);

      const valueColumn = new ColumnMetadata('value', 'value');
      valueColumn.columnType = ColumnType.TEXT;
      valueColumn.defaultValue = "it's a test";
      metadata.addColumn(valueColumn);

      const sql = builder.generateCreateTableSql(metadata);
      expect(sql.indexOf("it''s a test") >= 0).assertEqual(true);
    });

    // 主键非自增测试
    it('generateCreateTableSql should handle primary key without autoincrement', 0, () => {
      const metadata = new EntityMetadata('User', 'users');
      const idColumn = new ColumnMetadata('uuid', 'uuid');
      idColumn.columnType = ColumnType.TEXT;
      idColumn.isPrimaryKey = true;
      idColumn.isAutoIncrement = false;
      metadata.addColumn(idColumn);

      const sql = builder.generateCreateTableSql(metadata);
      expect(sql.indexOf('PRIMARY KEY') >= 0).assertEqual(true);
      expect(sql.indexOf('AUTOINCREMENT') >= 0).assertEqual(false);
    });

    // TEXT 主键不应有 AUTOINCREMENT
    it('generateCreateTableSql should not add autoincrement for TEXT primary key', 0, () => {
      const metadata = new EntityMetadata('User', 'users');
      const idColumn = new ColumnMetadata('id', 'id');
      idColumn.columnType = ColumnType.TEXT;
      idColumn.isPrimaryKey = true;
      idColumn.isAutoIncrement = true;
      metadata.addColumn(idColumn);

      const sql = builder.generateCreateTableSql(metadata);
      expect(sql.indexOf('AUTOINCREMENT') >= 0).assertEqual(false);
    });

    // 空实体测试
    it('generateAllCreateTableSql should return empty array when no entities', 0, () => {
      const sqlStatements = builder.generateAllCreateTableSql(false);
      expect(sqlStatements.length).assertEqual(0);
    });

    // 多对多关系中间表类型推断测试
    it('generateAllCreateTableSql should use correct type for join table columns', 0, () => {
      const storage = MetadataStorage.getInstance();

      storage.registerEntity('User', 'users');
      const userIdColumn = new ColumnMetadata('id', 'id');
      userIdColumn.columnType = ColumnType.INTEGER;
      userIdColumn.isPrimaryKey = true;
      storage.registerColumn('User', userIdColumn);

      storage.registerEntity('Role', 'roles');
      const roleIdColumn = new ColumnMetadata('id', 'id');
      roleIdColumn.columnType = ColumnType.TEXT;
      roleIdColumn.isPrimaryKey = true;
      storage.registerColumn('Role', roleIdColumn);

      storage.registerManyToMany('User', 'Role', 'roles', 'user_roles', 'user_id', 'role_id');

      const sqlStatements = builder.generateAllCreateTableSql(true);
      let joinTableSql = '';
      for (let i = 0; i < sqlStatements.length; i++) {
        if (sqlStatements[i].indexOf('user_roles') >= 0) {
          joinTableSql = sqlStatements[i];
        }
      }
      expect(joinTableSql.indexOf('INTEGER') >= 0).assertEqual(true);
      expect(joinTableSql.indexOf('TEXT') >= 0).assertEqual(true);
    });
  });
}
