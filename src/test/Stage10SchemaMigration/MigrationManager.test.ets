import { describe, beforeEach, it, expect } from '@ohos/hypium';
import { relationalStore } from '@kit.ArkData';
import {
  MigrationManager,
  MigrationExecutionResult,
  AutoMigrationMode,
  SchemaMigrationExecutionResult
} from '../../main/ets/schema/MigrationManager';
import { Migration, MigrationResult, MigrationDirection } from '../../main/ets/schema/Migration';
import { SchemaDiffResult } from '../../main/ets/schema/SchemaDiffer';
import { MetadataStorage } from '../../main/ets/core/MetadataStorage';

class TestMigration implements Migration {
  version: number;
  description: string;
  upCalled: boolean = false;
  downCalled: boolean = false;
  shouldFail: boolean = false;

  constructor(version: number, description: string, shouldFail: boolean = false) {
    this.version = version;
    this.description = description;
    this.shouldFail = shouldFail;
  }

  async up(store: relationalStore.RdbStore): Promise<void> {
    this.upCalled = true;
    if (this.shouldFail) {
      throw new Error('Migration up failed');
    }
  }

  async down(store: relationalStore.RdbStore): Promise<void> {
    this.downCalled = true;
    if (this.shouldFail) {
      throw new Error('Migration down failed');
    }
  }
}

