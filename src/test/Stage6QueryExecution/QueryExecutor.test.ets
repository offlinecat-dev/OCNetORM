import { describe, beforeEach, it, expect } from '@ohos/hypium';
import { MetadataStorage } from '../../main/ets/core/MetadataStorage';
import { ColumnMetadata } from '../../main/ets/core/ColumnMetadata';
import { RelationMetadata } from '../../main/ets/core/RelationMetadata';
import { RelationType } from '../../main/ets/types/RelationType';
import { ColumnType } from '../../main/ets/types/ColumnType';
import { ConditionOperator } from '../../main/ets/types/ConditionOperator';
import { QueryBuilder } from '../../main/ets/query/QueryBuilder';
import { QueryExecutor } from '../../main/ets/query/QueryExecutor';
import { ExecutionError } from '../../main/ets/errors/DatabaseError';
import { DatabaseManager } from '../../main/ets/database/DatabaseManager';
import { relationalStore } from '@kit.ArkData';

class FakeResultSet {
  rowCount: number;
  columnNames: Array<string>;
  private rows: Array<Record<string, any>>;
  private index: number = -1;

  constructor(columns: Array<string>, rows: Array<Record<string, any>>) {
    this.columnNames = columns;
    this.rows = rows;
    this.rowCount = rows.length;
  }

  goToNextRow(): boolean {
    this.index++;
    return this.index < this.rows.length;
  }

  goToFirstRow(): boolean {
    if (this.rows.length === 0) {
      return false;
    }
    this.index = 0;
    return true;
  }

  getColumnIndex(columnName: string): number {
    return this.columnNames.indexOf(columnName);
  }

  isColumnNull(columnIndex: number): boolean {
    const row = this.rows[this.index];
    if (!row) {
      return true;
    }
    const columnName = this.columnNames[columnIndex];
    return row[columnName] === null || row[columnName] === undefined;
  }

  getLong(columnIndex: number): number {
    const columnName = this.columnNames[columnIndex];
    return Number(this.rows[this.index][columnName]);
  }

  getDouble(columnIndex: number): number {
    const columnName = this.columnNames[columnIndex];
    return Number(this.rows[this.index][columnName]);
  }

  getString(columnIndex: number): string {
    const columnName = this.columnNames[columnIndex];
    return String(this.rows[this.index][columnName]);
  }

  getBlob(columnIndex: number): Uint8Array {
    const columnName = this.columnNames[columnIndex];
    return this.rows[this.index][columnName] as Uint8Array;
  }

  close(): void {
  }
}

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

const setupRelations = (): void => {
  const storage = MetadataStorage.getInstance();

  storage.registerEntity('Post', 'posts');
  const postIdColumn = new ColumnMetadata('id', 'id')
    .setType(ColumnType.INTEGER)
    .setPrimaryKey(true);
  storage.registerColumn('Post', postIdColumn);

  const userIdColumn = new ColumnMetadata('userId', 'user_id')
    .setType(ColumnType.INTEGER);
  storage.registerColumn('Post', userIdColumn);

  const postTitleColumn = new ColumnMetadata('title', 'post_title')
    .setType(ColumnType.TEXT);
  storage.registerColumn('Post', postTitleColumn);

  const relation = new RelationMetadata(
    RelationType.ONE_TO_MANY,
    'User',
    'Post',
    'posts',
    'user_id'
  );
  storage.registerRelation('User', relation);
};

