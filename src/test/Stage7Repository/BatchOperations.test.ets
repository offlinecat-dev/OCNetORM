import { describe, beforeEach, it, expect } from '@ohos/hypium';
import { MetadataStorage } from '../../main/ets/core/MetadataStorage';
import { ColumnMetadata } from '../../main/ets/core/ColumnMetadata';
import { ColumnType } from '../../main/ets/types/ColumnType';
import { Repository, SaveResult } from '../../main/ets/repository/Repository';
import { BatchInsertOptions } from '../../main/ets/repository/BatchInsertOptions';
import { BatchInsertResult } from '../../main/ets/repository/BatchInsertResult';
import { EntityData } from '../../main/ets/mapping/DataMapper';
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
};

const createEntityData = (name: string, email: string): EntityData => {
  const data = new EntityData('User');
  data.addProperty('name', name, 'string');
  data.addProperty('email', email, 'string');
  return data;
};

export default function batchOperationsTest() {
  describe('batchOperationsTest', () => {
    beforeEach(() => {
      MetadataStorage.resetInstance();
      HooksProcessor.resetInstance();
      ValidationMetadataStorage.resetInstance();
    });

    it('BatchInsertOptions constructor should set default values', 0, () => {
      const options = new BatchInsertOptions();
      expect(options.useTransaction).assertEqual(true);
      expect(options.executeHooks).assertEqual(true);
      expect(options.executeValidation).assertEqual(true);
    });

    it('BatchInsertOptions constructor should accept parameters', 0, () => {
      const options = new BatchInsertOptions(false, false, false);
      expect(options.useTransaction).assertEqual(false);
      expect(options.executeHooks).assertEqual(false);
      expect(options.executeValidation).assertEqual(false);
    });

    it('BatchInsertOptions.create should create options', 0, () => {
      const options = BatchInsertOptions.create(true, false, true);
      expect(options.useTransaction).assertEqual(true);
      expect(options.executeHooks).assertEqual(false);
      expect(options.executeValidation).assertEqual(true);
    });

    it('BatchInsertOptions.createDefault should create default options', 0, () => {
      const options = BatchInsertOptions.createDefault();
      expect(options.useTransaction).assertEqual(true);
      expect(options.executeHooks).assertEqual(true);
      expect(options.executeValidation).assertEqual(true);
    });

    it('BatchInsertOptions.createFast should create fast options', 0, () => {
      const options = BatchInsertOptions.createFast();
      expect(options.useTransaction).assertEqual(false);
      expect(options.executeHooks).assertEqual(false);
      expect(options.executeValidation).assertEqual(false);
    });

    it('BatchInsertOptions.createSafe should create safe options', 0, () => {
      const options = BatchInsertOptions.createSafe();
      expect(options.useTransaction).assertEqual(true);
      expect(options.executeHooks).assertEqual(true);
      expect(options.executeValidation).assertEqual(true);
    });

    it('BatchInsertResult constructor should set default values', 0, () => {
      const result = new BatchInsertResult();
      expect(result.success).assertEqual(false);
      expect(result.insertedCount).assertEqual(0);
      expect(result.totalCount).assertEqual(0);
      expect(result.failedIndexes.length).assertEqual(0);
      expect(result.errorMessage).assertEqual('');
    });

    it('BatchInsertResult.createSuccess should create success result', 0, () => {
      const result = BatchInsertResult.createSuccess(10, 10);
      expect(result.success).assertEqual(true);
      expect(result.insertedCount).assertEqual(10);
      expect(result.totalCount).assertEqual(10);
    });

    it('BatchInsertResult.createFailure should create failure result', 0, () => {
      const result = BatchInsertResult.createFailure('Insert failed', [0, 2]);
      expect(result.success).assertEqual(false);
      expect(result.errorMessage).assertEqual('Insert failed');
      expect(result.failedIndexes.length).assertEqual(2);
      expect(result.failedIndexes[0]).assertEqual(0);
      expect(result.failedIndexes[1]).assertEqual(2);
    });

    it('BatchInsertResult.createPartialSuccess should create partial success result', 0, () => {
      const result = BatchInsertResult.createPartialSuccess(7, 10, [1, 3, 5], 'Some failed');
      expect(result.success).assertEqual(false);
      expect(result.insertedCount).assertEqual(7);
      expect(result.totalCount).assertEqual(10);
      expect(result.failedIndexes.length).assertEqual(3);
      expect(result.errorMessage).assertEqual('Some failed');
    });

    it('BatchInsertResult.isAllSuccess should return true when all succeed', 0, () => {
      const result = BatchInsertResult.createSuccess(10, 10);
      expect(result.isAllSuccess()).assertEqual(true);
    });

    it('BatchInsertResult.isAllSuccess should return false when partial', 0, () => {
      const result = BatchInsertResult.createPartialSuccess(5, 10, [], '');
      expect(result.isAllSuccess()).assertEqual(false);
    });

    it('BatchInsertResult.isPartialSuccess should return true for partial success', 0, () => {
      const result = BatchInsertResult.createPartialSuccess(5, 10, [], '');
      expect(result.isPartialSuccess()).assertEqual(true);
    });

    it('BatchInsertResult.isPartialSuccess should return false when all succeed', 0, () => {
      const result = BatchInsertResult.createSuccess(10, 10);
      expect(result.isPartialSuccess()).assertEqual(false);
    });

    it('BatchInsertResult.isAllFailed should return true when all fail', 0, () => {
      const result = BatchInsertResult.createPartialSuccess(0, 10, [], 'All failed');
      expect(result.isAllFailed()).assertEqual(true);
    });

    it('BatchInsertResult.isAllFailed should return false when some succeed', 0, () => {
      const result = BatchInsertResult.createPartialSuccess(5, 10, [], '');
      expect(result.isAllFailed()).assertEqual(false);
    });

    it('BatchInsertResult.getFailedCount should return correct count', 0, () => {
      const result = BatchInsertResult.createPartialSuccess(7, 10, [], '');
      expect(result.getFailedCount()).assertEqual(3);
    });

    it('BatchInsertResult.getSuccessRate should return correct rate', 0, () => {
      const result = BatchInsertResult.createPartialSuccess(5, 10, [], '');
      expect(result.getSuccessRate()).assertEqual(50);
    });

    it('BatchInsertResult.getSuccessRate should return 0 for empty total', 0, () => {
      const result = new BatchInsertResult();
      expect(result.getSuccessRate()).assertEqual(0);
    });

    it('saveAll should return failure results when database not initialized', 0, async () => {
      setupUserEntity();
      const repo = new Repository('User');
      const entities = [
        createEntityData('User1', 'user1@test.com'),
        createEntityData('User2', 'user2@test.com')
      ];

      const results = await repo.saveAll(entities);
      expect(results.length).assertEqual(2);
      expect(results[0].success).assertEqual(false);
      expect(results[1].success).assertEqual(false);
    });

    it('batchInsert should return success for empty array', 0, async () => {
      setupUserEntity();
      const repo = new Repository('User');

      const result = await repo.batchInsert([]);
      expect(result.success).assertEqual(true);
      expect(result.insertedCount).assertEqual(0);
      expect(result.totalCount).assertEqual(0);
    });

    it('batchInsert should fail when database not initialized', 0, async () => {
      setupUserEntity();
      const repo = new Repository('User');
      const entities = [
        createEntityData('User1', 'user1@test.com')
      ];

      const result = await repo.batchInsert(entities);
      expect(result.success).assertEqual(false);
      expect(result.errorMessage.length > 0).assertEqual(true);
    });

    it('batchInsert with useTransaction=true should fail when database not initialized', 0, async () => {
      setupUserEntity();
      const repo = new Repository('User');
      const entities = [createEntityData('User1', 'user1@test.com')];
      const options = BatchInsertOptions.createDefault();

      const result = await repo.batchInsert(entities, options);
      expect(result.success).assertEqual(false);
    });

    it('batchInsert with useTransaction=false should fail when database not initialized', 0, async () => {
      setupUserEntity();
      const repo = new Repository('User');
      const entities = [createEntityData('User1', 'user1@test.com')];
      const options = BatchInsertOptions.createFast();

      const result = await repo.batchInsert(entities, options);
      expect(result.success).assertEqual(false);
    });

    it('batchInsert with executeHooks=true should process hooks', 0, async () => {
      setupUserEntity();
      const repo = new Repository('User');
      const entities = [createEntityData('User1', 'user1@test.com')];
      const options = new BatchInsertOptions(true, true, false);

      const result = await repo.batchInsert(entities, options);
      expect(result.success).assertEqual(false);
    });

    it('batchInsert with executeHooks=false should skip hooks', 0, async () => {
      setupUserEntity();
      const repo = new Repository('User');
      const entities = [createEntityData('User1', 'user1@test.com')];
      const options = new BatchInsertOptions(true, false, false);

      const result = await repo.batchInsert(entities, options);
      expect(result.success).assertEqual(false);
    });

    it('batchInsert with executeValidation=true should validate data', 0, async () => {
      setupUserEntity();
      const repo = new Repository('User');
      const entities = [createEntityData('User1', 'user1@test.com')];
      const options = new BatchInsertOptions(true, false, true);

      const result = await repo.batchInsert(entities, options);
      expect(result.success).assertEqual(false);
    });

    it('batchInsert with executeValidation=false should skip validation', 0, async () => {
      setupUserEntity();
      const repo = new Repository('User');
      const entities = [createEntityData('User1', 'user1@test.com')];
      const options = new BatchInsertOptions(true, false, false);

      const result = await repo.batchInsert(entities, options);
      expect(result.success).assertEqual(false);
    });
  });
}
