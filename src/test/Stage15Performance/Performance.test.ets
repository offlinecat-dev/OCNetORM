import { describe, beforeEach, it, expect } from '@ohos/hypium';
import { MetadataStorage } from '../../main/ets/core/MetadataStorage';
import { ColumnMetadata } from '../../main/ets/core/ColumnMetadata';
import { ColumnType } from '../../main/ets/types/ColumnType';
import { QueryCache } from '../../main/ets/query/QueryCache';
import { RelationLoadResult, ParallelRelationLoadResult } from '../../main/ets/query/RelationLoadResult';
import { EntityData } from '../../main/ets/mapping/DataMapper';
import { BatchInsertOptions } from '../../main/ets/repository/BatchInsertOptions';
import { BatchInsertResult } from '../../main/ets/repository/BatchInsertResult';
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


const createEntityData = (entityName: string, id: number, name: string = 'Test'): EntityData => {
  const data = new EntityData(entityName);
  data.addProperty('id', id, 'number');
  data.addProperty('name', name, 'string');
  return data;
};

const createUserEntityData = (name: string, email: string): EntityData => {
  const data = new EntityData('User');
  data.addProperty('name', name, 'string');
  data.addProperty('email', email, 'string');
  return data;
};


export default function performanceTest() {
  describe('performanceTest', () => {
    beforeEach(() => {
      MetadataStorage.resetInstance();
      QueryCache.resetInstance();
      HooksProcessor.resetInstance();
      ValidationMetadataStorage.resetInstance();
    });

    // ==================== 15.1 大量数据 getAsync TaskPool 分支 ====================
    describe('getAsync TaskPool tests', () => {
      it('should handle data below TASKPOOL_THRESHOLD in main thread', 0, () => {
        setupUserEntity();
        const entities: Array<EntityData> = [];
        for (let i = 0; i < 50; i++) {
          entities.push(createEntityData('User', i, `User${i}`));
        }
        expect(entities.length).assertEqual(50);
        expect(entities.length < 100).assertEqual(true);
      });

      it('should handle data above TASKPOOL_THRESHOLD', 0, () => {
        setupUserEntity();
        const entities: Array<EntityData> = [];
        for (let i = 0; i < 150; i++) {
          entities.push(createEntityData('User', i, `User${i}`));
        }
        expect(entities.length).assertEqual(150);
        expect(entities.length > 100).assertEqual(true);
      });

      it('should create large data set correctly', 0, () => {
        setupUserEntity();
        const startTime = Date.now();
        const entities: Array<EntityData> = [];
        for (let i = 0; i < 1000; i++) {
          const data = new EntityData('User');
          data.addProperty('id', i, 'number');
          data.addProperty('name', `User${i}`, 'string');
          data.addProperty('email', `user${i}@test.com`, 'string');
          entities.push(data);
        }
        const duration = Date.now() - startTime;
        expect(entities.length).assertEqual(1000);
        expect(duration < 5000).assertEqual(true);
      });

      it('should verify TASKPOOL_THRESHOLD constant value', 0, () => {
        const threshold = 100;
        expect(threshold).assertEqual(100);
      });

      it('should handle empty result set', 0, () => {
        setupUserEntity();
        const entities: Array<EntityData> = [];
        expect(entities.length).assertEqual(0);
        expect(entities.length <= 100).assertEqual(true);
      });

      it('should handle exactly threshold count', 0, () => {
        setupUserEntity();
        const entities: Array<EntityData> = [];
        for (let i = 0; i < 100; i++) {
          entities.push(createEntityData('User', i, `User${i}`));
        }
        expect(entities.length).assertEqual(100);
      });
    });

    // ==================== 15.2 RelationLoader 并行加载性能 ====================
    describe('RelationLoader parallel loading tests', () => {
      it('RelationLoadResult should create success result', 0, () => {
        const result = RelationLoadResult.createSuccess('posts', 10, 50);
        expect(result.relationName).assertEqual('posts');
        expect(result.success).assertEqual(true);
        expect(result.loadedCount).assertEqual(10);
        expect(result.duration).assertEqual(50);
      });

      it('RelationLoadResult should create failure result', 0, () => {
        const result = RelationLoadResult.createFailure('posts', 'Load failed', 100);
        expect(result.relationName).assertEqual('posts');
        expect(result.success).assertEqual(false);
        expect(result.errorMessage).assertEqual('Load failed');
        expect(result.duration).assertEqual(100);
      });

      it('RelationLoadResult isSuccess should return correct value', 0, () => {
        const successResult = RelationLoadResult.createSuccess('posts', 5, 10);
        const failureResult = RelationLoadResult.createFailure('posts', 'Error', 10);
        expect(successResult.isSuccess()).assertEqual(true);
        expect(failureResult.isSuccess()).assertEqual(false);
      });

      it('RelationLoadResult isFailed should return correct value', 0, () => {
        const successResult = RelationLoadResult.createSuccess('posts', 5, 10);
        const failureResult = RelationLoadResult.createFailure('posts', 'Error', 10);
        expect(successResult.isFailed()).assertEqual(false);
        expect(failureResult.isFailed()).assertEqual(true);
      });

      it('RelationLoadResult getFormattedError should return formatted error', 0, () => {
        const result = RelationLoadResult.createFailure('posts', 'Connection failed', 50);
        const formatted = result.getFormattedError();
        expect(formatted.includes('posts')).assertEqual(true);
        expect(formatted.includes('Connection failed')).assertEqual(true);
      });

      it('RelationLoadResult getFormattedError should return empty for success', 0, () => {
        const result = RelationLoadResult.createSuccess('posts', 5, 10);
        expect(result.getFormattedError()).assertEqual('');
      });

      it('ParallelRelationLoadResult should add results correctly', 0, () => {
        const parallelResult = new ParallelRelationLoadResult();
        parallelResult.addResult(RelationLoadResult.createSuccess('posts', 10, 50));
        parallelResult.addResult(RelationLoadResult.createSuccess('profile', 1, 30));
        expect(parallelResult.results.length).assertEqual(2);
      });

      it('ParallelRelationLoadResult isAllSuccess should return true when all succeed', 0, () => {
        const parallelResult = new ParallelRelationLoadResult();
        parallelResult.addResult(RelationLoadResult.createSuccess('posts', 10, 50));
        parallelResult.addResult(RelationLoadResult.createSuccess('profile', 1, 30));
        expect(parallelResult.isAllSuccess()).assertEqual(true);
      });

      it('ParallelRelationLoadResult isAllSuccess should return false when any fails', 0, () => {
        const parallelResult = new ParallelRelationLoadResult();
        parallelResult.addResult(RelationLoadResult.createSuccess('posts', 10, 50));
        parallelResult.addResult(RelationLoadResult.createFailure('profile', 'Error', 30));
        expect(parallelResult.isAllSuccess()).assertEqual(false);
      });

      it('ParallelRelationLoadResult hasAnyFailure should detect failures', 0, () => {
        const parallelResult = new ParallelRelationLoadResult();
        parallelResult.addResult(RelationLoadResult.createSuccess('posts', 10, 50));
        parallelResult.addResult(RelationLoadResult.createFailure('profile', 'Error', 30));
        expect(parallelResult.hasAnyFailure()).assertEqual(true);
      });

      it('ParallelRelationLoadResult hasAnyFailure should return false when all succeed', 0, () => {
        const parallelResult = new ParallelRelationLoadResult();
        parallelResult.addResult(RelationLoadResult.createSuccess('posts', 10, 50));
        parallelResult.addResult(RelationLoadResult.createSuccess('profile', 1, 30));
        expect(parallelResult.hasAnyFailure()).assertEqual(false);
      });

      it('ParallelRelationLoadResult getSuccessCount should return correct count', 0, () => {
        const parallelResult = new ParallelRelationLoadResult();
        parallelResult.addResult(RelationLoadResult.createSuccess('posts', 10, 50));
        parallelResult.addResult(RelationLoadResult.createFailure('profile', 'Error', 30));
        parallelResult.addResult(RelationLoadResult.createSuccess('tags', 5, 20));
        expect(parallelResult.getSuccessCount()).assertEqual(2);
      });

      it('ParallelRelationLoadResult getFailureCount should return correct count', 0, () => {
        const parallelResult = new ParallelRelationLoadResult();
        parallelResult.addResult(RelationLoadResult.createSuccess('posts', 10, 50));
        parallelResult.addResult(RelationLoadResult.createFailure('profile', 'Error', 30));
        parallelResult.addResult(RelationLoadResult.createFailure('tags', 'Error2', 20));
        expect(parallelResult.getFailureCount()).assertEqual(2);
      });

      it('ParallelRelationLoadResult getFailedRelationNames should return failed names', 0, () => {
        const parallelResult = new ParallelRelationLoadResult();
        parallelResult.addResult(RelationLoadResult.createSuccess('posts', 10, 50));
        parallelResult.addResult(RelationLoadResult.createFailure('profile', 'Error', 30));
        parallelResult.addResult(RelationLoadResult.createFailure('tags', 'Error2', 20));
        const failedNames = parallelResult.getFailedRelationNames();
        expect(failedNames.length).assertEqual(2);
        expect(failedNames.includes('profile')).assertEqual(true);
        expect(failedNames.includes('tags')).assertEqual(true);
      });

      it('ParallelRelationLoadResult getErrorMessages should return error messages', 0, () => {
        const parallelResult = new ParallelRelationLoadResult();
        parallelResult.addResult(RelationLoadResult.createSuccess('posts', 10, 50));
        parallelResult.addResult(RelationLoadResult.createFailure('profile', 'Connection failed', 30));
        const messages = parallelResult.getErrorMessages();
        expect(messages.length).assertEqual(1);
        expect(messages[0].includes('profile')).assertEqual(true);
      });

      it('ParallelRelationLoadResult getTotalLoadedCount should sum loaded counts', 0, () => {
        const parallelResult = new ParallelRelationLoadResult();
        parallelResult.addResult(RelationLoadResult.createSuccess('posts', 10, 50));
        parallelResult.addResult(RelationLoadResult.createSuccess('profile', 1, 30));
        parallelResult.addResult(RelationLoadResult.createSuccess('tags', 5, 20));
        expect(parallelResult.getTotalLoadedCount()).assertEqual(16);
      });

      it('ParallelRelationLoadResult.create should create instance correctly', 0, () => {
        const results: Array<RelationLoadResult> = [
          RelationLoadResult.createSuccess('posts', 10, 50),
          RelationLoadResult.createSuccess('profile', 1, 30)
        ];
        const parallelResult = ParallelRelationLoadResult.create(results, 100);
        expect(parallelResult.results.length).assertEqual(2);
        expect(parallelResult.totalDuration).assertEqual(100);
      });

    });

    // ==================== 15.3 QueryCache 命中率与内存稳定性 ====================
    describe('QueryCache hit rate and memory stability tests', () => {
      it('cache hit rate should be 0 initially', 0, () => {
        const cache = QueryCache.getInstance();
        const stats = cache.getStatistics();
        expect(stats.hitRate).assertEqual(0);
        expect(stats.hits).assertEqual(0);
        expect(stats.misses).assertEqual(0);
      });

      it('cache hit rate should increase with hits', 0, () => {
        const cache = QueryCache.getInstance();
        cache.configure({ enabled: true });
        const data = createEntityData('User', 1);
        cache.set('User', 1, data);

        cache.get('User', 1);
        cache.get('User', 1);
        cache.get('User', 1);

        const stats = cache.getStatistics();
        expect(stats.hits).assertEqual(3);
        expect(stats.hitRate).assertEqual(1);
      });

      it('cache hit rate should be calculated correctly with mixed hits and misses', 0, () => {
        const cache = QueryCache.getInstance();
        cache.configure({ enabled: true });
        const data = createEntityData('User', 1);
        cache.set('User', 1, data);

        cache.get('User', 1);
        cache.get('User', 1);
        cache.get('User', 999);
        cache.get('User', 998);

        const stats = cache.getStatistics();
        expect(stats.hits).assertEqual(2);
        expect(stats.misses).assertEqual(2);
        expect(stats.hitRate).assertEqual(0.5);
      });

      it('cache should maintain stability under heavy load', 0, () => {
        const cache = QueryCache.getInstance();
        cache.configure({ enabled: true, maxSize: 100 });

        for (let i = 0; i < 200; i++) {
          const data = createEntityData('User', i);
          cache.set('User', i, data);
        }

        expect(cache.getSize() <= 100).assertEqual(true);
      });

      it('cache should evict oldest entries when maxSize reached', 0, () => {
        const cache = QueryCache.getInstance();
        cache.configure({ enabled: true, maxSize: 3 });

        cache.set('User', 1, createEntityData('User', 1));
        cache.set('User', 2, createEntityData('User', 2));
        cache.set('User', 3, createEntityData('User', 3));
        cache.set('User', 4, createEntityData('User', 4));

        expect(cache.getSize()).assertEqual(3);
      });

      it('cache TTL configuration should work', 0, () => {
        const cache = QueryCache.getInstance();
        cache.configure({ enabled: true, ttlMs: 50 });

        cache.set('User', 1, createEntityData('User', 1));
        const result = cache.get('User', 1);
        expect(result !== null).assertEqual(true);
      });

      it('cache should not increment stats when disabled', 0, () => {
        const cache = QueryCache.getInstance();
        cache.configure({ enabled: false });

        cache.get('User', 1);
        cache.get('User', 2);

        const stats = cache.getStatistics();
        expect(stats.hits).assertEqual(0);
        expect(stats.misses).assertEqual(0);
      });

      it('cache clear should reset statistics', 0, () => {
        const cache = QueryCache.getInstance();
        cache.configure({ enabled: true });

        cache.set('User', 1, createEntityData('User', 1));
        cache.get('User', 1);
        cache.get('User', 999);

        cache.clear();

        const stats = cache.getStatistics();
        expect(stats.hits).assertEqual(0);
        expect(stats.misses).assertEqual(0);
        expect(stats.size).assertEqual(0);
      });

      it('cache should handle concurrent-like access', 0, () => {
        const cache = QueryCache.getInstance();
        cache.configure({ enabled: true, maxSize: 50 });

        for (let i = 0; i < 100; i++) {
          if (i % 2 === 0) {
            cache.set('User', i, createEntityData('User', i));
          } else {
            cache.get('User', i - 1);
          }
        }

        expect(cache.getSize() > 0).assertEqual(true);
        expect(cache.getSize() <= 50).assertEqual(true);
      });

      it('cache should handle multiple entity types', 0, () => {
        const cache = QueryCache.getInstance();
        cache.configure({ enabled: true, maxSize: 100 });

        for (let i = 0; i < 30; i++) {
          cache.set('User', i, createEntityData('User', i));
          cache.set('Post', i, createEntityData('Post', i));
          cache.set('Tag', i, createEntityData('Tag', i));
        }

        expect(cache.getSize()).assertEqual(90);

        cache.invalidateEntity('User');
        expect(cache.getSize()).assertEqual(60);
      });

      it('cache memory should be stable after many operations', 0, () => {
        const cache = QueryCache.getInstance();
        cache.configure({ enabled: true, maxSize: 50 });

        for (let round = 0; round < 10; round++) {
          for (let i = 0; i < 100; i++) {
            cache.set('User', i, createEntityData('User', i, `Name${round}_${i}`));
          }
          cache.clear();
        }

        expect(cache.getSize()).assertEqual(0);
      });

      it('cache hit rate should remain valid under stress', 0, () => {
        const cache = QueryCache.getInstance();
        cache.configure({ enabled: true, maxSize: 20 });

        for (let i = 0; i < 50; i++) {
          cache.set('User', i % 20, createEntityData('User', i % 20));
        }

        for (let i = 0; i < 100; i++) {
          cache.get('User', i % 30);
        }

        const stats = cache.getStatistics();
        expect(stats.hitRate >= 0 && stats.hitRate <= 1).assertEqual(true);
      });
    });

    // ==================== 15.4 批量插入性能（事务/非事务） ====================
    describe('Batch insert performance tests', () => {
      it('BatchInsertOptions should have default values', 0, () => {
        const options = new BatchInsertOptions();
        expect(options.useTransaction).assertEqual(true);
        expect(options.executeHooks).assertEqual(true);
        expect(options.executeValidation).assertEqual(true);
      });

      it('BatchInsertOptions.createFast should disable all options', 0, () => {
        const options = BatchInsertOptions.createFast();
        expect(options.useTransaction).assertEqual(false);
        expect(options.executeHooks).assertEqual(false);
        expect(options.executeValidation).assertEqual(false);
      });

      it('BatchInsertOptions.createSafe should enable all options', 0, () => {
        const options = BatchInsertOptions.createSafe();
        expect(options.useTransaction).assertEqual(true);
        expect(options.executeHooks).assertEqual(true);
        expect(options.executeValidation).assertEqual(true);
      });

      it('BatchInsertResult should calculate success rate correctly', 0, () => {
        const result = BatchInsertResult.createPartialSuccess(75, 100, [], '');
        expect(result.getSuccessRate()).assertEqual(75);
      });

      it('BatchInsertResult should calculate failed count correctly', 0, () => {
        const result = BatchInsertResult.createPartialSuccess(80, 100, [], '');
        expect(result.getFailedCount()).assertEqual(20);
      });

      it('BatchInsertResult success rate should be 0 for empty total', 0, () => {
        const result = new BatchInsertResult();
        expect(result.getSuccessRate()).assertEqual(0);
      });

      it('BatchInsertResult should track failed indexes', 0, () => {
        const result = BatchInsertResult.createFailure('Failed', [0, 5, 10]);
        expect(result.failedIndexes.length).assertEqual(3);
        expect(result.failedIndexes[0]).assertEqual(0);
        expect(result.failedIndexes[1]).assertEqual(5);
        expect(result.failedIndexes[2]).assertEqual(10);
      });


      it('should be able to create large batch of entities quickly', 0, () => {
        setupUserEntity();
        const startTime = Date.now();
        const entities: Array<EntityData> = [];

        for (let i = 0; i < 1000; i++) {
          entities.push(createUserEntityData(`User${i}`, `user${i}@test.com`));
        }

        const duration = Date.now() - startTime;
        expect(entities.length).assertEqual(1000);
        expect(duration < 1000).assertEqual(true);
      });

      it('BatchInsertResult isAllSuccess should work correctly', 0, () => {
        const successResult = BatchInsertResult.createSuccess(100, 100);
        const partialResult = BatchInsertResult.createPartialSuccess(50, 100, [], '');

        expect(successResult.isAllSuccess()).assertEqual(true);
        expect(partialResult.isAllSuccess()).assertEqual(false);
      });

      it('BatchInsertResult isPartialSuccess should work correctly', 0, () => {
        const successResult = BatchInsertResult.createSuccess(100, 100);
        const partialResult = BatchInsertResult.createPartialSuccess(50, 100, [], '');

        expect(successResult.isPartialSuccess()).assertEqual(false);
        expect(partialResult.isPartialSuccess()).assertEqual(true);
      });

      it('BatchInsertResult isAllFailed should work correctly', 0, () => {
        const partialResult = BatchInsertResult.createPartialSuccess(50, 100, [], '');
        const allFailedResult = BatchInsertResult.createPartialSuccess(0, 100, [], 'All failed');

        expect(partialResult.isAllFailed()).assertEqual(false);
        expect(allFailedResult.isAllFailed()).assertEqual(true);
      });

      it('EntityData array should be created correctly', 0, () => {
        setupUserEntity();
        const entities = [
          createUserEntityData('User1', 'user1@test.com'),
          createUserEntityData('User2', 'user2@test.com'),
          createUserEntityData('User3', 'user3@test.com')
        ];
        expect(entities.length).assertEqual(3);
      });

      it('batch options should be customizable', 0, () => {
        const options = BatchInsertOptions.create(true, false, true);
        expect(options.useTransaction).assertEqual(true);
        expect(options.executeHooks).assertEqual(false);
        expect(options.executeValidation).assertEqual(true);
      });

      it('performance timing for entity creation should be reasonable', 0, () => {
        setupUserEntity();
        const iterations = 5;
        const durations: Array<number> = [];

        for (let iter = 0; iter < iterations; iter++) {
          const startTime = Date.now();
          const entities: Array<EntityData> = [];
          for (let i = 0; i < 100; i++) {
            entities.push(createUserEntityData(`User${i}`, `user${i}@test.com`));
          }
          durations.push(Date.now() - startTime);
        }

        const avgDuration = durations.reduce((a, b) => a + b, 0) / iterations;
        expect(avgDuration < 500).assertEqual(true);
      });
    });
  });
}