export default function queryExecutorTest() {
  describe('queryExecutorTest', () => {
    beforeEach(() => {
      MetadataStorage.resetInstance();
      DatabaseManager.resetInstance();
    });

    it('should create QueryExecutor with valid QueryBuilder', 0, () => {
      setupUserEntity();
      const builder = new QueryBuilder('User');
      const executor = new QueryExecutor(builder);
      expect(executor !== null).assertEqual(true);
    });

    it('get should throw ExecutionError when database not initialized', 0, async () => {
      setupUserEntity();
      const builder = new QueryBuilder('User');
      const executor = new QueryExecutor(builder);

      let threw = false;
      let errorType = '';
      try {
        await executor.get();
      } catch (error) {
        threw = true;
        if (error instanceof ExecutionError) {
          errorType = 'ExecutionError';
        }
      }

      expect(threw).assertEqual(true);
      expect(errorType).assertEqual('ExecutionError');
    });

    it('getOne should throw ExecutionError when database not initialized', 0, async () => {
      setupUserEntity();
      const builder = new QueryBuilder('User');
      const executor = new QueryExecutor(builder);

      let threw = false;
      let errorType = '';
      try {
        await executor.getOne();
      } catch (error) {
        threw = true;
        if (error instanceof ExecutionError) {
          errorType = 'ExecutionError';
        }
      }

      expect(threw).assertEqual(true);
      expect(errorType).assertEqual('ExecutionError');
    });

    it('count should throw ExecutionError when database not initialized', 0, async () => {
      setupUserEntity();
      const builder = new QueryBuilder('User');
      const executor = new QueryExecutor(builder);

      let threw = false;
      let errorType = '';
      try {
        await executor.count();
      } catch (error) {
        threw = true;
        if (error instanceof ExecutionError) {
          errorType = 'ExecutionError';
        }
      }

      expect(threw).assertEqual(true);
      expect(errorType).assertEqual('ExecutionError');
    });

    it('getPaginated should throw ExecutionError when database not initialized', 0, async () => {
      setupUserEntity();
      const builder = new QueryBuilder('User');
      builder.paginate(1, 10);
      const executor = new QueryExecutor(builder);

      let threw = false;
      let errorType = '';
      try {
        await executor.getPaginated();
      } catch (error) {
        threw = true;
        if (error instanceof ExecutionError) {
          errorType = 'ExecutionError';
        }
      }

      expect(threw).assertEqual(true);
      expect(errorType).assertEqual('ExecutionError');
    });

    it('getAsync should throw ExecutionError when database not initialized', 0, async () => {
      setupUserEntity();
      const builder = new QueryBuilder('User');
      const executor = new QueryExecutor(builder);

      let threw = false;
      let errorType = '';
      try {
        await executor.getAsync();
      } catch (error) {
        threw = true;
        if (error instanceof ExecutionError) {
          errorType = 'ExecutionError';
        }
      }

      expect(threw).assertEqual(true);
      expect(errorType).assertEqual('ExecutionError');
    });

    it('should work with soft delete entity', 0, () => {
      setupSoftDeleteEntity();
      const builder = new QueryBuilder('Article');
      const executor = new QueryExecutor(builder);
      expect(executor !== null).assertEqual(true);
    });

    it('should work with relations configured', 0, () => {
      setupUserEntity();
      setupRelations();
      const builder = new QueryBuilder('User');
      builder.with('posts');
      const executor = new QueryExecutor(builder);
      expect(executor !== null).assertEqual(true);
    });

    it('should work with lazy relations configured', 0, () => {
      setupUserEntity();
      setupRelations();
      const builder = new QueryBuilder('User');
      builder.withLazy('posts');
      const executor = new QueryExecutor(builder);
      expect(executor !== null).assertEqual(true);
    });

    it('should work with selected columns', 0, () => {
      setupUserEntity();
      const builder = new QueryBuilder('User');
      builder.select(['name', 'email']);
      const executor = new QueryExecutor(builder);
      expect(executor !== null).assertEqual(true);
    });

    it('should work with pagination params', 0, () => {
      setupUserEntity();
      const builder = new QueryBuilder('User');
      builder.paginate(2, 15);
      const executor = new QueryExecutor(builder);
      expect(executor !== null).assertEqual(true);
    });

    it('should work with subquery configured', 0, () => {
      setupUserEntity();
      setupRelations();
      const builder = new QueryBuilder('User');
      builder.whereExists('posts', (sub) => {
        sub.where('title', ConditionOperator.LIKE, '%test%');
      });
      const executor = new QueryExecutor(builder);
      expect(executor !== null).assertEqual(true);
    });

    it('get with subquery should return empty when database not initialized', 0, async () => {
      setupUserEntity();
      setupRelations();
      const builder = new QueryBuilder('User');
      builder.whereExists('posts', (sub) => {
        sub.where('title', ConditionOperator.LIKE, '%test%');
      });
      const executor = new QueryExecutor(builder);

      let threw = false;
      try {
        await executor.get();
      } catch (error) {
        threw = error instanceof ExecutionError;
      }

      expect(threw).assertEqual(true);
    });

    it('count with subquery should throw when database not initialized', 0, async () => {
      setupUserEntity();
      setupRelations();
      const builder = new QueryBuilder('User');
      builder.whereExists('posts', (sub) => {
        sub.where('title', ConditionOperator.LIKE, '%test%');
      });
      const executor = new QueryExecutor(builder);

      let threw = false;
      try {
        await executor.count();
      } catch (error) {
        threw = error instanceof ExecutionError;
      }

      expect(threw).assertEqual(true);
    });

    it('getPaginated with subquery should throw when database not initialized', 0, async () => {
      setupUserEntity();
      setupRelations();
      const builder = new QueryBuilder('User');
      builder.whereExists('posts', (sub) => {
        sub.where('title', ConditionOperator.LIKE, '%test%');
      });
      builder.paginate(1, 10);
      const executor = new QueryExecutor(builder);

      let threw = false;
      try {
        await executor.getPaginated();
      } catch (error) {
        threw = error instanceof ExecutionError;
      }

      expect(threw).assertEqual(true);
    });

    it('getAsync with subquery should return empty without querying store', 0, async () => {
      setupUserEntity();
      setupRelations();
      const builder = new QueryBuilder('User');
      builder.whereExists('posts', (sub) => {
        sub.where('title', ConditionOperator.LIKE, '%test%');
      });
      const executor = new QueryExecutor(builder);
      (executor as unknown as { executeSubQueries: () => Promise<number[]> }).executeSubQueries = async () => {
        return [];
      };

      let queryCalled = false;
      const fakeStore = {
        query: async () => {
          queryCalled = true;
          return new FakeResultSet(['id'], []);
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

      const results = await executor.getAsync();
      expect(results.length).assertEqual(0);
      expect(queryCalled).assertEqual(false);
    });

    it('get should not mutate QueryBuilder conditions when applying subquery filter', 0, async () => {
      setupUserEntity();
      setupRelations();
      const builder = new QueryBuilder('User');
      builder.where('name', ConditionOperator.EQUAL, 'Alice');
      const originalCount = builder.getConditions().length;

      const executor = new QueryExecutor(builder);
      (executor as unknown as { executeSubQueries: () => Promise<number[]> }).executeSubQueries = async () => {
        return [1];
      };

      const fakeStore = {
        query: async () => new FakeResultSet(['id', 'user_name', 'user_email'], [])
      } as unknown as relationalStore.RdbStore;

      const manager = DatabaseManager.getInstance() as unknown as {
        store: relationalStore.RdbStore | null,
        initialized: boolean,
        healthy: boolean
      };
      manager.store = fakeStore;
      manager.initialized = true;
      manager.healthy = true;

      await executor.get();
      expect(builder.getConditions().length).assertEqual(originalCount);
    });

    it('get should apply in-memory filter when subquery ids exceed limit', 0, async () => {
      setupUserEntity();
      setupRelations();
      const builder = new QueryBuilder('User');
      builder.whereExists('posts', (sub) => {
        sub.where('title', ConditionOperator.LIKE, '%test%');
      });

      const executor = new QueryExecutor(builder);
      (executor as unknown as { executeSubQueries: () => Promise<number[]> }).executeSubQueries = async () => {
        return [1, 2, 3];
      };

      const executorClass = QueryExecutor as unknown as { SUBQUERY_IN_LIMIT: number };
      const originalLimit = executorClass.SUBQUERY_IN_LIMIT;
      executorClass.SUBQUERY_IN_LIMIT = 2;

      const fakeStore = {
        query: async () => new FakeResultSet(
          ['id', 'user_name', 'user_email'],
          [
            { id: 1, user_name: 'a', user_email: 'a@a.com' },
            { id: 2, user_name: 'b', user_email: 'b@b.com' },
            { id: 3, user_name: 'c', user_email: 'c@c.com' },
            { id: 4, user_name: 'd', user_email: 'd@d.com' }
          ]
        )
      } as unknown as relationalStore.RdbStore;

      const manager = DatabaseManager.getInstance() as unknown as {
        store: relationalStore.RdbStore | null,
        initialized: boolean,
        healthy: boolean
      };
      manager.store = fakeStore;
      manager.initialized = true;
      manager.healthy = true;

      try {
        const results = await executor.get();
        expect(results.length).assertEqual(3);
        expect(results[0].getPropertyValue('id')).assertEqual(1);
        expect(results[1].getPropertyValue('id')).assertEqual(2);
        expect(results[2].getPropertyValue('id')).assertEqual(3);
      } finally {
        executorClass.SUBQUERY_IN_LIMIT = originalLimit;
      }
    });

    it('count should escape identifiers in SQL', 0, async () => {
      const storage = MetadataStorage.getInstance();
      storage.registerEntity('KeywordEntity', 'order');

      const idColumn = new ColumnMetadata('id', 'id')
        .setType(ColumnType.INTEGER)
        .setPrimaryKey(true);
      storage.registerColumn('KeywordEntity', idColumn);

      const selectColumn = new ColumnMetadata('select', 'select')
        .setType(ColumnType.TEXT);
      storage.registerColumn('KeywordEntity', selectColumn);

      const builder = new QueryBuilder('KeywordEntity');
      builder.where('select', ConditionOperator.EQUAL, 'x');
      const executor = new QueryExecutor(builder);

      let capturedSql = '';
      const fakeStore = {
        querySql: async (sql: string) => {
          capturedSql = sql;
          return new FakeResultSet(['total'], [{ total: 0 }]);
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

      await executor.count();
      expect(capturedSql.includes('"order"')).assertEqual(true);
      expect(capturedSql.includes('"select"')).assertEqual(true);
    });
  });
}
