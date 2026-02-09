import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { MetadataStorage } from '../../main/ets/core/MetadataStorage';
import { ColumnMetadata } from '../../main/ets/core/ColumnMetadata';
import { RelationMetadata } from '../../main/ets/core/RelationMetadata';
import { RelationType } from '../../main/ets/types/RelationType';
import { QueryBuilder, BatchUpdateValues } from '../../main/ets/query/QueryBuilder';
import { ConditionOperator } from '../../main/ets/types/ConditionOperator';
import { LogicalOperator } from '../../main/ets/query/WhereCondition';
import { EntityNotRegisteredError } from '../../main/ets/errors/MetadataError';
import { InvalidConditionError, SubQueryError } from '../../main/ets/errors/QueryError';
import { RelationNotFoundError } from '../../main/ets/errors/RelationError';
import { ExecutionError } from '../../main/ets/errors/DatabaseError';

const setupTestEntity = (): void => {
  const storage = MetadataStorage.getInstance();
  storage.registerEntity('User', 'users');
  const idColumn = new ColumnMetadata('id', 'id');
  idColumn.isPrimaryKey = true;
  storage.registerColumn('User', idColumn);
  storage.registerColumn('User', new ColumnMetadata('name', 'user_name'));
  storage.registerColumn('User', new ColumnMetadata('email', 'user_email'));
  storage.registerColumn('User', new ColumnMetadata('age', 'user_age'));
};

const setupSoftDeleteEntity = (): void => {
  const storage = MetadataStorage.getInstance();
  storage.registerEntity('Article', 'articles');
  const idColumn = new ColumnMetadata('id', 'id');
  idColumn.isPrimaryKey = true;
  storage.registerColumn('Article', idColumn);
  storage.registerColumn('Article', new ColumnMetadata('title', 'title'));
  const metadata = storage.getEntityMetadata('Article');
  if (metadata) {
    metadata.setSoftDelete(true, 'deleted_at');
    storage.registerColumn('Article', new ColumnMetadata('deletedAt', 'deleted_at'));
  }
};

const setupRelations = (): void => {
  const storage = MetadataStorage.getInstance();
  storage.registerEntity('Post', 'posts');
  const idColumn = new ColumnMetadata('id', 'id');
  idColumn.isPrimaryKey = true;
  storage.registerColumn('Post', idColumn);
  storage.registerColumn('Post', new ColumnMetadata('userId', 'user_id'));
  storage.registerColumn('Post', new ColumnMetadata('title', 'post_title'));
  const relation = new RelationMetadata(RelationType.ONE_TO_MANY, 'User', 'Post', 'posts', 'user_id');
  storage.registerRelation('User', relation);
};

const setupNestedRelations = (): void => {
  const storage = MetadataStorage.getInstance();
  if (storage.getEntityMetadata('Post') === null) {
    storage.registerEntity('Post', 'posts');
    const postId = new ColumnMetadata('id', 'id');
    postId.isPrimaryKey = true;
    storage.registerColumn('Post', postId);
    storage.registerColumn('Post', new ColumnMetadata('userId', 'user_id'));
  }
  if (storage.getEntityMetadata('Comment') === null) {
    storage.registerEntity('Comment', 'comments');
    const commentId = new ColumnMetadata('id', 'id');
    commentId.isPrimaryKey = true;
    storage.registerColumn('Comment', commentId);
    storage.registerColumn('Comment', new ColumnMetadata('postId', 'post_id'));
    storage.registerColumn('Comment', new ColumnMetadata('status', 'status'));
  }
  storage.registerRelation('User', new RelationMetadata(RelationType.ONE_TO_MANY, 'User', 'Post', 'posts', 'user_id'));
  storage.registerRelation('Post', new RelationMetadata(RelationType.ONE_TO_MANY, 'Post', 'Comment', 'comments', 'post_id'));
};

const setupMorphRelations = (): void => {
  const storage = MetadataStorage.getInstance();
  if (storage.getEntityMetadata('Comment') === null) {
    storage.registerEntity('Comment', 'comments');
    const commentId = new ColumnMetadata('id', 'id');
    commentId.isPrimaryKey = true;
    storage.registerColumn('Comment', commentId);
    storage.registerColumn('Comment', new ColumnMetadata('commentableId', 'commentable_id'));
    storage.registerColumn('Comment', new ColumnMetadata('commentableType', 'commentable_type'));
  }
  storage.registerEntity('Article', 'articles');
  const articleId = new ColumnMetadata('id', 'id');
  articleId.isPrimaryKey = true;
  storage.registerColumn('Article', articleId);
  storage.registerMorphTo('Comment', 'commentable', 'commentableId', 'commentableType', { article: 'Article', user: 'User' });
};

