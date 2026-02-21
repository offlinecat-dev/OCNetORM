import { describe, beforeEach, it, expect } from '@ohos/hypium';
import { QueryCache, CacheEntry, QueryCacheConfig, CacheStatistics } from '../../main/ets/query/QueryCache';
import { EntityData } from '../../main/ets/mapping/EntityData';

const createEntityData = (entityName: string, id: number, name: string = 'Test'): EntityData => {
  const data = new EntityData(entityName);
  data.addProperty('id', id, 'number');
  data.addProperty('name', name, 'string');
  return data;
};

const createEntityDataWithTransient = (entityName: string, id: number): EntityData => {
  const data = new EntityData(entityName);
  data.addProperty('id', id, 'number');
  data.setTransient('tempKey', 'tempValue');
  return data;
};

const createEntityDataWithRelated = (entityName: string, id: number): EntityData => {
  const data = new EntityData(entityName);
  data.addProperty('id', id, 'number');
  const relatedData = new EntityData('Profile');
  relatedData.addProperty('id', 100, 'number');
  data.setRelatedSingle('profile', relatedData);
  return data;
};

const sleep = (ms: number): Promise<void> => {
  return new Promise<void>((resolve) => {
    setTimeout(() => {
      resolve();
    }, ms);
  });
};

export default function queryCacheTest() {
  describe('queryCacheTest', () => {
    beforeEach(() => {
      QueryCache.resetInstance();
    });

    // ==================== CacheEntry 测试 ====================
    it('CacheEntry should store data and timestamp', 0, () => {
      const entityData = createEntityData('User', 1);
      const timestamp = Date.now();
      const entry = new CacheEntry(entityData, timestamp);

      expect(entry.data !== null).assertEqual(true);
      expect(entry.data.entityName).assertEqual('User');
      expect(entry.timestamp).assertEqual(timestamp);
    });

    // ==================== 单例模式测试 ====================
    it('QueryCache should be singleton', 0, () => {
      const cache1 = QueryCache.getInstance();
      const cache2 = QueryCache.getInstance();
      expect(cache1 === cache2).assertEqual(true);
    });

    it('resetInstance should create new instance', 0, () => {
      const cache1 = QueryCache.getInstance();
      cache1.configure({ maxSize: 999 });
      QueryCache.resetInstance();
      const cache2 = QueryCache.getInstance();
      expect(cache2.getSize()).assertEqual(0);
    });

    // ==================== configure 测试 ====================
    it('configure should set maxSize', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ maxSize: 50 });
      expect(cache.isEnabled()).assertEqual(true);
    });

    it('configure should set ttlMs', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ ttlMs: 30000 });
      expect(cache.isEnabled()).assertEqual(true);
    });

    it('configure should set enabled', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: false });
      expect(cache.isEnabled()).assertEqual(false);
    });

    it('configure should set all options at once', 0, () => {
      const cache = QueryCache.getInstance();
      const config: QueryCacheConfig = {
        maxSize: 200,
        ttlMs: 120000,
        enabled: true
      };
      cache.configure(config);
      expect(cache.isEnabled()).assertEqual(true);
    });

    it('configure with partial options should only update specified', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      cache.configure({ maxSize: 300 });
      expect(cache.isEnabled()).assertEqual(true);
    });

    // ==================== set/get 基本功能测试 ====================
    it('set and get should work correctly', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      const entityData = createEntityData('User', 1, 'Alice');
      cache.set('User', 1, entityData);
      const result = cache.get('User', 1);
      expect(result !== null).assertEqual(true);
      expect(result?.getPropertyValue('name')).assertEqual('Alice');
    });

    it('get should return null for non-existent entry', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      const result = cache.get('User', 999);
      expect(result).assertEqual(null);
    });

    it('keys should not collide when id contains null character', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });

      const plain = new EntityData('User');
      plain.addProperty('id', 'abc', 'string');
      plain.addProperty('name', 'Plain', 'string');

      const withNull = new EntityData('User');
      withNull.addProperty('id', 'abc\u0000def', 'string');
      withNull.addProperty('name', 'WithNull', 'string');

      cache.set('User', 'abc', plain);
      cache.set('User', 'abc\u0000def', withNull);

      expect(cache.get('User', 'abc')?.getPropertyValue('name')).assertEqual('Plain');
      expect(cache.get('User', 'abc\u0000def')?.getPropertyValue('name')).assertEqual('WithNull');
    });

    it('same entity and id should be isolated by namespace', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });

      cache.setNamespace('db_a');
      cache.set('User', 1, createEntityData('User', 1, 'Alice_A'));

      cache.setNamespace('db_b');
      expect(cache.get('User', 1)).assertEqual(null);
      cache.set('User', 1, createEntityData('User', 1, 'Alice_B'));

      cache.setNamespace('db_a');
      expect(cache.get('User', 1)?.getPropertyValue('name')).assertEqual('Alice_A');
      cache.setNamespace('db_b');
      expect(cache.get('User', 1)?.getPropertyValue('name')).assertEqual('Alice_B');
    });

    it('invalidateEntity should handle entityName with null character safely', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      cache.set('User', 1, createEntityData('User', 1, 'UserOnly'));
      cache.set('User\u0000Archive', 1, createEntityData('User\u0000Archive', 1, 'Archived'));

      cache.invalidateEntity('User\u0000Archive');

      expect(cache.get('User\u0000Archive', 1)).assertEqual(null);
      expect(cache.get('User', 1)?.getPropertyValue('name')).assertEqual('UserOnly');
    });

    it('set should not store when disabled', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: false });
      const entityData = createEntityData('User', 1);
      cache.set('User', 1, entityData);
      cache.configure({ enabled: true });
      const result = cache.get('User', 1);
      expect(result).assertEqual(null);
    });

    it('get should return null when disabled', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      const entityData = createEntityData('User', 1);
      cache.set('User', 1, entityData);
      cache.configure({ enabled: false });
      const result = cache.get('User', 1);
      expect(result).assertEqual(null);
    });

    // ==================== 深拷贝测试 ====================
    it('get should return deep clone - modifying result should not affect cache', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      const entityData = createEntityData('User', 1, 'Original');
      cache.set('User', 1, entityData);

      const result1 = cache.get('User', 1);
      if (result1 !== null) {
        result1.addProperty('name', 'Modified', 'string');
      }

      const result2 = cache.get('User', 1);
      expect(result2?.getPropertyValue('name')).assertEqual('Original');
    });

    it('set should store deep clone - modifying original should not affect cache', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      const entityData = createEntityData('User', 1, 'Original');
      cache.set('User', 1, entityData);

      entityData.addProperty('name', 'Modified', 'string');

      const result = cache.get('User', 1);
      expect(result?.getPropertyValue('name')).assertEqual('Original');
    });

    it('set should deep clone related entity from original data', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      const entityData = createEntityDataWithRelated('User', 1);
      cache.set('User', 1, entityData);

      entityData.getRelatedSingle('profile')?.setPropertyValue('id', 777);

      const result = cache.get('User', 1);
      expect(result?.getRelatedSingle('profile')?.getPropertyValue('id')).assertEqual(100);
    });

    it('deep clone should preserve transient data', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      const entityData = createEntityDataWithTransient('User', 1);
      cache.set('User', 1, entityData);

      const result = cache.get('User', 1);
      expect(result?.getTransient('tempKey')).assertEqual('tempValue');
    });

    it('deep clone should preserve related data', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      const entityData = createEntityDataWithRelated('User', 1);
      cache.set('User', 1, entityData);

      const result = cache.get('User', 1);
      const related = result?.getRelatedValue('profile');
      expect(related !== null && related !== undefined).assertEqual(true);
      expect(related?.singleEntity?.getPropertyValue('id')).assertEqual(100);
    });

    it('deep clone should isolate related single entity mutation', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      const entityData = createEntityDataWithRelated('User', 1);
      cache.set('User', 1, entityData);

      const result1 = cache.get('User', 1);
      result1?.getRelatedSingle('profile')?.setPropertyValue('id', 999);

      const result2 = cache.get('User', 1);
      expect(result2?.getRelatedSingle('profile')?.getPropertyValue('id')).assertEqual(100);
    });

    it('deep clone should preserve related array', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      const entityData = new EntityData('User');
      entityData.addProperty('id', 1, 'number');
      const post1 = new EntityData('Post');
      post1.addProperty('id', 10, 'number');
      const post2 = new EntityData('Post');
      post2.addProperty('id', 20, 'number');
      entityData.setRelatedArray('posts', [post1, post2]);

      cache.set('User', 1, entityData);
      const result = cache.get('User', 1);
      const related = result?.getRelatedValue('posts');
      expect(related?.isArray).assertEqual(true);
      expect(related?.entityArray.length).assertEqual(2);
    });

    it('deep clone should isolate related array entity mutation', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      const entityData = new EntityData('User');
      entityData.addProperty('id', 1, 'number');
      const post = new EntityData('Post');
      post.addProperty('id', 10, 'number');
      entityData.setRelatedArray('posts', [post]);
      cache.set('User', 1, entityData);

      const result1 = cache.get('User', 1);
      if (result1 !== null) {
        result1.getRelatedArray('posts')[0].setPropertyValue('id', 888);
      }

      const result2 = cache.get('User', 1);
      const relatedPosts = result2 ? result2.getRelatedArray('posts') : [];
      expect(relatedPosts.length).assertEqual(1);
      expect(relatedPosts[0].getPropertyValue('id')).assertEqual(10);
    });

    it('deep clone should handle cyclic related entities', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      const user = new EntityData('User');
      user.addProperty('id', 1, 'number');
      const profile = new EntityData('Profile');
      profile.addProperty('id', 100, 'number');
      user.setRelatedSingle('profile', profile);
      profile.setRelatedSingle('user', user);

      cache.set('User', 1, user);

      const result = cache.get('User', 1);
      expect(result?.getRelatedSingle('profile') !== null).assertEqual(true);
      expect(result?.getRelatedSingle('profile')?.getRelatedSingle('user') !== null).assertEqual(true);
    });

    // ==================== TTL 过期测试 ====================
    it('get should return null for expired entry', 0, async () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true, ttlMs: 50 });
      const entityData = createEntityData('User', 1);
      cache.set('User', 1, entityData);

      await sleep(100);

      const result = cache.get('User', 1);
      expect(result).assertEqual(null);
    });

    it('get should return data before TTL expires', 0, async () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true, ttlMs: 5000 });
      const entityData = createEntityData('User', 1);
      cache.set('User', 1, entityData);

      await sleep(10);

      const result = cache.get('User', 1);
      expect(result !== null).assertEqual(true);
    });

    it('expired entry should be deleted on access', 0, async () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true, ttlMs: 50 });
      const entityData = createEntityData('User', 1);
      cache.set('User', 1, entityData);
      expect(cache.getSize()).assertEqual(1);

      await sleep(100);

      cache.get('User', 1);
      expect(cache.getSize()).assertEqual(0);
    });

    // ==================== invalidate 测试 ====================
    it('invalidate should remove specific entry', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      cache.set('User', 1, createEntityData('User', 1));
      cache.set('User', 2, createEntityData('User', 2));

      cache.invalidate('User', 1);

      expect(cache.get('User', 1)).assertEqual(null);
      expect(cache.get('User', 2) !== null).assertEqual(true);
    });

    it('invalidate non-existent entry should not throw', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      let threw = false;
      try {
        cache.invalidate('User', 999);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertEqual(false);
    });

    // ==================== invalidateEntity 测试 ====================
    it('invalidateEntity should remove all entries for entity', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      cache.set('User', 1, createEntityData('User', 1));
      cache.set('User', 2, createEntityData('User', 2));
      cache.set('User', 3, createEntityData('User', 3));
      cache.set('Post', 1, createEntityData('Post', 1));

      cache.invalidateEntity('User');

      expect(cache.get('User', 1)).assertEqual(null);
      expect(cache.get('User', 2)).assertEqual(null);
      expect(cache.get('User', 3)).assertEqual(null);
      expect(cache.get('Post', 1) !== null).assertEqual(true);
    });

    it('invalidateEntity should only affect current namespace', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });

      cache.setNamespace('db_a');
      cache.set('User', 1, createEntityData('User', 1, 'A_User'));
      cache.setNamespace('db_b');
      cache.set('User', 1, createEntityData('User', 1, 'B_User'));

      cache.setNamespace('db_a');
      cache.invalidateEntity('User');
      expect(cache.get('User', 1)).assertEqual(null);

      cache.setNamespace('db_b');
      expect(cache.get('User', 1)?.getPropertyValue('name')).assertEqual('B_User');
    });

    it('invalidateEntity for non-existent entity should not throw', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      let threw = false;
      try {
        cache.invalidateEntity('NonExistent');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertEqual(false);
    });

    // ==================== clear 测试 ====================
    it('clear should remove all entries', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      cache.set('User', 1, createEntityData('User', 1));
      cache.set('User', 2, createEntityData('User', 2));
      cache.set('Post', 1, createEntityData('Post', 1));

      cache.clear();

      expect(cache.getSize()).assertEqual(0);
      expect(cache.get('User', 1)).assertEqual(null);
    });

    it('clear should reset statistics', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      cache.set('User', 1, createEntityData('User', 1));
      cache.get('User', 1);
      cache.get('User', 999);

      cache.clear();

      const stats = cache.getStatistics();
      expect(stats.hits).assertEqual(0);
      expect(stats.misses).assertEqual(0);
    });

    // ==================== evictOldest 测试 ====================
    it('evictOldest should remove oldest entry when maxSize reached', 0, async () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true, maxSize: 2 });

      cache.set('User', 1, createEntityData('User', 1));
      await sleep(10);
      cache.set('User', 2, createEntityData('User', 2));
      await sleep(10);
      cache.set('User', 3, createEntityData('User', 3));

      expect(cache.getSize()).assertEqual(2);
      expect(cache.get('User', 1)).assertEqual(null);
    });

    it('evictOldest should keep newer entries', 0, async () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true, maxSize: 2 });

      cache.set('User', 1, createEntityData('User', 1));
      await sleep(10);
      cache.set('User', 2, createEntityData('User', 2));
      await sleep(10);
      cache.set('User', 3, createEntityData('User', 3));

      expect(cache.get('User', 2) !== null).assertEqual(true);
      expect(cache.get('User', 3) !== null).assertEqual(true);
    });

    it('evictOldest with maxSize 1 should always keep last entry', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true, maxSize: 1 });

      cache.set('User', 1, createEntityData('User', 1));
      cache.set('User', 2, createEntityData('User', 2));
      cache.set('User', 3, createEntityData('User', 3));

      expect(cache.getSize()).assertEqual(1);
      expect(cache.get('User', 3) !== null).assertEqual(true);
    });

    // ==================== hits/misses/hitRate 统计测试 ====================
    it('getStatistics should return correct initial values', 0, () => {
      const cache = QueryCache.getInstance();
      const stats = cache.getStatistics();

      expect(stats.hits).assertEqual(0);
      expect(stats.misses).assertEqual(0);
      expect(stats.size).assertEqual(0);
      expect(stats.hitRate).assertEqual(0);
    });

    it('hits should increment on cache hit', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      cache.set('User', 1, createEntityData('User', 1));

      cache.get('User', 1);
      cache.get('User', 1);

      const stats = cache.getStatistics();
      expect(stats.hits).assertEqual(2);
    });

    it('misses should increment on cache miss', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });

      cache.get('User', 1);
      cache.get('User', 2);

      const stats = cache.getStatistics();
      expect(stats.misses).assertEqual(2);
    });

    it('hitRate should be calculated correctly', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      cache.set('User', 1, createEntityData('User', 1));

      cache.get('User', 1);
      cache.get('User', 1);
      cache.get('User', 999);
      cache.get('User', 888);

      const stats = cache.getStatistics();
      expect(stats.hits).assertEqual(2);
      expect(stats.misses).assertEqual(2);
      expect(stats.hitRate).assertEqual(0.5);
    });

    it('hitRate should be 0 when no accesses', 0, () => {
      const cache = QueryCache.getInstance();
      const stats = cache.getStatistics();
      expect(stats.hitRate).assertEqual(0);
    });

    it('hitRate should be 1 when all hits', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      cache.set('User', 1, createEntityData('User', 1));

      cache.get('User', 1);
      cache.get('User', 1);
      cache.get('User', 1);

      const stats = cache.getStatistics();
      expect(stats.hitRate).assertEqual(1);
    });

    it('counters should scale down near MAX_SAFE_INTEGER and continue increment', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      cache.set('User', 1, createEntityData('User', 1));

      cache.setStatisticsForTest(Number.MAX_SAFE_INTEGER - 1, Number.MAX_SAFE_INTEGER - 1);

      cache.get('User', 1);
      const afterScale = cache.getStatistics();
      expect(afterScale.hits < Number.MAX_SAFE_INTEGER).assertEqual(true);
      expect(afterScale.misses < Number.MAX_SAFE_INTEGER).assertEqual(true);
      expect(afterScale.hitRate <= 1).assertEqual(true);

      cache.get('User', 999);
      const afterMiss = cache.getStatistics();
      expect(afterMiss.misses).assertEqual(afterScale.misses + 1);
    });

    it('size should reflect current cache entries', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });

      expect(cache.getStatistics().size).assertEqual(0);

      cache.set('User', 1, createEntityData('User', 1));
      expect(cache.getStatistics().size).assertEqual(1);

      cache.set('User', 2, createEntityData('User', 2));
      expect(cache.getStatistics().size).assertEqual(2);

      cache.invalidate('User', 1);
      expect(cache.getStatistics().size).assertEqual(1);
    });

    // ==================== enable/disable 测试 ====================
    it('enable should enable cache', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: false });
      cache.enable();
      expect(cache.isEnabled()).assertEqual(true);
    });

    it('disable should disable cache', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      cache.disable();
      expect(cache.isEnabled()).assertEqual(false);
    });

    it('isEnabled should return current state', 0, () => {
      const cache = QueryCache.getInstance();
      cache.enable();
      expect(cache.isEnabled()).assertEqual(true);
      cache.disable();
      expect(cache.isEnabled()).assertEqual(false);
    });

    it('cache should stop working after disable', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      cache.set('User', 1, createEntityData('User', 1));

      cache.disable();
      const result = cache.get('User', 1);

      expect(result).assertEqual(null);
    });

    it('cache should resume working after enable', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      cache.set('User', 1, createEntityData('User', 1));
      cache.disable();
      cache.enable();

      const result = cache.get('User', 1);
      expect(result !== null).assertEqual(true);
    });

    // ==================== getSize 测试 ====================
    it('getSize should return 0 for empty cache', 0, () => {
      const cache = QueryCache.getInstance();
      expect(cache.getSize()).assertEqual(0);
    });

    it('getSize should return correct count', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      cache.set('User', 1, createEntityData('User', 1));
      cache.set('User', 2, createEntityData('User', 2));
      expect(cache.getSize()).assertEqual(2);
    });

    // ==================== 边界条件测试 ====================
    it('should handle string id', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      const entityData = createEntityData('User', 1);
      cache.set('User', 'abc-123', entityData);
      const result = cache.get('User', 'abc-123');
      expect(result !== null).assertEqual(true);
    });

    it('should handle special characters in entity name', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      const entityData = new EntityData('User_Special');
      entityData.addProperty('id', 1, 'number');
      cache.set('User_Special', 1, entityData);
      const result = cache.get('User_Special', 1);
      expect(result !== null).assertEqual(true);
    });

    it('should handle zero as id', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      const entityData = createEntityData('User', 0);
      cache.set('User', 0, entityData);
      const result = cache.get('User', 0);
      expect(result !== null).assertEqual(true);
    });

    it('should handle negative id', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      const entityData = createEntityData('User', -1);
      cache.set('User', -1, entityData);
      const result = cache.get('User', -1);
      expect(result !== null).assertEqual(true);
    });

    it('should handle overwriting existing entry', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      cache.set('User', 1, createEntityData('User', 1, 'First'));
      cache.set('User', 1, createEntityData('User', 1, 'Second'));

      const result = cache.get('User', 1);
      expect(result?.getPropertyValue('name')).assertEqual('Second');
    });

    it('should differentiate between different entities with same id', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: true });
      cache.set('User', 1, createEntityData('User', 1, 'UserName'));
      cache.set('Post', 1, createEntityData('Post', 1, 'PostName'));

      const userResult = cache.get('User', 1);
      const postResult = cache.get('Post', 1);

      expect(userResult?.entityName).assertEqual('User');
      expect(postResult?.entityName).assertEqual('Post');
    });

    it('statistics should not increment when cache is disabled', 0, () => {
      const cache = QueryCache.getInstance();
      cache.configure({ enabled: false });

      cache.get('User', 1);
      cache.get('User', 2);

      const stats = cache.getStatistics();
      expect(stats.hits).assertEqual(0);
      expect(stats.misses).assertEqual(0);
    });
  });
}
