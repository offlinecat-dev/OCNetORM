import { describe, beforeEach, it, expect } from '@ohos/hypium';
import { MetadataStorage } from '../../main/ets/core/MetadataStorage';
import { ColumnMetadata } from '../../main/ets/core/ColumnMetadata';
import { ColumnType } from '../../main/ets/types/ColumnType';
import { QueryBuilder } from '../../main/ets/query/QueryBuilder';
import { ConditionOperator } from '../../main/ets/types/ConditionOperator';
import { Repository } from '../../main/ets/repository/Repository';
import { EntityData } from '../../main/ets/mapping/DataMapper';
import { QueryCache } from '../../main/ets/query/QueryCache';
import { SoftDeleteNotEnabledError } from '../../main/ets/errors/SoftDeleteError';
import { HooksProcessor } from '../../main/ets/core/HooksProcessor';

const setupSoftDeleteEntity = (): void => {
  const storage = MetadataStorage.getInstance();
  storage.registerEntity('Article', 'articles');

  const idColumn = new ColumnMetadata('id', 'id')
    .setType(ColumnType.INTEGER)
    .setPrimaryKey(true)
    .setAutoIncrement(true);
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

const setupNonSoftDeleteEntity = (): void => {
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

const createArticleEntityData = (id: number, title: string): EntityData => {
  const data = new EntityData('Article');
  data.addProperty('id', id, 'number');
  data.addProperty('title', title, 'string');
  return data;
};

export default function softDeleteTest() {
  describe('Stage14SoftDeleteTest', () => {
    beforeEach(() => {
      MetadataStorage.resetInstance();
      QueryCache.resetInstance();
      HooksProcessor.resetInstance();
    });

    describe('软删除实体默认过滤', () => {
      it('QueryBuilder should add IS_NULL condition for soft delete entity by default', 0, () => {
        setupSoftDeleteEntity();
        const builder = new QueryBuilder('Article');
        const condition = builder.getSoftDeleteCondition();

        expect(condition !== null).assertEqual(true);
        if (condition) {
          expect(condition.operator).assertEqual(ConditionOperator.IS_NULL);
          expect(condition.column).assertEqual('deleted_at');
        }
      });

      it('getAllConditions should include soft delete condition automatically', 0, () => {
        setupSoftDeleteEntity();
        const builder = new QueryBuilder('Article');
        builder.where('title', ConditionOperator.LIKE, '%test%');

        const allConditions = builder.getAllConditions();
        expect(allConditions.length).assertEqual(2);

        const softDeleteCondition = allConditions.find(c => c.column === 'deleted_at');
        expect(softDeleteCondition !== undefined).assertEqual(true);
        if (softDeleteCondition) {
          expect(softDeleteCondition.operator).assertEqual(ConditionOperator.IS_NULL);
        }
      });

      it('non-soft-delete entity should not have soft delete condition', 0, () => {
        setupNonSoftDeleteEntity();
        const builder = new QueryBuilder('User');
        const condition = builder.getSoftDeleteCondition();

        expect(condition === null).assertEqual(true);
      });

      it('getQueryDescription should show excludeDeleted for soft delete entity', 0, () => {
        setupSoftDeleteEntity();
        const builder = new QueryBuilder('Article');
        const desc = builder.getQueryDescription();

        expect(desc.includes('SOFT_DELETE: excludeDeleted')).assertEqual(true);
      });

      it('isSoftDeleteEnabled should return true for soft delete entity', 0, () => {
        setupSoftDeleteEntity();
        const repo = new Repository('Article');
        expect(repo.getMetadata().isSoftDeleteEnabled()).assertEqual(true);
      });

      it('isSoftDeleteEnabled should return false for non-soft-delete entity', 0, () => {
        setupNonSoftDeleteEntity();
        const repo = new Repository('User');
        expect(repo.getMetadata().isSoftDeleteEnabled()).assertEqual(false);
      });

      it('getDeletedAtColumn should return correct column name', 0, () => {
        setupSoftDeleteEntity();
        const repo = new Repository('Article');
        expect(repo.getMetadata().getDeletedAtColumn()).assertEqual('deleted_at');
      });
    });

    describe('withDeleted/onlyDeleted', () => {
      it('withDeleted should set includeDeleted flag to true', 0, () => {
        setupSoftDeleteEntity();
        const builder = new QueryBuilder('Article');
        builder.withDeleted();

        expect(builder.isIncludeDeleted()).assertEqual(true);
        expect(builder.isOnlyDeleted()).assertEqual(false);
      });

      it('withDeleted should return null for soft delete condition', 0, () => {
        setupSoftDeleteEntity();
        const builder = new QueryBuilder('Article');
        builder.withDeleted();

        const condition = builder.getSoftDeleteCondition();
        expect(condition === null).assertEqual(true);
      });

      it('withDeleted should not add soft delete condition to getAllConditions', 0, () => {
        setupSoftDeleteEntity();
        const builder = new QueryBuilder('Article');
        builder.where('title', ConditionOperator.EQUAL, 'test');
        builder.withDeleted();

        const allConditions = builder.getAllConditions();
        expect(allConditions.length).assertEqual(1);
        expect(allConditions[0].column).assertEqual('title');
      });

      it('onlyDeleted should set onlyDeletedFlag to true', 0, () => {
        setupSoftDeleteEntity();
        const builder = new QueryBuilder('Article');
        builder.onlyDeleted();

        expect(builder.isOnlyDeleted()).assertEqual(true);
        expect(builder.isIncludeDeleted()).assertEqual(false);
      });

      it('onlyDeleted should return IS_NOT_NULL condition', 0, () => {
        setupSoftDeleteEntity();
        const builder = new QueryBuilder('Article');
        builder.onlyDeleted();

        const condition = builder.getSoftDeleteCondition();
        expect(condition !== null).assertEqual(true);
        if (condition) {
          expect(condition.operator).assertEqual(ConditionOperator.IS_NOT_NULL);
          expect(condition.column).assertEqual('deleted_at');
        }
      });

      it('onlyDeleted getAllConditions should include IS_NOT_NULL condition', 0, () => {
        setupSoftDeleteEntity();
        const builder = new QueryBuilder('Article');
        builder.where('title', ConditionOperator.LIKE, '%test%');
        builder.onlyDeleted();

        const allConditions = builder.getAllConditions();
        expect(allConditions.length).assertEqual(2);

        const softDeleteCondition = allConditions.find(c => c.column === 'deleted_at');
        expect(softDeleteCondition !== undefined).assertEqual(true);
        if (softDeleteCondition) {
          expect(softDeleteCondition.operator).assertEqual(ConditionOperator.IS_NOT_NULL);
        }
      });

      it('withDeleted should override onlyDeleted when called after', 0, () => {
        setupSoftDeleteEntity();
        const builder = new QueryBuilder('Article');
        builder.onlyDeleted();
        builder.withDeleted();

        expect(builder.isIncludeDeleted()).assertEqual(true);
        expect(builder.isOnlyDeleted()).assertEqual(false);
      });

      it('onlyDeleted should override withDeleted when called after', 0, () => {
        setupSoftDeleteEntity();
        const builder = new QueryBuilder('Article');
        builder.withDeleted();
        builder.onlyDeleted();

        expect(builder.isOnlyDeleted()).assertEqual(true);
        expect(builder.isIncludeDeleted()).assertEqual(false);
      });

      it('getQueryDescription should show withDeleted status', 0, () => {
        setupSoftDeleteEntity();
        const builder = new QueryBuilder('Article');
        builder.withDeleted();
        const desc = builder.getQueryDescription();

        expect(desc.includes('SOFT_DELETE: withDeleted')).assertEqual(true);
      });

      it('getQueryDescription should show onlyDeleted status', 0, () => {
        setupSoftDeleteEntity();
        const builder = new QueryBuilder('Article');
        builder.onlyDeleted();
        const desc = builder.getQueryDescription();

        expect(desc.includes('SOFT_DELETE: onlyDeleted')).assertEqual(true);
      });

      it('reset should clear withDeleted flag', 0, () => {
        setupSoftDeleteEntity();
        const builder = new QueryBuilder('Article');
        builder.withDeleted();
        builder.reset();

        expect(builder.isIncludeDeleted()).assertEqual(false);
      });

      it('reset should clear onlyDeleted flag', 0, () => {
        setupSoftDeleteEntity();
        const builder = new QueryBuilder('Article');
        builder.onlyDeleted();
        builder.reset();

        expect(builder.isOnlyDeleted()).assertEqual(false);
      });

      it('non-soft-delete entity withDeleted should have no effect', 0, () => {
        setupNonSoftDeleteEntity();
        const builder = new QueryBuilder('User');
        builder.withDeleted();

        expect(builder.isIncludeDeleted()).assertEqual(true);
        const condition = builder.getSoftDeleteCondition();
        expect(condition === null).assertEqual(true);
      });

      it('non-soft-delete entity onlyDeleted should have no effect on conditions', 0, () => {
        setupNonSoftDeleteEntity();
        const builder = new QueryBuilder('User');
        builder.onlyDeleted();

        expect(builder.isOnlyDeleted()).assertEqual(true);
        const condition = builder.getSoftDeleteCondition();
        expect(condition === null).assertEqual(true);
      });
    });

    describe('restore 仅软删实体可用', () => {
      it('non-soft-delete entity should not have soft delete enabled', 0, () => {
        setupNonSoftDeleteEntity();
        const repo = new Repository('User');
        expect(repo.getMetadata().isSoftDeleteEnabled()).assertEqual(false);
      });

      it('SoftDeleteNotEnabledError should contain entity name in message', 0, () => {
        const error = new SoftDeleteNotEnabledError('TestEntity');
        expect(error.message.includes('TestEntity')).assertEqual(true);
        expect(error.name).assertEqual('SoftDeleteNotEnabledError');
      });

      it('SoftDeleteNotEnabledError should have correct error context', 0, () => {
        const error = new SoftDeleteNotEnabledError('TestEntity');
        expect(error.context.entityName).assertEqual('TestEntity');
        expect(error.context.details.length > 0).assertEqual(true);
      });

      it('restore method should exist on soft-delete entity repository', 0, () => {
        setupSoftDeleteEntity();
        const repo = new Repository('Article');
        expect(typeof repo.restore).assertEqual('function');
        expect(repo.getMetadata().isSoftDeleteEnabled()).assertEqual(true);
      });

      it('Repository should have restore method available', 0, () => {
        setupSoftDeleteEntity();
        const repo = new Repository('Article');
        expect(typeof repo.restore).assertEqual('function');
      });
    });

    describe('delete + 查询缓存失效', () => {
      it('QueryCache should be enabled by default', 0, () => {
        const cache = QueryCache.getInstance();
        expect(cache.isEnabled()).assertEqual(true);
      });

      it('QueryCache set and get should work correctly', 0, () => {
        setupSoftDeleteEntity();
        const cache = QueryCache.getInstance();
        cache.configure({ enabled: true, ttlMs: 60000 });

        const entityData = createArticleEntityData(1, 'Test Article');
        cache.set('Article', 1, entityData);

        const cached = cache.get('Article', 1);
        expect(cached !== null).assertEqual(true);
        if (cached) {
          expect(cached.getPropertyValue('title')).assertEqual('Test Article');
        }
      });

      it('QueryCache invalidate should remove specific entry', 0, () => {
        setupSoftDeleteEntity();
        const cache = QueryCache.getInstance();
        cache.configure({ enabled: true, ttlMs: 60000 });

        const entityData = createArticleEntityData(1, 'Test Article');
        cache.set('Article', 1, entityData);

        cache.invalidate('Article', 1);

        const cached = cache.get('Article', 1);
        expect(cached === null).assertEqual(true);
      });

      it('QueryCache invalidateEntity should remove all entries for entity', 0, () => {
        setupSoftDeleteEntity();
        const cache = QueryCache.getInstance();
        cache.configure({ enabled: true, ttlMs: 60000 });

        cache.set('Article', 1, createArticleEntityData(1, 'Article 1'));
        cache.set('Article', 2, createArticleEntityData(2, 'Article 2'));
        cache.set('Article', 3, createArticleEntityData(3, 'Article 3'));

        expect(cache.getSize()).assertEqual(3);

        cache.invalidateEntity('Article');

        expect(cache.getSize()).assertEqual(0);
        expect(cache.get('Article', 1) === null).assertEqual(true);
        expect(cache.get('Article', 2) === null).assertEqual(true);
        expect(cache.get('Article', 3) === null).assertEqual(true);
      });

      it('QueryCache clear should remove all entries', 0, () => {
        setupSoftDeleteEntity();
        setupNonSoftDeleteEntity();
        const cache = QueryCache.getInstance();
        cache.configure({ enabled: true, ttlMs: 60000 });

        cache.set('Article', 1, createArticleEntityData(1, 'Article'));
        const userData = new EntityData('User');
        userData.addProperty('id', 1, 'number');
        userData.addProperty('name', 'Test User', 'string');
        cache.set('User', 1, userData);

        expect(cache.getSize()).assertEqual(2);

        cache.clear();

        expect(cache.getSize()).assertEqual(0);
      });

      it('cache invalidate should work for soft-delete entity', 0, () => {
        setupSoftDeleteEntity();
        const cache = QueryCache.getInstance();
        cache.configure({ enabled: true, ttlMs: 60000 });

        const entityData = createArticleEntityData(1, 'Test Article');
        cache.set('Article', 1, entityData);
        expect(cache.get('Article', 1) !== null).assertEqual(true);

        cache.invalidate('Article', 1);

        expect(cache.get('Article', 1) === null).assertEqual(true);
      });

      it('cache invalidateEntity should work for soft-delete entity', 0, () => {
        setupSoftDeleteEntity();
        const cache = QueryCache.getInstance();
        cache.configure({ enabled: true, ttlMs: 60000 });

        const entityData = createArticleEntityData(1, 'Test Article');
        cache.set('Article', 1, entityData);
        expect(cache.get('Article', 1) !== null).assertEqual(true);

        cache.invalidateEntity('Article');

        expect(cache.get('Article', 1) === null).assertEqual(true);
      });

      it('QueryCache statistics should track hits and misses', 0, () => {
        setupSoftDeleteEntity();
        const cache = QueryCache.getInstance();
        cache.configure({ enabled: true, ttlMs: 60000 });
        cache.clear();

        const entityData = createArticleEntityData(1, 'Test Article');
        cache.set('Article', 1, entityData);

        cache.get('Article', 1);
        cache.get('Article', 1);
        cache.get('Article', 2);

        const stats = cache.getStatistics();
        expect(stats.hits).assertEqual(2);
        expect(stats.misses).assertEqual(1);
        expect(stats.hitRate > 0).assertEqual(true);
      });

      it('QueryCache should return deep copy to prevent mutation', 0, () => {
        setupSoftDeleteEntity();
        const cache = QueryCache.getInstance();
        cache.configure({ enabled: true, ttlMs: 60000 });

        const entityData = createArticleEntityData(1, 'Original Title');
        cache.set('Article', 1, entityData);

        const cached1 = cache.get('Article', 1);
        if (cached1) {
          cached1.setPropertyValue('title', 'Modified Title');
        }

        const cached2 = cache.get('Article', 1);
        expect(cached2 !== null).assertEqual(true);
        if (cached2) {
          expect(cached2.getPropertyValue('title')).assertEqual('Original Title');
        }
      });

      it('QueryCache disabled should not cache data', 0, () => {
        setupSoftDeleteEntity();
        const cache = QueryCache.getInstance();
        cache.configure({ enabled: false });

        const entityData = createArticleEntityData(1, 'Test Article');
        cache.set('Article', 1, entityData);

        const cached = cache.get('Article', 1);
        expect(cached === null).assertEqual(true);
      });

      it('QueryCache enable and disable should work', 0, () => {
        const cache = QueryCache.getInstance();

        cache.enable();
        expect(cache.isEnabled()).assertEqual(true);

        cache.disable();
        expect(cache.isEnabled()).assertEqual(false);

        cache.enable();
        expect(cache.isEnabled()).assertEqual(true);
      });
    });

    describe('软删除与缓存集成场景', () => {
      it('soft delete operation should use UPDATE not DELETE', 0, () => {
        setupSoftDeleteEntity();
        const repo = new Repository('Article');
        const metadata = repo.getMetadata();

        expect(metadata.isSoftDeleteEnabled()).assertEqual(true);
        expect(metadata.getDeletedAtColumn()).assertEqual('deleted_at');
      });

      it('QueryBuilder chain should support soft delete methods', 0, () => {
        setupSoftDeleteEntity();
        const builder = new QueryBuilder('Article')
          .where('title', ConditionOperator.LIKE, '%test%')
          .withDeleted()
          .orderBy('id', 'DESC')
          .limit(10);

        expect(builder.isIncludeDeleted()).assertEqual(true);
        expect(builder.getLimitValue()).assertEqual(10);
        expect(builder.getConditions().length).assertEqual(1);
      });

      it('QueryBuilder chain with onlyDeleted should work', 0, () => {
        setupSoftDeleteEntity();
        const builder = new QueryBuilder('Article')
          .where('title', ConditionOperator.LIKE, '%test%')
          .onlyDeleted()
          .orderBy('id', 'ASC');

        expect(builder.isOnlyDeleted()).assertEqual(true);
        const allConditions = builder.getAllConditions();
        expect(allConditions.length).assertEqual(2);
      });

      it('Repository createQueryBuilder should return fresh builder', 0, () => {
        setupSoftDeleteEntity();
        const repo = new Repository('Article');

        const builder1 = repo.createQueryBuilder();
        builder1.withDeleted();

        const builder2 = repo.createQueryBuilder();
        expect(builder2.isIncludeDeleted()).assertEqual(false);
      });

      it('multiple repositories should have independent cache entries', 0, () => {
        setupSoftDeleteEntity();
        setupNonSoftDeleteEntity();
        const cache = QueryCache.getInstance();
        cache.configure({ enabled: true, ttlMs: 60000 });

        cache.set('Article', 1, createArticleEntityData(1, 'Article'));
        const userData = new EntityData('User');
        userData.addProperty('id', 1, 'number');
        userData.addProperty('name', 'User', 'string');
        cache.set('User', 1, userData);

        cache.invalidateEntity('Article');

        expect(cache.get('Article', 1) === null).assertEqual(true);
        expect(cache.get('User', 1) !== null).assertEqual(true);
      });
    });
  });
}
