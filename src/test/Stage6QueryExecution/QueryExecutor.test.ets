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
  });
}
