import { describe, beforeEach, it, expect } from '@ohos/hypium';
import { MetadataStorage } from '../../main/ets/core/MetadataStorage';
import { ColumnMetadata } from '../../main/ets/core/ColumnMetadata';
import { RelationMetadata } from '../../main/ets/core/RelationMetadata';
import { ManyToManyMetadata } from '../../main/ets/core/ManyToManyMetadata';
import { ColumnType } from '../../main/ets/types/ColumnType';
import { RelationType } from '../../main/ets/types/RelationType';
import { Repository } from '../../main/ets/repository/index';
import { RelationNotFoundError } from '../../main/ets/errors/RelationError';
import { ExecutionError } from '../../main/ets/errors/DatabaseError';
import { HooksProcessor } from '../../main/ets/core/HooksProcessor';

const setupPostEntity = (): void => {
  const storage = MetadataStorage.getInstance();
  storage.registerEntity('Post', 'posts');

  const idColumn = new ColumnMetadata('id', 'id')
    .setType(ColumnType.INTEGER)
    .setPrimaryKey(true)
    .setAutoIncrement(true);
  storage.registerColumn('Post', idColumn);

  const titleColumn = new ColumnMetadata('title', 'title')
    .setType(ColumnType.TEXT);
  storage.registerColumn('Post', titleColumn);
};

const setupTagEntity = (): void => {
  const storage = MetadataStorage.getInstance();
  storage.registerEntity('Tag', 'tags');

  const idColumn = new ColumnMetadata('id', 'id')
    .setType(ColumnType.INTEGER)
    .setPrimaryKey(true)
    .setAutoIncrement(true);
  storage.registerColumn('Tag', idColumn);

  const nameColumn = new ColumnMetadata('name', 'name')
    .setType(ColumnType.TEXT);
  storage.registerColumn('Tag', nameColumn);
};

const setupManyToManyRelation = (): void => {
  const storage = MetadataStorage.getInstance();

  storage.registerManyToMany(
    'Post',
    'Tag',
    'tags',
    'post_tags',
    'post_id',
    'tag_id'
  );
};