export default function migrationManagerTest() {
  describe('migrationManagerTest', () => {
    let manager: MigrationManager;

    beforeEach(() => {
      MetadataStorage.resetInstance();
      manager = new MigrationManager({ enableLog: false });
    });

    // ==================== 10.4 MigrationManager ====================

    // register - 正常注册
    it('register should add migration', 0, () => {
      const migration = new TestMigration(1, 'Create users table');
      manager.register(migration);
      expect(manager.getMigrationCount()).assertEqual(1);
    });

    it('register should add multiple migrations', 0, () => {
      manager.register(new TestMigration(1, 'Migration 1'));
      manager.register(new TestMigration(2, 'Migration 2'));
      manager.register(new TestMigration(3, 'Migration 3'));
      expect(manager.getMigrationCount()).assertEqual(3);
    });

    // register - 重复版本抛错
    it('register should throw on duplicate version', 0, () => {
      const migration1 = new TestMigration(1, 'First');
      const migration2 = new TestMigration(1, 'Duplicate');
      manager.register(migration1);

      let threw = false;
      try {
        manager.register(migration2);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertEqual(true);
    });

    // registerAll - 批量注册
    it('registerAll should add all migrations', 0, () => {
      const migrations: Array<Migration> = [];
      migrations.push(new TestMigration(1, 'Migration 1'));
      migrations.push(new TestMigration(2, 'Migration 2'));
      migrations.push(new TestMigration(3, 'Migration 3'));

      manager.registerAll(migrations);
      expect(manager.getMigrationCount()).assertEqual(3);
    });

    // registerAll - 重复版本忽略
    it('registerAll should ignore duplicate versions', 0, () => {
      const migrations: Array<Migration> = [];
      migrations.push(new TestMigration(1, 'Migration 1'));
      migrations.push(new TestMigration(1, 'Duplicate'));
      migrations.push(new TestMigration(2, 'Migration 2'));

      manager.registerAll(migrations);
      expect(manager.getMigrationCount()).assertEqual(2);
    });

    // getMigrationsByOrder - 排序测试
    it('getMigrationsByOrder should return sorted migrations', 0, () => {
      manager.register(new TestMigration(3, 'Third'));
      manager.register(new TestMigration(1, 'First'));
      manager.register(new TestMigration(2, 'Second'));

      const sorted = manager.getMigrationsByOrder();
      expect(sorted.length).assertEqual(3);
      expect(sorted[0].version).assertEqual(1);
      expect(sorted[1].version).assertEqual(2);
      expect(sorted[2].version).assertEqual(3);
    });

    it('getMigrationsByOrder should handle single migration', 0, () => {
      manager.register(new TestMigration(5, 'Only'));
      const sorted = manager.getMigrationsByOrder();
      expect(sorted.length).assertEqual(1);
      expect(sorted[0].version).assertEqual(5);
    });

    it('getMigrationsByOrder should return empty array when no migrations', 0, () => {
      const sorted = manager.getMigrationsByOrder();
      expect(sorted.length).assertEqual(0);
    });

    // getPendingMigrations - 待执行迁移
    it('getPendingMigrations should return migrations after current version', 0, () => {
      manager.register(new TestMigration(1, 'First'));
      manager.register(new TestMigration(2, 'Second'));
      manager.register(new TestMigration(3, 'Third'));

      const pending = manager.getPendingMigrations(1);
      expect(pending.length).assertEqual(2);
      expect(pending[0].version).assertEqual(2);
      expect(pending[1].version).assertEqual(3);
    });

    it('getPendingMigrations should return all migrations when version is 0', 0, () => {
      manager.register(new TestMigration(1, 'First'));
      manager.register(new TestMigration(2, 'Second'));

      const pending = manager.getPendingMigrations(0);
      expect(pending.length).assertEqual(2);
    });

    it('getPendingMigrations should return empty when all executed', 0, () => {
      manager.register(new TestMigration(1, 'First'));
      manager.register(new TestMigration(2, 'Second'));

      const pending = manager.getPendingMigrations(2);
      expect(pending.length).assertEqual(0);
    });

    it('getPendingMigrations should return empty when version exceeds latest', 0, () => {
      manager.register(new TestMigration(1, 'First'));
      manager.register(new TestMigration(2, 'Second'));

      const pending = manager.getPendingMigrations(10);
      expect(pending.length).assertEqual(0);
    });

    // getRollbackMigrations - 回滚迁移
    it('getRollbackMigrations should return migrations to rollback in reverse order', 0, () => {
      manager.register(new TestMigration(1, 'First'));
      manager.register(new TestMigration(2, 'Second'));
      manager.register(new TestMigration(3, 'Third'));

      const rollback = manager.getRollbackMigrations(3, 1);
      expect(rollback.length).assertEqual(2);
      expect(rollback[0].version).assertEqual(3);
      expect(rollback[1].version).assertEqual(2);
    });

    it('getRollbackMigrations should return empty when target equals current', 0, () => {
      manager.register(new TestMigration(1, 'First'));
      manager.register(new TestMigration(2, 'Second'));

      const rollback = manager.getRollbackMigrations(2, 2);
      expect(rollback.length).assertEqual(0);
    });

    it('getRollbackMigrations should return empty when target exceeds current', 0, () => {
      manager.register(new TestMigration(1, 'First'));
      manager.register(new TestMigration(2, 'Second'));

      const rollback = manager.getRollbackMigrations(2, 5);
      expect(rollback.length).assertEqual(0);
    });

    // getLatestVersion
    it('getLatestVersion should return highest version', 0, () => {
      manager.register(new TestMigration(1, 'First'));
      manager.register(new TestMigration(5, 'Fifth'));
      manager.register(new TestMigration(3, 'Third'));

      expect(manager.getLatestVersion()).assertEqual(5);
    });

    it('getLatestVersion should return 0 when no migrations', 0, () => {
      expect(manager.getLatestVersion()).assertEqual(0);
    });

    // getMigration
    it('getMigration should return migration by version', 0, () => {
      const migration = new TestMigration(2, 'Target');
      manager.register(new TestMigration(1, 'First'));
      manager.register(migration);
      manager.register(new TestMigration(3, 'Third'));

      const found = manager.getMigration(2);
      expect(found !== null).assertEqual(true);
      if (found) {
        expect(found.description).assertEqual('Target');
      }
    });

    it('getMigration should return null for non-existent version', 0, () => {
      manager.register(new TestMigration(1, 'First'));
      const found = manager.getMigration(99);
      expect(found === null).assertEqual(true);
    });

    // hasPendingMigrations
    it('hasPendingMigrations should return true when pending exist', 0, () => {
      manager.register(new TestMigration(1, 'First'));
      manager.register(new TestMigration(2, 'Second'));

      expect(manager.hasPendingMigrations(0)).assertEqual(true);
      expect(manager.hasPendingMigrations(1)).assertEqual(true);
    });

    it('hasPendingMigrations should return false when no pending', 0, () => {
      manager.register(new TestMigration(1, 'First'));
      manager.register(new TestMigration(2, 'Second'));

      expect(manager.hasPendingMigrations(2)).assertEqual(false);
      expect(manager.hasPendingMigrations(10)).assertEqual(false);
    });

    // setCurrentVersion / getCurrentVersion
    it('setCurrentVersion should update current version', 0, () => {
      manager.setCurrentVersion(5);
      expect(manager.getCurrentVersion()).assertEqual(5);
    });

    it('getCurrentVersion should return 0 initially', 0, () => {
      expect(manager.getCurrentVersion()).assertEqual(0);
    });

    // clear
    it('clear should remove all migrations', 0, () => {
      manager.register(new TestMigration(1, 'First'));
      manager.register(new TestMigration(2, 'Second'));
      manager.setCurrentVersion(2);

      manager.clear();

      expect(manager.getMigrationCount()).assertEqual(0);
      expect(manager.getCurrentVersion()).assertEqual(0);
    });

    // getSummary
    it('getSummary should return formatted summary', 0, () => {
      manager.register(new TestMigration(1, 'Create users'));
      manager.register(new TestMigration(2, 'Add posts'));
      manager.setCurrentVersion(1);

      const summary = manager.getSummary();
      expect(summary.indexOf('2 个迁移脚本') >= 0).assertEqual(true);
      expect(summary.indexOf('最新版本: 2') >= 0).assertEqual(true);
      expect(summary.indexOf('当前版本: 1') >= 0).assertEqual(true);
    });

    // MigrationResult 测试
    it('MigrationResult should store migration result data', 0, () => {
      const result = new MigrationResult(1, true, 100);
      expect(result.version).assertEqual(1);
      expect(result.success).assertEqual(true);
      expect(result.executionTime).assertEqual(100);
      expect(result.errorMessage).assertEqual('');
    });

    it('MigrationResult should store error message on failure', 0, () => {
      const result = new MigrationResult(2, false, 50, 'Test error');
      expect(result.version).assertEqual(2);
      expect(result.success).assertEqual(false);
      expect(result.errorMessage).assertEqual('Test error');
    });

    // MigrationDirection 枚举测试
    it('MigrationDirection should have UP value', 0, () => {
      expect(MigrationDirection.UP).assertEqual('UP');
    });

    it('MigrationDirection should have DOWN value', 0, () => {
      expect(MigrationDirection.DOWN).assertEqual('DOWN');
    });

    // MigrationExecutionResult 测试
    it('MigrationExecutionResult.createSuccess should create success result', 0, () => {
      const results: Array<MigrationResult> = [];
      results.push(new MigrationResult(1, true, 100));
      results.push(new MigrationResult(2, true, 150));

      const execResult = MigrationExecutionResult.createSuccess(0, 2, results);
      expect(execResult.success).assertEqual(true);
      expect(execResult.fromVersion).assertEqual(0);
      expect(execResult.toVersion).assertEqual(2);
      expect(execResult.actualVersion).assertEqual(2);
      expect(execResult.executedCount).assertEqual(2);
      expect(execResult.errorMessage).assertEqual('');
    });

    it('MigrationExecutionResult.createFailure should create failure result', 0, () => {
      const results: Array<MigrationResult> = [];
      results.push(new MigrationResult(1, true, 100));

      const execResult = MigrationExecutionResult.createFailure(0, 3, 1, results, 'Migration failed');
      expect(execResult.success).assertEqual(false);
      expect(execResult.fromVersion).assertEqual(0);
      expect(execResult.toVersion).assertEqual(3);
      expect(execResult.actualVersion).assertEqual(1);
      expect(execResult.executedCount).assertEqual(1);
      expect(execResult.errorMessage).assertEqual('Migration failed');
    });

    // AutoMigrationMode 枚举测试
    it('AutoMigrationMode should have SAFE value', 0, () => {
      expect(AutoMigrationMode.SAFE).assertEqual('SAFE');
    });

    it('AutoMigrationMode should have FULL value', 0, () => {
      expect(AutoMigrationMode.FULL).assertEqual('FULL');
    });

    // SchemaMigrationExecutionResult 测试
    it('SchemaMigrationExecutionResult.createSuccess should create success result', 0, () => {
      const diff = new SchemaDiffResult();
      const executedSql: Array<string> = [];
      executedSql.push('CREATE TABLE users');
      executedSql.push('ALTER TABLE users ADD COLUMN name');

      const result = SchemaMigrationExecutionResult.createSuccess(diff, executedSql, []);
      expect(result.success).assertEqual(true);
      expect(result.executedCount).assertEqual(2);
      expect(result.skippedCount).assertEqual(0);
      expect(result.errorMessage).assertEqual('');
    });

    it('SchemaMigrationExecutionResult.createFailure should create failure result', 0, () => {
      const diff = new SchemaDiffResult();
      const executedSql: Array<string> = [];
      executedSql.push('CREATE TABLE users');

      const result = SchemaMigrationExecutionResult.createFailure(diff, executedSql, [], 'Execution failed');
      expect(result.success).assertEqual(false);
      expect(result.executedCount).assertEqual(1);
      expect(result.errorMessage).assertEqual('Execution failed');
    });

    // MigrationManager 构造函数选项测试
    it('MigrationManager should accept enableLog option', 0, () => {
      const mgr = new MigrationManager({ enableLog: true });
      expect(mgr !== null).assertEqual(true);
    });

    it('MigrationManager should accept autoMigrationMode option', 0, () => {
      const mgr = new MigrationManager({ autoMigrationMode: AutoMigrationMode.FULL });
      expect(mgr !== null).assertEqual(true);
    });

    it('MigrationManager should work with default options', 0, () => {
      const mgr = new MigrationManager();
      expect(mgr !== null).assertEqual(true);
      expect(mgr.getMigrationCount()).assertEqual(0);
    });

    // 边界测试
    it('register should handle large version numbers', 0, () => {
      manager.register(new TestMigration(999999, 'Large version'));
      expect(manager.getLatestVersion()).assertEqual(999999);
    });

    it('getMigrationsByOrder should maintain stability', 0, () => {
      for (let i = 10; i >= 1; i--) {
        manager.register(new TestMigration(i, `Migration ${i}`));
      }

      const sorted = manager.getMigrationsByOrder();
      for (let i = 0; i < sorted.length - 1; i++) {
        expect(sorted[i].version < sorted[i + 1].version).assertEqual(true);
      }
    });

    // 空迁移列表处理
    it('getSummary should handle empty migrations', 0, () => {
      const summary = manager.getSummary();
      expect(summary.indexOf('0 个迁移脚本') >= 0).assertEqual(true);
      expect(summary.indexOf('最新版本: 0') >= 0).assertEqual(true);
    });

    // 连续版本号测试
    it('getPendingMigrations should handle consecutive versions', 0, () => {
      for (let i = 1; i <= 5; i++) {
        manager.register(new TestMigration(i, `Migration ${i}`));
      }

      const pending = manager.getPendingMigrations(2);
      expect(pending.length).assertEqual(3);
      expect(pending[0].version).assertEqual(3);
      expect(pending[1].version).assertEqual(4);
      expect(pending[2].version).assertEqual(5);
    });

    // 非连续版本号测试
    it('getPendingMigrations should handle non-consecutive versions', 0, () => {
      manager.register(new TestMigration(1, 'V1'));
      manager.register(new TestMigration(5, 'V5'));
      manager.register(new TestMigration(10, 'V10'));

      const pending = manager.getPendingMigrations(1);
      expect(pending.length).assertEqual(2);
      expect(pending[0].version).assertEqual(5);
      expect(pending[1].version).assertEqual(10);
    });
  });
}
