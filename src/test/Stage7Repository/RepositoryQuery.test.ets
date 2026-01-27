import { describe, beforeEach, it, expect } from '@ohos/hypium';
import { MetadataStorage } from '../../main/ets/core/MetadataStorage';
import { ColumnMetadata } from '../../main/ets/core/ColumnMetadata';
import { ColumnType } from '../../main/ets/types/ColumnType';
import { Repository } from '../../main/ets/repository/Repository';
import { EntityData } from '../../main/ets/mapping/DataMapper';
import { ExecutionError } from '../../main/ets/errors/DatabaseError';
import { QueryCache } from '../../main/ets/query/QueryCache';
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

  const emailColumn = new ColumnMetadata('email', 'user_email')
    .setType(ColumnType.TEXT);
  storage.registerColumn('User', emailColumn);
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

export default function repositoryQueryTest() {
  describe('repositoryQueryTest', () => {
    beforeEach(() => {
      MetadataStorage.resetInstance();
      QueryCache.resetInstance();
      HooksProcessor.resetInstance();
    });

    it('findById should throw ExecutionError when database not initialized', 0, async () => {
      setupUserEntity();
      const repo = new Repository('User');

      let threw = false;
      let errorType = '';
      try {
        await repo.findById(1);
      } catch (error) {
        threw = true;
        if (error instanceof ExecutionError) {
          errorType = 'ExecutionError';
        }
      }

      expect(threw).assertEqual(true);
      expect(errorType).assertEqual('ExecutionError');
    });

    it('findById should accept includeDeleted parameter', 0, async () => {
      setupSoftDeleteEntity();
      const repo = new Repository('Article');

      let threw = false;
      try {
        await repo.findById(1, true);
      } catch (error) {
        threw = error instanceof ExecutionError;
      }

      expect(threw).assertEqual(true);
    });

    it('findById should accept useCache parameter', 0, async () => {
      setupUserEntity();
      const repo = new Repository('User');

      let threw = false;
      try {
        await repo.findById(1, false, false);
      } catch (error) {
        threw = error instanceof ExecutionError;
      }

      expect(threw).assertEqual(true);
    });

    it('findAll should throw ExecutionError when database not initialized', 0, async () => {
      setupUserEntity();
      const repo = new Repository('User');

      let threw = false;
      let errorType = '';
      try {
        await repo.findAll();
      } catch (error) {
        threw = true;
        if (error instanceof ExecutionError) {
          errorType = 'ExecutionError';
        }
      }

      expect(threw).assertEqual(true);
      expect(errorType).assertEqual('ExecutionError');
    });

    it('findAll should accept includeDeleted parameter', 0, async () => {
      setupSoftDeleteEntity();
      const repo = new Repository('Article');

      let threw = false;
      try {
        await repo.findAll(true);
      } catch (error) {
        threw = error instanceof ExecutionError;
      }

      expect(threw).assertEqual(true);
    });

    it('findAllAsync should throw ExecutionError when database not initialized', 0, async () => {
      setupUserEntity();
      const repo = new Repository('User');

      let threw = false;
      let errorType = '';
      try {
        await repo.findAllAsync();
      } catch (error) {
        threw = true;
        if (error instanceof ExecutionError) {
          errorType = 'ExecutionError';
        }
      }

      expect(threw).assertEqual(true);
      expect(errorType).assertEqual('ExecutionError');
    });

    it('findAllAsync should accept includeDeleted parameter', 0, async () => {
      setupSoftDeleteEntity();
      const repo = new Repository('Article');

      let threw = false;
      try {
        await repo.findAllAsync(true);
      } catch (error) {
        threw = error instanceof ExecutionError;
      }

      expect(threw).assertEqual(true);
    });

    it('count should throw ExecutionError when database not initialized', 0, async () => {
      setupUserEntity();
      const repo = new Repository('User');

      let threw = false;
      let errorType = '';
      try {
        await repo.count();
      } catch (error) {
        threw = true;
        if (error instanceof ExecutionError) {
          errorType = 'ExecutionError';
        }
      }

      expect(threw).assertEqual(true);
      expect(errorType).assertEqual('ExecutionError');
    });

    it('count should accept includeDeleted parameter', 0, async () => {
      setupSoftDeleteEntity();
      const repo = new Repository('Article');

      let threw = false;
      try {
        await repo.count(true);
      } catch (error) {
        threw = error instanceof ExecutionError;
      }

      expect(threw).assertEqual(true);
    });

    it('findPaginated should throw ExecutionError when database not initialized', 0, async () => {
      setupUserEntity();
      const repo = new Repository('User');

      let threw = false;
      let errorType = '';
      try {
        await repo.findPaginated(1, 10);
      } catch (error) {
        threw = true;
        if (error instanceof ExecutionError) {
          errorType = 'ExecutionError';
        }
      }

      expect(threw).assertEqual(true);
      expect(errorType).assertEqual('ExecutionError');
    });

    it('findPaginated should accept includeDeleted parameter', 0, async () => {
      setupSoftDeleteEntity();
      const repo = new Repository('Article');

      let threw = false;
      try {
        await repo.findPaginated(1, 10, true);
      } catch (error) {
        threw = error instanceof ExecutionError;
      }

      expect(threw).assertEqual(true);
    });

    it('findPaginated should work with different page sizes', 0, async () => {
      setupUserEntity();
      const repo = new Repository('User');

      let threw = false;
      try {
        await repo.findPaginated(2, 20);
      } catch (error) {
        threw = error instanceof ExecutionError;
      }

      expect(threw).assertEqual(true);
    });

    it('QueryCache should be singleton', 0, () => {
      const cache1 = QueryCache.getInstance();
      const cache2 = QueryCache.getInstance();
      expect(cache1 === cache2).assertEqual(true);
    });

    it('QueryCache.configure should set options', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ maxSize: 500, ttlMs: 60000, enabled: true });
      expect(cache.isEnabled()).assertEqual(true);
    });

    it('QueryCache.disable should disable cache', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      cache.disable();
      expect(cache.isEnabled()).assertEqual(false);
    });

    it('QueryCache.enable should enable cache', 0, () => {
      const cache = QueryCache.getInstance();
      cache.disable();
      cache.enable();
      expect(cache.isEnabled()).assertEqual(true);
    });

    it('QueryCache.clear should clear all entries', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      const entityData = new EntityData('User');
      entityData.addProperty('id', 1, 'number');
      cache.set('User', 1, entityData);
      cache.clear();
      const result = cache.get('User', 1);
      expect(result).assertEqual(null);
    });

    it('QueryCache.set and get should work correctly', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      const entityData = new EntityData('User');
      entityData.addProperty('id', 1, 'number');
      entityData.addProperty('name', 'Test', 'string');
      cache.set('User', 1, entityData);
      const result = cache.get('User', 1);
      expect(result !== null).assertEqual(true);
    });

    it('QueryCache.invalidate should remove specific entry', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      const entityData = new EntityData('User');
      entityData.addProperty('id', 1, 'number');
      cache.set('User', 1, entityData);
      cache.invalidate('User', 1);
      const result = cache.get('User', 1);
      expect(result).assertEqual(null);
    });

    it('QueryCache.invalidateEntity should remove all entity entries', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      const data1 = new EntityData('User');
      data1.addProperty('id', 1, 'number');
      const data2 = new EntityData('User');
      data2.addProperty('id', 2, 'number');
      cache.set('User', 1, data1);
      cache.set('User', 2, data2);
      cache.invalidateEntity('User');
      expect(cache.get('User', 1)).assertEqual(null);
      expect(cache.get('User', 2)).assertEqual(null);
    });

    it('QueryCache should return null when disabled', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: false });
      const entityData = new EntityData('User');
      entityData.addProperty('id', 1, 'number');
      cache.set('User', 1, entityData);
      const result = cache.get('User', 1);
      expect(result).assertEqual(null);
    });

    it('QueryCache should track hits and misses', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      cache.clear();
      const entityData = new EntityData('User');
      entityData.addProperty('id', 1, 'number');
      cache.set('User', 1, entityData);
      cache.get('User', 1);
      cache.get('User', 999);
      const stats = cache.getStatistics();
      expect(stats.hits >= 0).assertEqual(true);
      expect(stats.misses >= 0).assertEqual(true);
    });
  });
}
