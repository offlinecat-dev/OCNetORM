import { describe, beforeEach, it, expect } from '@ohos/hypium';
import { DatabaseManager } from '../../main/ets/database/DatabaseManager';
import { DatabaseConfig } from '../../main/ets/database/DatabaseConfig';
import { DatabaseNotInitializedError } from '../../main/ets/errors/DatabaseError';
import { QueryCache } from '../../main/ets/query/QueryCache';
import { Logger } from '../../main/ets/logging/Logger';
import { LogLevel } from '../../main/ets/logging/LogLevel';
import { relationalStore } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';

export default function databaseTest() {
  describe('databaseTest', () => {
    beforeEach(() => {
      DatabaseManager.resetInstance();
      QueryCache.resetInstance();
      Logger.resetInstance();
    });

    // ==================== DatabaseConfig 测试 ====================

    // 9.2 DatabaseConfig - constructor 默认值
    it('DatabaseConfig constructor should set default values', 0, () => {
      const config = new DatabaseConfig('test.db');
      expect(config.name).assertEqual('test.db');
      expect(config.securityLevel).assertEqual(relationalStore.SecurityLevel.S1);
      expect(config.encrypt).assertEqual(false);
      expect(config.enableLogger).assertEqual(false);
      expect(config.loggerLevel).assertEqual(LogLevel.INFO);
      expect(config.healthCheckIntervalMs).assertEqual(0);
      expect(config.enableQueryCache).assertEqual(false);
      expect(config.queryCacheMaxSize).assertEqual(100);
      expect(config.queryCacheTtlMs).assertEqual(60000);
    });

    it('DatabaseConfig constructor should accept custom securityLevel', 0, () => {
      const config = new DatabaseConfig('test.db', relationalStore.SecurityLevel.S2);
      expect(config.securityLevel).assertEqual(relationalStore.SecurityLevel.S2);
    });

    it('DatabaseConfig constructor should accept custom encrypt', 0, () => {
      const config = new DatabaseConfig('test.db', undefined, true);
      expect(config.encrypt).assertEqual(true);
    });

    it('DatabaseConfig constructor should accept custom enableLogger', 0, () => {
      const config = new DatabaseConfig('test.db', undefined, undefined, true);
      expect(config.enableLogger).assertEqual(true);
    });

    it('DatabaseConfig constructor should accept custom loggerLevel', 0, () => {
      const config = new DatabaseConfig('test.db', undefined, undefined, undefined, LogLevel.DEBUG);
      expect(config.loggerLevel).assertEqual(LogLevel.DEBUG);
    });

    it('DatabaseConfig constructor should accept all custom values', 0, () => {
      const config = new DatabaseConfig(
        'custom.db',
        relationalStore.SecurityLevel.S3,
        true,
        true,
        LogLevel.ERROR
      );
      expect(config.name).assertEqual('custom.db');
      expect(config.securityLevel).assertEqual(relationalStore.SecurityLevel.S3);
      expect(config.encrypt).assertEqual(true);
      expect(config.enableLogger).assertEqual(true);
      expect(config.loggerLevel).assertEqual(LogLevel.ERROR);
    });

    // 9.2 DatabaseConfig - setHealthCheckInterval
    it('setHealthCheckInterval should set interval value', 0, () => {
      const config = new DatabaseConfig('test.db');
      config.setHealthCheckInterval(5000);
      expect(config.healthCheckIntervalMs).assertEqual(5000);
    });

    it('setHealthCheckInterval should support method chaining', 0, () => {
      const config = new DatabaseConfig('test.db');
      const result = config.setHealthCheckInterval(3000);
      expect(result === config).assertEqual(true);
    });

    it('setHealthCheckInterval with 0 should disable health check', 0, () => {
      const config = new DatabaseConfig('test.db');
      config.setHealthCheckInterval(5000);
      config.setHealthCheckInterval(0);
      expect(config.healthCheckIntervalMs).assertEqual(0);
    });

    // 9.2 DatabaseConfig - setQueryCache
    it('setQueryCache should enable cache', 0, () => {
      const config = new DatabaseConfig('test.db');
      config.setQueryCache(true);
      expect(config.enableQueryCache).assertEqual(true);
    });

    it('setQueryCache should disable cache', 0, () => {
      const config = new DatabaseConfig('test.db');
      config.setQueryCache(true);
      config.setQueryCache(false);
      expect(config.enableQueryCache).assertEqual(false);
    });

    it('setQueryCache should set maxSize', 0, () => {
      const config = new DatabaseConfig('test.db');
      config.setQueryCache(true, 500);
      expect(config.queryCacheMaxSize).assertEqual(500);
    });

    it('setQueryCache should set ttlMs', 0, () => {
      const config = new DatabaseConfig('test.db');
      config.setQueryCache(true, undefined, 120000);
      expect(config.queryCacheTtlMs).assertEqual(120000);
    });

    it('setQueryCache should set all parameters', 0, () => {
      const config = new DatabaseConfig('test.db');
      config.setQueryCache(true, 200, 30000);
      expect(config.enableQueryCache).assertEqual(true);
      expect(config.queryCacheMaxSize).assertEqual(200);
      expect(config.queryCacheTtlMs).assertEqual(30000);
    });

    it('setQueryCache should support method chaining', 0, () => {
      const config = new DatabaseConfig('test.db');
      const result = config.setQueryCache(true);
      expect(result === config).assertEqual(true);
    });

    it('setQueryCache and setHealthCheckInterval should chain together', 0, () => {
      const config = new DatabaseConfig('test.db')
        .setHealthCheckInterval(5000)
        .setQueryCache(true, 300, 90000);
      expect(config.healthCheckIntervalMs).assertEqual(5000);
      expect(config.enableQueryCache).assertEqual(true);
      expect(config.queryCacheMaxSize).assertEqual(300);
      expect(config.queryCacheTtlMs).assertEqual(90000);
    });

    // ==================== DatabaseManager 测试 ====================

    // 9.1 DatabaseManager - 单例模式
    it('DatabaseManager should be singleton', 0, () => {
      const manager1 = DatabaseManager.getInstance();
      const manager2 = DatabaseManager.getInstance();
      expect(manager1 === manager2).assertEqual(true);
    });

    // 9.1 DatabaseManager - getStore 未初始化抛错
    it('getStore should throw DatabaseNotInitializedError when not initialized', 0, () => {
      const manager = DatabaseManager.getInstance();
      let threw = false;
      let errorType = '';
      try {
        manager.getStore();
      } catch (error) {
        threw = true;
        if (error instanceof DatabaseNotInitializedError) {
          errorType = 'DatabaseNotInitializedError';
        }
      }
      expect(threw).assertEqual(true);
      expect(errorType).assertEqual('DatabaseNotInitializedError');
    });

    // 9.1 DatabaseManager - isInitialized
    it('isInitialized should return false before initialization', 0, () => {
      const manager = DatabaseManager.getInstance();
      expect(manager.isInitialized()).assertEqual(false);
    });

    // 9.1 DatabaseManager - isHealthy
    it('isHealthy should return false before initialization', 0, () => {
      const manager = DatabaseManager.getInstance();
      expect(manager.isHealthy()).assertEqual(false);
    });

    // 9.1 DatabaseManager - getConfig
    it('getConfig should return null before initialization', 0, () => {
      const manager = DatabaseManager.getInstance();
      expect(manager.getConfig()).assertEqual(null);
    });

    // 9.1 DatabaseManager - close / resetInstance
    it('resetInstance should reset manager state', 0, () => {
      const manager1 = DatabaseManager.getInstance();
      DatabaseManager.resetInstance();
      const manager2 = DatabaseManager.getInstance();
      expect(manager1 === manager2).assertEqual(false);
    });

    it('resetInstance should clear initialization state', 0, () => {
      const manager = DatabaseManager.getInstance();
      DatabaseManager.resetInstance();
      const newManager = DatabaseManager.getInstance();
      expect(newManager.isInitialized()).assertEqual(false);
      expect(newManager.isHealthy()).assertEqual(false);
      expect(newManager.getConfig()).assertEqual(null);
    });

    it('close should reset state without throwing on uninitialized manager', 0, async () => {
      const manager = DatabaseManager.getInstance();
      let threw = false;
      try {
        await manager.close();
      } catch (e) {
        threw = true;
      }
      expect(threw).assertEqual(false);
    });

    // 9.1 DatabaseManager - getQueryCache
    it('getQueryCache should return QueryCache instance', 0, () => {
      const manager = DatabaseManager.getInstance();
      const cache = manager.getQueryCache();
      expect(cache !== null).assertEqual(true);
      expect(cache === QueryCache.getInstance()).assertEqual(true);
    });

    // 9.1 DatabaseManager - QueryCache 配置绑定 (验证配置逻辑)
    it('DatabaseConfig with enableQueryCache true should configure cache', 0, () => {
      const config = new DatabaseConfig('test.db');
      config.setQueryCache(true, 250, 45000);

      expect(config.enableQueryCache).assertEqual(true);
      expect(config.queryCacheMaxSize).assertEqual(250);
      expect(config.queryCacheTtlMs).assertEqual(45000);
    });

    it('DatabaseManager initialize should reapply runtime config when connection matches', 0, async () => {
      const manager = DatabaseManager.getInstance() as unknown as {
        store: relationalStore.RdbStore | null,
        initialized: boolean,
        healthy: boolean,
        config: DatabaseConfig | null
      };

      manager.store = {} as relationalStore.RdbStore;
      manager.initialized = true;
      manager.healthy = true;
      manager.config = new DatabaseConfig('test.db');

      QueryCache.getInstance().configure({ enabled: false });

      const newConfig = new DatabaseConfig('test.db');
      newConfig.setQueryCache(true, 321, 12345);

      let threw = false;
      try {
        await DatabaseManager.getInstance().initialize({} as unknown as Context, newConfig);
      } catch (e) {
        threw = true;
      }

      expect(threw).assertEqual(false);
      expect(QueryCache.getInstance().isEnabled()).assertEqual(true);
    });

    it('DatabaseManager ping should use querySql', 0, async () => {
      const manager = DatabaseManager.getInstance() as unknown as {
        store: relationalStore.RdbStore | null,
        initialized: boolean,
        healthy: boolean
      };

      let queryCalled = false;
      const fakeStore = {
        querySql: async () => {
          queryCalled = true;
          return { close: () => {} };
        }
      } as unknown as relationalStore.RdbStore;

      manager.store = fakeStore;
      manager.initialized = true;
      manager.healthy = true;

      const result = await DatabaseManager.getInstance().ping();
      expect(result).assertEqual(true);
      expect(queryCalled).assertEqual(true);
    });

    it('DatabaseConfig with enableQueryCache false should configure cache disabled', 0, () => {
      const config = new DatabaseConfig('test.db');
      config.setQueryCache(false);

      expect(config.enableQueryCache).assertEqual(false);
    });

    // 额外边界测试
    it('DatabaseConfig name should be set correctly', 0, () => {
      const config = new DatabaseConfig('my_database.db');
      expect(config.name).assertEqual('my_database.db');
    });

    it('DatabaseConfig should handle empty name', 0, () => {
      const config = new DatabaseConfig('');
      expect(config.name).assertEqual('');
    });

    it('DatabaseConfig should handle special characters in name', 0, () => {
      const config = new DatabaseConfig('test-db_v1.2.db');
      expect(config.name).assertEqual('test-db_v1.2.db');
    });

    it('setHealthCheckInterval should accept large values', 0, () => {
      const config = new DatabaseConfig('test.db');
      config.setHealthCheckInterval(3600000);
      expect(config.healthCheckIntervalMs).assertEqual(3600000);
    });

    it('setQueryCache should accept large maxSize', 0, () => {
      const config = new DatabaseConfig('test.db');
      config.setQueryCache(true, 10000);
      expect(config.queryCacheMaxSize).assertEqual(10000);
    });

    it('setQueryCache should accept large ttlMs', 0, () => {
      const config = new DatabaseConfig('test.db');
      config.setQueryCache(true, undefined, 86400000);
      expect(config.queryCacheTtlMs).assertEqual(86400000);
    });

    it('multiple resetInstance calls should not throw', 0, () => {
      let threw = false;
      try {
        DatabaseManager.resetInstance();
        DatabaseManager.resetInstance();
        DatabaseManager.resetInstance();
      } catch (e) {
        threw = true;
      }
      expect(threw).assertEqual(false);
    });

    it('getInstance after resetInstance should return fresh instance', 0, () => {
      DatabaseManager.getInstance();
      DatabaseManager.resetInstance();
      const manager = DatabaseManager.getInstance();
      expect(manager.isInitialized()).assertEqual(false);
    });

    it('getStore should throw consistent error type', 0, () => {
      const manager = DatabaseManager.getInstance();
      let errorCode = '';
      try {
        manager.getStore();
      } catch (error) {
        if (error instanceof DatabaseNotInitializedError) {
          errorCode = error.code;
        }
      }
      expect(errorCode.length > 0).assertEqual(true);
    });

    it('DatabaseConfig securityLevel S1 should be default', 0, () => {
      const config = new DatabaseConfig('test.db');
      expect(config.securityLevel).assertEqual(relationalStore.SecurityLevel.S1);
    });

    it('DatabaseConfig should support S2 security level', 0, () => {
      const config = new DatabaseConfig('secure.db', relationalStore.SecurityLevel.S2);
      expect(config.securityLevel).assertEqual(relationalStore.SecurityLevel.S2);
    });

    it('DatabaseConfig should support S3 security level', 0, () => {
      const config = new DatabaseConfig('secure.db', relationalStore.SecurityLevel.S3);
      expect(config.securityLevel).assertEqual(relationalStore.SecurityLevel.S3);
    });

    it('DatabaseConfig should support S4 security level', 0, () => {
      const config = new DatabaseConfig('secure.db', relationalStore.SecurityLevel.S4);
      expect(config.securityLevel).assertEqual(relationalStore.SecurityLevel.S4);
    });
  });
}