export default function manyToManyTest() {
  describe('manyToManyTest', () => {
    beforeEach(() => {
      MetadataStorage.resetInstance();
      HooksProcessor.resetInstance();
    });

    it('ManyToManyMetadata should store correct values', 0, () => {
      const metadata = new ManyToManyMetadata(
        'Post',
        'Tag',
        'tags',
        'post_tags',
        'post_id',
        'tag_id'
      );
      expect(metadata.sourceEntity).assertEqual('Post');
      expect(metadata.targetEntity).assertEqual('Tag');
      expect(metadata.joinTable).assertEqual('post_tags');
      expect(metadata.joinSourceKey).assertEqual('post_id');
      expect(metadata.joinTargetKey).assertEqual('tag_id');
    });

    it('should register many-to-many relation', 0, () => {
      setupPostEntity();
      setupTagEntity();
      setupManyToManyRelation();

      const storage = MetadataStorage.getInstance();
      const relation = storage.getManyToManyRelation('Post', 'tags');
      expect(relation !== null).assertEqual(true);
    });

    it('should get many-to-many relation metadata', 0, () => {
      setupPostEntity();
      setupTagEntity();
      setupManyToManyRelation();

      const storage = MetadataStorage.getInstance();
      const relation = storage.getManyToManyRelation('Post', 'tags');
      expect(relation?.joinTable).assertEqual('post_tags');
      expect(relation?.joinSourceKey).assertEqual('post_id');
      expect(relation?.joinTargetKey).assertEqual('tag_id');
    });

    it('attach should throw RelationNotFoundError for unregistered relation', 0, async () => {
      setupPostEntity();
      const repo = new Repository('Post');

      let threw = false;
      let errorType = '';
      try {
        await repo.attach(1, 1, 'unknownRelation');
      } catch (error) {
        threw = true;
        if (error instanceof RelationNotFoundError) {
          errorType = 'RelationNotFoundError';
        }
      }

      expect(threw).assertEqual(true);
      expect(errorType).assertEqual('RelationNotFoundError');
    });

    it('attach should accept string primary keys', 0, async () => {
      setupPostEntity();
      const repo = new Repository('Post');
      let threw = false;
      let errorType = '';
      try {
        await repo.attach('post_A', 'tag_A', 'unknownRelation');
      } catch (error) {
        threw = true;
        if (error instanceof RelationNotFoundError) {
          errorType = 'RelationNotFoundError';
        }
      }
      expect(threw).assertEqual(true);
      expect(errorType).assertEqual('RelationNotFoundError');
    });

    it('attach should return failure when database not initialized', 0, async () => {
      setupPostEntity();
      setupTagEntity();
      setupManyToManyRelation();
      const repo = new Repository('Post');

      const result = await repo.attach(1, 1, 'tags');
      expect(result.success).assertEqual(false);
      expect(result.errorMessage.length > 0).assertEqual(true);
    });

    it('detach should throw RelationNotFoundError for unregistered relation', 0, async () => {
      setupPostEntity();
      const repo = new Repository('Post');

      let threw = false;
      let errorType = '';
      try {
        await repo.detach(1, 1, 'unknownRelation');
      } catch (error) {
        threw = true;
        if (error instanceof RelationNotFoundError) {
          errorType = 'RelationNotFoundError';
        }
      }

      expect(threw).assertEqual(true);
      expect(errorType).assertEqual('RelationNotFoundError');
    });

    it('detach should accept string primary keys', 0, async () => {
      setupPostEntity();
      const repo = new Repository('Post');
      let threw = false;
      let errorType = '';
      try {
        await repo.detach('post_A', 'tag_A', 'unknownRelation');
      } catch (error) {
        threw = true;
        if (error instanceof RelationNotFoundError) {
          errorType = 'RelationNotFoundError';
        }
      }
      expect(threw).assertEqual(true);
      expect(errorType).assertEqual('RelationNotFoundError');
    });

    it('detach should return failure when database not initialized', 0, async () => {
      setupPostEntity();
      setupTagEntity();
      setupManyToManyRelation();
      const repo = new Repository('Post');

      const result = await repo.detach(1, 1, 'tags');
      expect(result.success).assertEqual(false);
      expect(result.errorMessage.length > 0).assertEqual(true);
    });

    it('sync should throw RelationNotFoundError for unregistered relation', 0, async () => {
      setupPostEntity();
      const repo = new Repository('Post');

      let threw = false;
      let errorType = '';
      try {
        await repo.sync(1, [1, 2, 3], 'unknownRelation');
      } catch (error) {
        threw = true;
        if (error instanceof RelationNotFoundError) {
          errorType = 'RelationNotFoundError';
        }
      }

      expect(threw).assertEqual(true);
      expect(errorType).assertEqual('RelationNotFoundError');
    });

    it('sync should return failure when database not initialized', 0, async () => {
      setupPostEntity();
      setupTagEntity();
      setupManyToManyRelation();
      const repo = new Repository('Post');

      const result = await repo.sync(1, [1, 2, 3], 'tags');
      expect(result.success).assertEqual(false);
      expect(result.errorMessage.length > 0).assertEqual(true);
    });

    it('sync with empty array should return failure when database not initialized', 0, async () => {
      setupPostEntity();
      setupTagEntity();
      setupManyToManyRelation();
      const repo = new Repository('Post');

      const result = await repo.sync(1, [], 'tags');
      expect(result.success).assertEqual(false);
    });

    it('getManyToManyRelation should return null for non-existent relation', 0, () => {
      setupPostEntity();
      const storage = MetadataStorage.getInstance();
      const relation = storage.getManyToManyRelation('Post', 'nonExistent');
      expect(relation).assertEqual(null);
    });

    it('getManyToManyRelation should return null for non-existent entity', 0, () => {
      const storage = MetadataStorage.getInstance();
      const relation = storage.getManyToManyRelation('NonExistent', 'tags');
      expect(relation).assertEqual(null);
    });

    it('RelationNotFoundError should have correct properties', 0, () => {
      const error = new RelationNotFoundError('Post', 'tags');
      expect(error.message.length > 0).assertEqual(true);
    });
  });
}
