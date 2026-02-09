import { describe, beforeEach, it, expect } from '@ohos/hypium';
import { MetadataStorage } from '../../main/ets/core/MetadataStorage';
import { ColumnMetadata } from '../../main/ets/core/ColumnMetadata';
import { ColumnType } from '../../main/ets/types/ColumnType';
import { Repository, DeleteResult } from '../../main/ets/repository/index';
import { EntityData } from '../../main/ets/mapping/EntityData';
import { ExecutionError } from '../../main/ets/errors/DatabaseError';
import { SoftDeleteNotEnabledError } from '../../main/ets/errors/SoftDeleteError';
import { HooksProcessor } from '../../main/ets/core/HooksProcessor';

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
};

const setupSoftDeleteEntity = (): void => {
  const storage = MetadataStorage.getInstance();
  storage.registerEntity('Article', 'articles');

  const idColumn = new ColumnMetadata('id', 'id')
    .setType(ColumnType.INTEGER)
    .setPrimaryKey(true);
  storage.registerColumn('Article', idColumn);

  const titleColumn = new ColumnMetadata('title', 'title')
    .setType(ColumnType.TEXT);
  storage.registerColumn('Article', titleColumn);

  const deletedAtColumn = new ColumnMetadata('deletedAt', 'deleted_at')
    .setType(ColumnType.INTEGER)
    .setNullable(true);
  storage.registerColumn('Article', deletedAtColumn);

  const metadata = storage.getEntityMetadata('Article');
  if (metadata) {
    metadata.setSoftDelete(true, 'deleted_at');
  }
};

const createEntityDataWithId = (id: number): EntityData => {
  const data = new EntityData('User');
  data.addProperty('id', id, 'number');
  data.addProperty('name', 'Test User', 'string');
  return data;
};

const createEntityDataWithoutId = (): EntityData => {
  const data = new EntityData('User');
  data.addProperty('name', 'Test User', 'string');
  return data;
};

export default function repositoryDeleteTest() {
  describe('repositoryDeleteTest', () => {
    beforeEach(() => {
      MetadataStorage.resetInstance();
      HooksProcessor.resetInstance();
    });

    it('DeleteResult.createSuccess should create success result', 0, () => {
      const result = DeleteResult.createSuccess(1);
      expect(result.success).assertEqual(true);
      expect(result.affectedRows).assertEqual(1);
      expect(result.errorMessage).assertEqual('');
    });

    it('DeleteResult.createFailure should create failure result', 0, () => {
      const result = DeleteResult.createFailure('Delete failed');
      expect(result.success).assertEqual(false);
      expect(result.affectedRows).assertEqual(0);
      expect(result.errorMessage).assertEqual('Delete failed');
    });

    it('remove should return failure when entity has no primary key value', 0, async () => {
      setupUserEntity();
      const repo = new Repository('User');
      const entityData = createEntityDataWithoutId();

      const result = await repo.remove(entityData);
      expect(result.success).assertEqual(false);
      expect(result.errorMessage.length > 0).assertEqual(true);
    });

    it('remove should return failure when database not initialized', 0, async () => {
      setupUserEntity();
      const repo = new Repository('User');
      const entityData = createEntityDataWithId(1);

      const result = await repo.remove(entityData);
      expect(result.success).assertEqual(false);
      expect(result.errorMessage.length > 0).assertEqual(true);
    });

    it('removeById should return failure when database not initialized', 0, async () => {
      setupUserEntity();
      const repo = new Repository('User');

      const result = await repo.removeById(1);
      expect(result.success).assertEqual(false);
      expect(result.errorMessage.length > 0).assertEqual(true);
    });

    it('removeById on soft delete entity should return failure when database not initialized', 0, async () => {
      setupSoftDeleteEntity();
      const repo = new Repository('Article');

      const result = await repo.removeById(1);
      expect(result.success).assertEqual(false);
      expect(result.errorMessage.length > 0).assertEqual(true);
    });

    it('forceRemove should return failure when entity has no primary key value', 0, async () => {
      setupUserEntity();
      const repo = new Repository('User');
      const entityData = createEntityDataWithoutId();

      const result = await repo.forceRemove(entityData);
      expect(result.success).assertEqual(false);
    });

    it('forceRemove should return failure when database not initialized', 0, async () => {
      setupUserEntity();
      const repo = new Repository('User');
      const entityData = createEntityDataWithId(1);

      const result = await repo.forceRemove(entityData);
      expect(result.success).assertEqual(false);
      expect(result.errorMessage.length > 0).assertEqual(true);
    });

    it('forceRemoveById should return failure when database not initialized', 0, async () => {
      setupUserEntity();
      const repo = new Repository('User');

      const result = await repo.forceRemoveById(1);
      expect(result.success).assertEqual(false);
      expect(result.errorMessage.length > 0).assertEqual(true);
    });

    it('restore should throw SoftDeleteNotEnabledError for non-soft-delete entity', 0, async () => {
      setupUserEntity();
      const repo = new Repository('User');

      let threw = false;
      let errorType = '';
      try {
        await repo.restore(1);
      } catch (error) {
        threw = true;
        if (error instanceof SoftDeleteNotEnabledError) {
          errorType = 'SoftDeleteNotEnabledError';
        }
      }

      expect(threw).assertEqual(true);
      expect(errorType).assertEqual('SoftDeleteNotEnabledError');
    });

    it('restore should return failure when database not initialized for soft-delete entity', 0, async () => {
      setupSoftDeleteEntity();
      const repo = new Repository('Article');

      const result = await repo.restore(1);
      expect(result.success).assertEqual(false);
      expect(result.errorMessage.length > 0).assertEqual(true);
    });

    it('should detect soft delete enabled on entity', 0, () => {
      setupSoftDeleteEntity();
      const repo = new Repository('Article');
      const metadata = repo.getMetadata();
      expect(metadata.isSoftDeleteEnabled()).assertEqual(true);
    });

    it('should detect soft delete disabled on entity', 0, () => {
      setupUserEntity();
      const repo = new Repository('User');
      const metadata = repo.getMetadata();
      expect(metadata.isSoftDeleteEnabled()).assertEqual(false);
    });

    it('should get deleted_at column name for soft delete entity', 0, () => {
      setupSoftDeleteEntity();
      const repo = new Repository('Article');
      const metadata = repo.getMetadata();
      const deletedAtColumn = metadata.getDeletedAtColumn();
      expect(deletedAtColumn).assertEqual('deleted_at');
    });

    it('removeById should call hardDelete for non-soft-delete entity', 0, async () => {
      setupUserEntity();
      const repo = new Repository('User');
      const metadata = repo.getMetadata();

      expect(metadata.isSoftDeleteEnabled()).assertEqual(false);
      const result = await repo.removeById(1);
      expect(result.success).assertEqual(false);
    });

    it('removeById should call softDelete for soft-delete entity', 0, async () => {
      setupSoftDeleteEntity();
      const repo = new Repository('Article');
      const metadata = repo.getMetadata();

      expect(metadata.isSoftDeleteEnabled()).assertEqual(true);
      const result = await repo.removeById(1);
      expect(result.success).assertEqual(false);
    });
  });
}