export default function queryBuilderTest() {
  describe('queryBuilderTest', () => {
    beforeAll(() => {
    });
    beforeEach(() => {
      MetadataStorage.resetInstance();
    });
    afterEach(() => {
    });
    afterAll(() => {
    });

    it('should throw EntityNotRegisteredError for unregistered entity', 0, () => {
      let caught = false;
      try {
        new QueryBuilder('UnknownEntity');
      } catch (error) {
        caught = error instanceof EntityNotRegisteredError;
      }
      expect(caught).assertEqual(true);
    });

    it('should create builder for registered entity', 0, () => {
      setupTestEntity();
      const builder = new QueryBuilder('User');
      expect(builder.getEntityName()).assertEqual('User');
      expect(builder.getTableName()).assertEqual('users');
      expect(builder.getEntityMetadata() !== null).assertEqual(true);
    });

    it('where should add condition with resolved column name', 0, () => {
      setupTestEntity();
      const builder = new QueryBuilder('User');
      builder.where('name', ConditionOperator.EQUAL, 'Alice');
      const conditions = builder.getConditions();
      expect(conditions.length).assertEqual(1);
      expect(conditions[0].column).assertEqual('user_name');
      expect(conditions[0].operator).assertEqual(ConditionOperator.EQUAL);
      expect(conditions[0].value).assertEqual('Alice');
      expect(conditions[0].logicalOperator).assertEqual(LogicalOperator.AND);
    });

    it('where should throw InvalidConditionError for invalid column', 0, () => {
      setupTestEntity();
      const builder = new QueryBuilder('User');
      let caught = false;
      try {
        builder.where('invalidColumn', ConditionOperator.EQUAL, 'test');
      } catch (error) {
        caught = error instanceof InvalidConditionError;
      }
      expect(caught).assertEqual(true);
    });

    it('andWhere should add AND condition', 0, () => {
      setupTestEntity();
      const builder = new QueryBuilder('User');
      builder.where('name', ConditionOperator.EQUAL, 'Alice')
        .andWhere('age', ConditionOperator.GREATER, 18);
      const conditions = builder.getConditions();
      expect(conditions.length).assertEqual(2);
      expect(conditions[1].logicalOperator).assertEqual(LogicalOperator.AND);
    });

    it('orWhere should add OR condition', 0, () => {
      setupTestEntity();
      const builder = new QueryBuilder('User');
      builder.where('name', ConditionOperator.EQUAL, 'Alice')
        .orWhere('name', ConditionOperator.EQUAL, 'Bob');
      const conditions = builder.getConditions();
      expect(conditions.length).assertEqual(2);
      expect(conditions[1].logicalOperator).assertEqual(LogicalOperator.OR);
    });

    it('whereIn should add IN condition', 0, () => {
      setupTestEntity();
      const builder = new QueryBuilder('User');
      builder.whereIn('id', [1, 2, 3]);
      const conditions = builder.getConditions();
      expect(conditions[0].operator).assertEqual(ConditionOperator.IN);
      expect(Array.isArray(conditions[0].value)).assertEqual(true);
    });

    it('whereNull should add IS_NULL condition', 0, () => {
      setupTestEntity();
      const builder = new QueryBuilder('User');
      builder.whereNull('email');
      const conditions = builder.getConditions();
      expect(conditions[0].operator).assertEqual(ConditionOperator.IS_NULL);
    });

    it('whereBetween should add BETWEEN condition', 0, () => {
      setupTestEntity();
      const builder = new QueryBuilder('User');
      builder.whereBetween('age', 18, 65);
      const conditions = builder.getConditions();
      expect(conditions[0].operator).assertEqual(ConditionOperator.BETWEEN);
      expect(conditions[0].value).assertEqual(18);
      expect(conditions[0].secondValue).assertEqual(65);
    });

    it('whereLike should add LIKE condition', 0, () => {
      setupTestEntity();
      const builder = new QueryBuilder('User');
      builder.whereLike('name', '%test%');
      const conditions = builder.getConditions();
      expect(conditions[0].operator).assertEqual(ConditionOperator.LIKE);
    });

    it('orderBy should add order clause', 0, () => {
      setupTestEntity();
      const builder = new QueryBuilder('User');
      builder.orderBy('name', 'ASC');
      const orderBys = builder.getOrderByColumns();
      expect(orderBys.length).assertEqual(1);
      expect(orderBys[0].column).assertEqual('user_name');
      expect(orderBys[0].direction).assertEqual('ASC');
    });

    it('limit should set limit value', 0, () => {
      setupTestEntity();
      const builder = new QueryBuilder('User');
      builder.limit(10);
      expect(builder.getLimitValue()).assertEqual(10);
    });

    it('offset should set offset value', 0, () => {
      setupTestEntity();
      const builder = new QueryBuilder('User');
      builder.offset(20);
      expect(builder.getOffsetValue()).assertEqual(20);
    });

    it('select should set selected columns', 0, () => {
      setupTestEntity();
      const builder = new QueryBuilder('User');
      builder.select(['name', 'email']);
      const selected = builder.getSelectedColumns();
      expect(selected.length).assertEqual(2);
      expect(selected[0]).assertEqual('user_name');
    });

    it('with should add relation', 0, () => {
      setupTestEntity();
      setupRelations();
      const builder = new QueryBuilder('User');
      builder.with('posts');
      expect(builder.hasRelations()).assertEqual(true);
      expect(builder.getRelationNames()[0]).assertEqual('posts');
    });

    it('with should support nested relation path', 0, () => {
      setupTestEntity();
      setupNestedRelations();
      const builder = new QueryBuilder('User');
      builder.with('posts.comments');
      expect(builder.hasRelations()).assertEqual(true);
      expect(builder.getRelationNames()[0]).assertEqual('posts.comments');
    });

    it('with should throw RelationNotFoundError for non-existent relation', 0, () => {
      setupTestEntity();
      const builder = new QueryBuilder('User');
      let caught = false;
      try {
        builder.with('invalidRelation');
      } catch (error) {
        caught = error instanceof RelationNotFoundError;
      }
      expect(caught).assertEqual(true);
    });

    it('with should allow nested path on morphTo relation', 0, () => {
      setupTestEntity();
      setupMorphRelations();
      const builder = new QueryBuilder('Comment');
      builder.with('commentable.profile');
      expect(builder.getRelationNames()[0]).assertEqual('commentable.profile');
    });

    it('withLazy should add lazy relation', 0, () => {
      setupTestEntity();
      setupRelations();
      const builder = new QueryBuilder('User');
      builder.withLazy('posts');
      expect(builder.hasLazyRelations()).assertEqual(true);
    });

    it('withLazy should accept morphTo relation', 0, () => {
      setupTestEntity();
      setupMorphRelations();
      const builder = new QueryBuilder('Comment');
      builder.withLazy('commentable');
      expect(builder.hasLazyRelations()).assertEqual(true);
    });

    it('withWhere should register relation query options', 0, () => {
      setupTestEntity();
      setupRelations();
      const builder = new QueryBuilder('User');
      builder.withWhere('posts', (relationQb) => {
        relationQb.where('title', ConditionOperator.LIKE, '%ark%')
          .orderBy('title', 'DESC')
          .limit(5);
      });
      const options = builder.getRelationQueryOptions('posts');
      expect(options !== null).assertEqual(true);
      if (options !== null) {
        expect(options.conditions.length).assertEqual(1);
        expect(options.orderByColumns.length).assertEqual(1);
        expect(options.limitValue).assertEqual(5);
      }
      expect(builder.getRelationNames().includes('posts')).assertEqual(true);
    });

    it('withCount should register relation count option', 0, () => {
      setupTestEntity();
      setupRelations();
      const builder = new QueryBuilder('User');
      builder.withCount('posts');
      const countOptions = builder.getRelationCountOptions();
      expect(countOptions.length).assertEqual(1);
      expect(countOptions[0].relationPath).assertEqual('posts');
      expect(countOptions[0].alias).assertEqual('posts_count');
    });

    it('with should accept morphTo relation', 0, () => {
      setupTestEntity();
      setupMorphRelations();
      const builder = new QueryBuilder('Comment');
      builder.with('commentable');
      expect(builder.hasRelations()).assertEqual(true);
      expect(builder.getRelationNames()[0]).assertEqual('commentable');
    });

    it('withCount should accept morphTo relation', 0, () => {
      setupTestEntity();
      setupMorphRelations();
      const builder = new QueryBuilder('Comment');
      builder.withCount('commentable');
      const countOptions = builder.getRelationCountOptions();
      expect(countOptions.length).assertEqual(1);
      expect(countOptions[0].relationPath).assertEqual('commentable');
      expect(countOptions[0].alias).assertEqual('commentable_count');
    });

    it('withWhere should accept morphTo relation', 0, () => {
      setupTestEntity();
      setupMorphRelations();
      const builder = new QueryBuilder('Comment');
      builder.withWhere('commentable', (relationQb) => {
        relationQb.limit(1);
      });
      expect(builder.getRelationNames().includes('commentable')).assertEqual(true);
    });

    it('withWhere should accept nested path on morphTo relation', 0, () => {
      setupTestEntity();
      setupMorphRelations();
      const builder = new QueryBuilder('Comment');
      builder.withWhere('commentable.profile', (relationQb) => {
        relationQb.limit(1);
      });
      expect(builder.getRelationNames().includes('commentable.profile')).assertEqual(true);
    });

    it('withDeleted should set includeDeleted flag', 0, () => {
      setupSoftDeleteEntity();
      const builder = new QueryBuilder('Article');
      builder.withDeleted();
      expect(builder.isIncludeDeleted()).assertEqual(true);
    });

    it('onlyDeleted should set onlyDeleted flag', 0, () => {
      setupSoftDeleteEntity();
      const builder = new QueryBuilder('Article');
      builder.onlyDeleted();
      expect(builder.isOnlyDeleted()).assertEqual(true);
    });

    it('getSoftDeleteCondition should return IS_NULL for default', 0, () => {
      setupSoftDeleteEntity();
      const builder = new QueryBuilder('Article');
      const condition = builder.getSoftDeleteCondition();
      expect(condition !== null).assertEqual(true);
      if (condition) {
        expect(condition.operator).assertEqual(ConditionOperator.IS_NULL);
      }
    });

    it('getAllConditions should append soft delete for each OR segment', 0, () => {
      setupSoftDeleteEntity();
      const builder = new QueryBuilder('Article');
      builder.where('title', ConditionOperator.EQUAL, 'A')
        .orWhere('title', ConditionOperator.EQUAL, 'B');

      const conditions = builder.getAllConditions();
      expect(conditions.length).assertEqual(4);
      expect(conditions[0].column).assertEqual('title');
      expect(conditions[1].column).assertEqual('deleted_at');
      expect(conditions[1].operator).assertEqual(ConditionOperator.IS_NULL);
      expect(conditions[2].logicalOperator).assertEqual(LogicalOperator.OR);
      expect(conditions[2].column).assertEqual('title');
      expect(conditions[3].column).assertEqual('deleted_at');
      expect(conditions[3].operator).assertEqual(ConditionOperator.IS_NULL);
    });

    it('paginate should set page and size', 0, () => {
      setupTestEntity();
      const builder = new QueryBuilder('User');
      builder.paginate(2, 10);
      expect(builder.getPageNumber()).assertEqual(2);
      expect(builder.getPageSizeValue()).assertEqual(10);
      expect(builder.hasPagination()).assertEqual(true);
    });

    it('reset should clear all builder state', 0, () => {
      setupTestEntity();
      const builder = new QueryBuilder('User');
      builder.where('name', ConditionOperator.EQUAL, 'test').limit(10);
      builder.reset();
      expect(builder.getConditions().length).assertEqual(0);
      expect(builder.getLimitValue()).assertEqual(0);
    });

    it('update should delegate to QueryExecutor and throw when db is unavailable', 0, async () => {
      setupTestEntity();
      const builder = new QueryBuilder('User');
      const values = BatchUpdateValues.create().set('name', 'Alice');

      let caught = false;
      try {
        await builder.update(values);
      } catch (error) {
        caught = error instanceof ExecutionError;
      }
      expect(caught).assertEqual(true);
    });

    it('delete should delegate to QueryExecutor and throw when db is unavailable', 0, async () => {
      setupTestEntity();
      const builder = new QueryBuilder('User');

      let caught = false;
      try {
        await builder.delete();
      } catch (error) {
        caught = error instanceof ExecutionError;
      }
      expect(caught).assertEqual(true);
    });

    it('whereExists should add sub query', 0, () => {
      setupTestEntity();
      setupRelations();
      const builder = new QueryBuilder('User');
      builder.whereExists('posts', (subQuery) => {
        subQuery.where('title', ConditionOperator.LIKE, '%test%');
      });
      expect(builder.hasSubQueries()).assertEqual(true);
      expect(builder.getSubQueries().length).assertEqual(1);
    });

    it('whereExists should throw for non-existent relation', 0, () => {
      setupTestEntity();
      const builder = new QueryBuilder('User');
      let caught = false;
      try {
        builder.whereExists('invalidRelation', () => {});
      } catch (error) {
        caught = error instanceof RelationNotFoundError;
      }
      expect(caught).assertEqual(true);
    });

    it('getQueryDescription should build description', 0, () => {
      setupTestEntity();
      const builder = new QueryBuilder('User');
      builder.where('name', ConditionOperator.EQUAL, 'Alice').limit(10);
      const desc = builder.getQueryDescription();
      expect(desc.includes('FROM: users')).assertEqual(true);
      expect(desc.includes('WHERE:')).assertEqual(true);
      expect(desc.includes('LIMIT: 10')).assertEqual(true);
    });
  });
}
