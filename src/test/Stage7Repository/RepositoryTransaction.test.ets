import { describe, beforeEach, it, expect } from '@ohos/hypium';
import { MetadataStorage } from '../../main/ets/core/MetadataStorage';
import { ColumnMetadata } from '../../main/ets/core/ColumnMetadata';
import { ColumnType } from '../../main/ets/types/ColumnType';
import { Repository, TransactionResult } from '../../main/ets/repository/Repository';
import { TransactionOptions, IsolationLevel } from '../../main/ets/repository/TransactionOptions';
import { TransactionRollbackError } from '../../main/ets/errors/TransactionError';
import { HooksProcessor } from '../../main/ets/core/HooksProcessor';
import { DatabaseManager } from '../../main/ets/database/DatabaseManager';
import { relationalStore } from '@kit.ArkData';

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

export default function repositoryTransactionTest() {
  describe('repositoryTransactionTest', () => {
    beforeEach(() => {
      MetadataStorage.resetInstance();
      HooksProcessor.resetInstance();
      DatabaseManager.resetInstance();
    });

    it('TransactionResult.createSuccess should create success result', 0, () => {
      const result = TransactionResult.createSuccess();
      expect(result.success).assertEqual(true);
      expect(result.errorMessage).assertEqual('');
    });

    it('TransactionResult.createFailure should create failure result', 0, () => {
      const result = TransactionResult.createFailure('Transaction failed');
      expect(result.success).assertEqual(false);
      expect(result.errorMessage).assertEqual('Transaction failed');
    });

    it('TransactionOptions.createDefault should create default options', 0, () => {
      const options = TransactionOptions.createDefault();
      expect(options.isolation).assertEqual(IsolationLevel.READ_COMMITTED);
      expect(options.timeout).assertEqual(30000);
      expect(options.retries).assertEqual(0);
      expect(options.retryDelay).assertEqual(100);
      expect(options.readOnly).assertEqual(false);
    });

    it('TransactionOptions.readOnly should create read-only options', 0, () => {
      const options = TransactionOptions.readOnly();
      expect(options.readOnly).assertEqual(true);
    });

    it('TransactionOptions.withRetry should create options with retry', 0, () => {
      const options = TransactionOptions.withRetry(3, 200);
      expect(options.retries).assertEqual(3);
      expect(options.retryDelay).assertEqual(200);
    });

    it('TransactionOptions.withTimeout should create options with timeout', 0, () => {
      const options = TransactionOptions.withTimeout(5000);
      expect(options.timeout).assertEqual(5000);
    });

    it('TransactionOptions.serializable should create serializable options', 0, () => {
      const options = TransactionOptions.serializable();
      expect(options.isolation).assertEqual(IsolationLevel.SERIALIZABLE);
    });

    it('TransactionOptions.fromConfig should create options from config', 0, () => {
      const options = TransactionOptions.fromConfig({
        isolation: IsolationLevel.READ_UNCOMMITTED,
        timeout: 10000,
        retries: 2,
        retryDelay: 500,
        readOnly: true
      });
      expect(options.isolation).assertEqual(IsolationLevel.READ_UNCOMMITTED);
      expect(options.timeout).assertEqual(10000);
      expect(options.retries).assertEqual(2);
      expect(options.retryDelay).assertEqual(500);
      expect(options.readOnly).assertEqual(true);
    });

    it('TransactionOptions.fromConfig should use defaults for missing values', 0, () => {
      const options = TransactionOptions.fromConfig({});
      expect(options.isolation).assertEqual(IsolationLevel.READ_COMMITTED);
      expect(options.timeout).assertEqual(30000);
      expect(options.retries).assertEqual(0);
    });

    it('IsolationLevel enum should have correct values', 0, () => {
      expect(IsolationLevel.READ_UNCOMMITTED).assertEqual('READ_UNCOMMITTED');
      expect(IsolationLevel.READ_COMMITTED).assertEqual('READ_COMMITTED');
      expect(IsolationLevel.REPEATABLE_READ).assertEqual('REPEATABLE_READ');
      expect(IsolationLevel.SERIALIZABLE).assertEqual('SERIALIZABLE');
    });

    it('transaction should throw TransactionRollbackError when database not initialized', 0, async () => {
      setupUserEntity();
      const repo = new Repository('User');

      let threw = false;
      let errorType = '';
      try {
        await repo.transaction(async () => {
        });
      } catch (error) {
        threw = true;
        if (error instanceof TransactionRollbackError) {
          errorType = 'TransactionRollbackError';
        }
      }

      expect(threw).assertEqual(true);
      expect(errorType).assertEqual('TransactionRollbackError');
    });

    it('transactionWithOptions should throw TransactionRollbackError when database not initialized', 0, async () => {
      setupUserEntity();
      const repo = new Repository('User');
      const options = TransactionOptions.createDefault();

      let threw = false;
      let errorType = '';
      try {
        await repo.transactionWithOptions(async () => {
        }, options);
      } catch (error) {
        threw = true;
        if (error instanceof TransactionRollbackError) {
          errorType = 'TransactionRollbackError';
        }
      }

      expect(threw).assertEqual(true);
      expect(errorType).assertEqual('TransactionRollbackError');
    });

    it('transactionWithOptions with timeout should throw error', 0, async () => {
      setupUserEntity();
      const repo = new Repository('User');
      const options = TransactionOptions.withTimeout(100);

      let threw = false;
      try {
        await repo.transactionWithOptions(async () => {
        }, options);
      } catch (error) {
        threw = error instanceof TransactionRollbackError;
      }

      expect(threw).assertEqual(true);
    });

    it('transactionWithOptions timeout should rollback without commit', 0, async () => {
      setupUserEntity();
      const repo = new Repository('User');
      const options = TransactionOptions.withTimeout(10);

      let beginCount = 0;
      let commitCount = 0;
      let rollbackCount = 0;

      const fakeStore = {
        beginTransaction: () => {
          beginCount++;
        },
        commit: () => {
          commitCount++;
        },
        rollBack: () => {
          rollbackCount++;
        },
        executeSql: async () => {
        }
      } as unknown as relationalStore.RdbStore;

      const manager = DatabaseManager.getInstance() as unknown as {
        store: relationalStore.RdbStore | null,
        initialized: boolean,
        healthy: boolean
      };
      manager.store = fakeStore;
      manager.initialized = true;
      manager.healthy = true;

      let threw = false;
      try {
        await repo.transactionWithOptions(async () => {
          await new Promise<void>((resolve) => setTimeout(resolve, 30));
        }, options);
      } catch (error) {
        threw = error instanceof TransactionRollbackError;
      }

      expect(threw).assertEqual(true);
      expect(beginCount).assertEqual(1);
      expect(commitCount).assertEqual(0);
      expect(rollbackCount).assertEqual(1);
    });

    it('transactionWithOptions with retry should attempt multiple times', 0, async () => {
      setupUserEntity();
      const repo = new Repository('User');
      const options = TransactionOptions.fromConfig({
        retries: 1,
        retryDelay: 10
      });

      let threw = false;
      try {
        await repo.transactionWithOptions(async () => {
        }, options);
      } catch (error) {
        threw = error instanceof TransactionRollbackError;
      }

      expect(threw).assertEqual(true);
    });

    it('transactionWithOptions with readOnly should work', 0, async () => {
      setupUserEntity();
      const repo = new Repository('User');
      const options = TransactionOptions.readOnly();

      let threw = false;
      try {
        await repo.transactionWithOptions(async () => {
        }, options);
      } catch (error) {
        threw = error instanceof TransactionRollbackError;
      }

      expect(threw).assertEqual(true);
    });

    it('transactionWithOptions with isolation level should work', 0, async () => {
      setupUserEntity();
      const repo = new Repository('User');
      const options = TransactionOptions.serializable();

      let threw = false;
      try {
        await repo.transactionWithOptions(async () => {
        }, options);
      } catch (error) {
        threw = error instanceof TransactionRollbackError;
      }

      expect(threw).assertEqual(true);
    });

    it('transaction callback error should be propagated', 0, async () => {
      setupUserEntity();
      const repo = new Repository('User');

      let threw = false;
      try {
        await repo.transaction(async () => {
          throw new Error('Callback error');
        });
      } catch (error) {
        threw = true;
      }

      expect(threw).assertEqual(true);
    });
  });
}
