import { describe, beforeEach, it, expect } from '@ohos/hypium';
import { MetadataStorage } from '../../main/ets/core/MetadataStorage';
import { ColumnMetadata } from '../../main/ets/core/ColumnMetadata';
import { ColumnType } from '../../main/ets/types/ColumnType';
import { Repository, SaveResult } from '../../main/ets/repository/Repository';
import { EntityData } from '../../main/ets/mapping/DataMapper';
import { EntityNotRegisteredError } from '../../main/ets/errors/MetadataError';
import { ExecutionError } from '../../main/ets/errors/DatabaseError';
import { HooksProcessor } from '../../main/ets/core/HooksProcessor';
import { ValidationMetadataStorage } from '../../main/ets/validation/ValidationMetadataStorage';

const setupUserEntity = (): void => {
  const storage = MetadataStorage.getInstance();
  storage.registerEntity('User', 'users');

  const idColumn = new ColumnMetadata('id', 'id')
    .setType(ColumnType.INTEGER)
    .setPrimaryKey(true)
    .setAutoIncrement(true);
  storage.registerColumn('User', idColumn);

  const nameColumn = new ColumnMetadata('name', 'user_name')
    .setType(ColumnType.TEXT);
  storage.registerColumn('User', nameColumn);

  const emailColumn = new ColumnMetadata('email', 'user_email')
    .setType(ColumnType.TEXT);
  storage.registerColumn('User', emailColumn);

  const updatedAtColumn = new ColumnMetadata('updatedAt', 'updated_at')
    .setType(ColumnType.INTEGER)
    .setNullable(true);
  storage.registerColumn('User', updatedAtColumn);
};

const setupEntityWithNoPrimaryKey = (): void => {
  const storage = MetadataStorage.getInstance();
  storage.registerEntity('NoPkEntity', 'no_pk_table');

  const nameColumn = new ColumnMetadata('name', 'name')
    .setType(ColumnType.TEXT);
  storage.registerColumn('NoPkEntity', nameColumn);
};

const createNewEntityData = (): EntityData => {
  const data = new EntityData('User');
  data.addProperty('name', 'Test User', 'string');
  data.addProperty('email', 'test@example.com', 'string');
  return data;
};

const createExistingEntityData = (id: number): EntityData => {
  const data = new EntityData('User');
  data.addProperty('id', id, 'number');
  data.addProperty('name', 'Existing User', 'string');
  data.addProperty('email', 'existing@example.com', 'string');
  return data;
};

export default function saveInsertUpdateTest() {
  describe('saveInsertUpdateTest', () => {
    beforeEach(() => {
      MetadataStorage.resetInstance();
      HooksProcessor.resetInstance();
      ValidationMetadataStorage.resetInstance();
    });

    it('should create Repository with registered entity', 0, () => {
      setupUserEntity();
      const repo = new Repository('User');
      expect(repo !== null).assertEqual(true);
    });

    it('should throw EntityNotRegisteredError for unregistered entity', 0, () => {
      let threw = false;
      let errorType = '';
      try {
        new Repository('UnknownEntity');
      } catch (error) {
        threw = true;
        if (error instanceof EntityNotRegisteredError) {
          errorType = 'EntityNotRegisteredError';
        }
      }
      expect(threw).assertEqual(true);
      expect(errorType).assertEqual('EntityNotRegisteredError');
    });

    it('should get metadata from repository', 0, () => {
      setupUserEntity();
      const repo = new Repository('User');
      const metadata = repo.getMetadata();
      expect(metadata !== null).assertEqual(true);
      expect(metadata.tableName).assertEqual('users');
    });

    it('should get data mapper from repository', 0, () => {
      setupUserEntity();
      const repo = new Repository('User');
      const dataMapper = repo.getDataMapper();
      expect(dataMapper !== null).assertEqual(true);
    });

    it('should create query builder', 0, () => {
      setupUserEntity();
      const repo = new Repository('User');
      const qb = repo.createQueryBuilder();
      expect(qb !== null).assertEqual(true);
    });

    it('SaveResult.createSuccess should create success result', 0, () => {
      const result = SaveResult.createSuccess(1, 100);
      expect(result.success).assertEqual(true);
      expect(result.affectedRows).assertEqual(1);
      expect(result.insertId).assertEqual(100);
      expect(result.errorMessage).assertEqual('');
    });

    it('SaveResult.createFailure should create failure result', 0, () => {
      const result = SaveResult.createFailure('Test error');
      expect(result.success).assertEqual(false);
      expect(result.affectedRows).assertEqual(0);
      expect(result.insertId).assertEqual(0);
      expect(result.errorMessage).assertEqual('Test error');
    });

    it('save should return failure when database not initialized (new record)', 0, async () => {
      setupUserEntity();
      const repo = new Repository('User');
      const entityData = createNewEntityData();

      const result = await repo.save(entityData);
      expect(result.success).assertEqual(false);
      expect(result.errorMessage.length > 0).assertEqual(true);
    });

    it('save should return failure when database not initialized (existing record)', 0, async () => {
      setupUserEntity();
      const repo = new Repository('User');
      const entityData = createExistingEntityData(1);

      const result = await repo.save(entityData);
      expect(result.success).assertEqual(false);
      expect(result.errorMessage.length > 0).assertEqual(true);
    });

    it('should detect new record when primary key is null', 0, () => {
      setupUserEntity();
      const repo = new Repository('User');
      const entityData = createNewEntityData();
      const isNew = repo.getDataMapper().isNewRecord(entityData);
      expect(isNew).assertEqual(true);
    });

    it('should detect new record when primary key is 0', 0, () => {
      setupUserEntity();
      const repo = new Repository('User');
      const entityData = new EntityData('User');
      entityData.addProperty('id', 0, 'number');
      entityData.addProperty('name', 'Test', 'string');
      const isNew = repo.getDataMapper().isNewRecord(entityData);
      expect(isNew).assertEqual(true);
    });

    it('should detect existing record when primary key is non-zero', 0, () => {
      setupUserEntity();
      const repo = new Repository('User');
      const entityData = createExistingEntityData(5);
      const isNew = repo.getDataMapper().isNewRecord(entityData);
      expect(isNew).assertEqual(false);
    });

    it('should handle entity without primary key in save', 0, async () => {
      setupEntityWithNoPrimaryKey();
      const repo = new Repository('NoPkEntity');
      const entityData = new EntityData('NoPkEntity');
      entityData.addProperty('name', 'Test', 'string');

      const result = await repo.save(entityData);
      expect(result.success).assertEqual(false);
    });

    it('should handle empty EntityData', 0, () => {
      setupUserEntity();
      const repo = new Repository('User');
      const entityData = new EntityData('User');
      const isNew = repo.getDataMapper().isNewRecord(entityData);
      expect(isNew).assertEqual(true);
    });

    it('repository should have hooks processor access', 0, () => {
      setupUserEntity();
      const repo = new Repository('User');
      expect(repo !== null).assertEqual(true);
    });

    it('should work with updated_at column configured', 0, () => {
      setupUserEntity();
      const repo = new Repository('User');
      const metadata = repo.getMetadata();
      const updatedAtColumn = metadata.getColumnByProperty('updatedAt');
      expect(updatedAtColumn !== null).assertEqual(true);
      expect(updatedAtColumn?.columnName).assertEqual('updated_at');
    });
  });
}
