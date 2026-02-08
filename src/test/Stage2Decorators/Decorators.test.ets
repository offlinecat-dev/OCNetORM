import { describe, beforeEach, it, expect } from '@ohos/hypium';
import { MetadataStorage } from '../../main/ets/core/MetadataStorage';
import { ColumnType } from '../../main/ets/types/ColumnType';
import {
  DecoratorColumnOptions,
  PrimaryKeyOptions,
  Table,
  registerEntity,
  createEntityOptions,
  Column,
  PrimaryKey,
  CreatedAt,
  UpdatedAt,
  SoftDelete,
  inferColumnType
} from '../../main/ets/decorators';

class DecoratorColumnOptionsValue implements DecoratorColumnOptions {
  name?: string;
  type?: ColumnType;
  nullable?: boolean;
  unique?: boolean;
  defaultValue?: string | number | boolean | null;
  length?: number;
}

class PrimaryKeyOptionsValue implements PrimaryKeyOptions {
  name?: string;
  autoIncrement?: boolean;
}

export default function decoratorsTest() {
  describe('decoratorsTest', () => {
    beforeEach(() => {
      MetadataStorage.resetInstance();
    });

    it('Table decorator should register default and custom table names', 0, () => {
      class UserEntity {}
      const userInstance = new UserEntity();
      Table()(userInstance.constructor as Function);
      const storage = MetadataStorage.getInstance();
      const userMetadata = storage.getEntityMetadata(userInstance.constructor.name);
      expect(userMetadata !== null).assertEqual(true);
      if (userMetadata) {
        expect(userMetadata.tableName).assertEqual(userInstance.constructor.name);
      }

      class ProfileEntity {}
      const profileInstance = new ProfileEntity();
      Table('profiles')(profileInstance.constructor as Function);
      const profileMetadata = storage.getEntityMetadata(profileInstance.constructor.name);
      expect(profileMetadata !== null).assertEqual(true);
      if (profileMetadata) {
        expect(profileMetadata.tableName).assertEqual('profiles');
      }
    });

    it('registerEntity should ignore duplicate registrations', 0, () => {
      let threw = false;
      try {
        registerEntity('UserEntity');
        registerEntity('UserEntity');
      } catch (error) {
        threw = true;
      }
      expect(threw).assertEqual(false);
    });

    it('registerEntity should update table name when default was used', 0, () => {
      registerEntity('UserEntity');
      registerEntity('UserEntity', createEntityOptions('users'));
      const metadata = MetadataStorage.getInstance().getEntityMetadata('UserEntity');
      expect(metadata !== null).assertEqual(true);
      if (metadata) {
        expect(metadata.tableName).assertEqual('users');
      }
    });

    it('registerEntity should keep custom table name when already set', 0, () => {
      registerEntity('UserEntity', createEntityOptions('users'));
      registerEntity('UserEntity', createEntityOptions('accounts'));
      const metadata = MetadataStorage.getInstance().getEntityMetadata('UserEntity');
      expect(metadata !== null).assertEqual(true);
      if (metadata) {
        expect(metadata.tableName).assertEqual('users');
      }
    });

    it('Column should apply options to metadata', 0, () => {
      class UserEntity {}
      const userInstance = new UserEntity();
      registerEntity(userInstance.constructor.name);
      const columnOptions = new DecoratorColumnOptionsValue();
      columnOptions.name = 'user_name';
      columnOptions.type = ColumnType.TEXT;
      columnOptions.nullable = false;
      columnOptions.unique = true;
      columnOptions.defaultValue = 'guest';
      columnOptions.length = 64;
      Column(columnOptions)(userInstance, 'name');

      const metadata = MetadataStorage.getInstance().getEntityMetadata(userInstance.constructor.name);
      expect(metadata !== null).assertEqual(true);
      if (metadata) {
        const column = metadata.getColumnByProperty('name');
        expect(column !== null).assertEqual(true);
        if (column) {
          expect(column.columnName).assertEqual('user_name');
          expect(column.columnType).assertEqual(ColumnType.TEXT);
          expect(column.isNullable).assertEqual(false);
          expect(column.isUnique).assertEqual(true);
          expect(column.defaultValue).assertEqual('guest');
          expect(column.length).assertEqual(64);
        }
      }
    });

    it('Column should support boolean default value', 0, () => {
      class FeatureEntity {}
      const featureInstance = new FeatureEntity();
      registerEntity(featureInstance.constructor.name);
      const columnOptions = new DecoratorColumnOptionsValue();
      columnOptions.type = ColumnType.INTEGER;
      columnOptions.defaultValue = true;
      Column(columnOptions)(featureInstance, 'enabled');

      const metadata = MetadataStorage.getInstance().getEntityMetadata(featureInstance.constructor.name);
      expect(metadata !== null).assertEqual(true);
      if (metadata) {
        const column = metadata.getColumnByProperty('enabled');
        expect(column !== null).assertEqual(true);
        if (column) {
          expect(column.defaultValue).assertEqual(true);
        }
      }
    });

    it('PrimaryKey should register auto increment primary key by default', 0, () => {
      class UserEntity {}
      const userInstance = new UserEntity();
      registerEntity(userInstance.constructor.name);
      PrimaryKey()(userInstance, 'id');

      const metadata = MetadataStorage.getInstance().getEntityMetadata(userInstance.constructor.name);
      expect(metadata !== null).assertEqual(true);
      if (metadata) {
        const column = metadata.getColumnByProperty('id');
        expect(column !== null).assertEqual(true);
        if (column) {
          expect(column.isPrimaryKey).assertEqual(true);
          expect(column.isAutoIncrement).assertEqual(true);
          expect(column.columnType).assertEqual(ColumnType.INTEGER);
          expect(column.isNullable).assertEqual(false);
        }
      }
    });

    it('PrimaryKey should support non auto increment option', 0, () => {
      class UserEntity {}
      const userInstance = new UserEntity();
      registerEntity(userInstance.constructor.name);
      const primaryKeyOptions = new PrimaryKeyOptionsValue();
      primaryKeyOptions.autoIncrement = false;
      PrimaryKey(primaryKeyOptions)(userInstance, 'id');

      const metadata = MetadataStorage.getInstance().getEntityMetadata(userInstance.constructor.name);
      expect(metadata !== null).assertEqual(true);
      if (metadata) {
        const column = metadata.getColumnByProperty('id');
        expect(column !== null).assertEqual(true);
        if (column) {
          expect(column.isPrimaryKey).assertEqual(true);
          expect(column.isAutoIncrement).assertEqual(false);
          expect(column.columnType).assertEqual(ColumnType.INTEGER);
          expect(column.isNullable).assertEqual(false);
        }
      }
    });

    it('CreatedAt/UpdatedAt/SoftDelete should use default column names and types', 0, () => {
      class AuditEntity {}
      const auditInstance = new AuditEntity();
      registerEntity(auditInstance.constructor.name);
      CreatedAt()(auditInstance, 'createdAt');
      UpdatedAt()(auditInstance, 'updatedAt');
      SoftDelete()(auditInstance, 'deletedAt');

      const metadata = MetadataStorage.getInstance().getEntityMetadata(auditInstance.constructor.name);
      expect(metadata !== null).assertEqual(true);
      if (metadata) {
        const createdColumn = metadata.getColumnByProperty('createdAt');
        const updatedColumn = metadata.getColumnByProperty('updatedAt');
        const deletedColumn = metadata.getColumnByProperty('deletedAt');
        expect(createdColumn !== null).assertEqual(true);
        expect(updatedColumn !== null).assertEqual(true);
        expect(deletedColumn !== null).assertEqual(true);
        if (createdColumn) {
          expect(createdColumn.columnName).assertEqual('created_at');
          expect(createdColumn.columnType).assertEqual(ColumnType.INTEGER);
          expect(createdColumn.isNullable).assertEqual(false);
        }
        if (updatedColumn) {
          expect(updatedColumn.columnName).assertEqual('updated_at');
          expect(updatedColumn.columnType).assertEqual(ColumnType.INTEGER);
          expect(updatedColumn.isNullable).assertEqual(false);
        }
        if (deletedColumn) {
          expect(deletedColumn.columnName).assertEqual('deleted_at');
          expect(deletedColumn.columnType).assertEqual(ColumnType.INTEGER);
          expect(deletedColumn.isNullable).assertEqual(true);
        }
        expect(metadata.isSoftDeleteEnabled()).assertEqual(true);
        expect(metadata.getDeletedAtColumn()).assertEqual('deleted_at');
      }
    });

    it('SoftDelete should update entity soft delete column name', 0, () => {
      class SoftEntity {}
      const softInstance = new SoftEntity();
      registerEntity(softInstance.constructor.name);
      const softDeleteOptions = new DecoratorColumnOptionsValue();
      softDeleteOptions.name = 'deleted_time';
      SoftDelete(softDeleteOptions)(softInstance, 'deletedAt');

      const metadata = MetadataStorage.getInstance().getEntityMetadata(softInstance.constructor.name);
      expect(metadata !== null).assertEqual(true);
      if (metadata) {
        const column = metadata.getColumnByProperty('deletedAt');
        expect(column !== null).assertEqual(true);
        if (column) {
          expect(column.columnName).assertEqual('deleted_time');
        }
        expect(metadata.isSoftDeleteEnabled()).assertEqual(true);
        expect(metadata.getDeletedAtColumn()).assertEqual('deleted_time');
      }
    });

    it('inferColumnType should map ArkTS types', 0, () => {
      expect(inferColumnType('string')).assertEqual(ColumnType.TEXT);
      expect(inferColumnType('number')).assertEqual(ColumnType.REAL);
      expect(inferColumnType('boolean')).assertEqual(ColumnType.INTEGER);
      expect(inferColumnType('Date')).assertEqual(ColumnType.INTEGER);
      expect(inferColumnType('CustomType')).assertEqual(ColumnType.TEXT);
    });
  });
}
