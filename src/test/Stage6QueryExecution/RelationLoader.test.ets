import { describe, beforeEach, it, expect } from '@ohos/hypium';
import { MetadataStorage } from '../../main/ets/core/MetadataStorage';
import { ColumnMetadata } from '../../main/ets/core/ColumnMetadata';
import { RelationMetadata } from '../../main/ets/core/RelationMetadata';
import { ManyToManyMetadata } from '../../main/ets/core/ManyToManyMetadata';
import { RelationType } from '../../main/ets/types/RelationType';
import { ColumnType } from '../../main/ets/types/ColumnType';
import { RelationLoader } from '../../main/ets/query/RelationLoader';
import { EntityData } from '../../main/ets/mapping/DataMapper';
import { RelationNotFoundError } from '../../main/ets/errors/RelationError';

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

const setupPostEntity = (): void => {
  const storage = MetadataStorage.getInstance();
  storage.registerEntity('Post', 'posts');

  const idColumn = new ColumnMetadata('id', 'id')
    .setType(ColumnType.INTEGER)
    .setPrimaryKey(true);
  storage.registerColumn('Post', idColumn);

  const userIdColumn = new ColumnMetadata('userId', 'user_id')
    .setType(ColumnType.INTEGER);
  storage.registerColumn('Post', userIdColumn);

  const titleColumn = new ColumnMetadata('title', 'title')
    .setType(ColumnType.TEXT);
  storage.registerColumn('Post', titleColumn);
};

const setupProfileEntity = (): void => {
  const storage = MetadataStorage.getInstance();
  storage.registerEntity('Profile', 'profiles');

  const idColumn = new ColumnMetadata('id', 'id')
    .setType(ColumnType.INTEGER)
    .setPrimaryKey(true);
  storage.registerColumn('Profile', idColumn);

  const userIdColumn = new ColumnMetadata('userId', 'user_id')
    .setType(ColumnType.INTEGER);
  storage.registerColumn('Profile', userIdColumn);

  const bioColumn = new ColumnMetadata('bio', 'bio')
    .setType(ColumnType.TEXT);
  storage.registerColumn('Profile', bioColumn);
};

const setupTagEntity = (): void => {
  const storage = MetadataStorage.getInstance();
  storage.registerEntity('Tag', 'tags');

  const idColumn = new ColumnMetadata('id', 'id')
    .setType(ColumnType.INTEGER)
    .setPrimaryKey(true);
  storage.registerColumn('Tag', idColumn);

  const nameColumn = new ColumnMetadata('name', 'name')
    .setType(ColumnType.TEXT);
  storage.registerColumn('Tag', nameColumn);
};

const setupOneToManyRelation = (): void => {
  const storage = MetadataStorage.getInstance();
  const relation = new RelationMetadata(
    RelationType.ONE_TO_MANY,
    'User',
    'Post',
    'posts',
    'user_id'
  );
  storage.registerRelation('User', relation);
};

const setupManyToOneRelation = (): void => {
  const storage = MetadataStorage.getInstance();
  const relation = new RelationMetadata(
    RelationType.MANY_TO_ONE,
    'Post',
    'User',
    'user',
    'user_id'
  );
  storage.registerRelation('Post', relation);
};

const setupOneToOneSourceRelation = (): void => {
  const storage = MetadataStorage.getInstance();
  const relation = new RelationMetadata(
    RelationType.ONE_TO_ONE,
    'User',
    'Profile',
    'profile',
    'user_id'
  );
  relation.foreignKeySide = 'source';
  storage.registerRelation('User', relation);
};

const setupOneToOneTargetRelation = (): void => {
  const storage = MetadataStorage.getInstance();
  const relation = new RelationMetadata(
    RelationType.ONE_TO_ONE,
    'User',
    'Profile',
    'profile',
    'user_id'
  );
  relation.foreignKeySide = 'target';
  storage.registerRelation('User', relation);
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

export default function relationLoaderTest() {
  describe('relationLoaderTest', () => {
    beforeEach(() => {
      MetadataStorage.resetInstance();
    });

    it('should create RelationLoader with source entity name', 0, () => {
      setupUserEntity();
      const loader = new RelationLoader('User');
      expect(loader !== null).assertEqual(true);
    });

    it('loadRelation should return entities when array is empty', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupOneToManyRelation();

      const loader = new RelationLoader('User');
      const entities: Array<EntityData> = [];
      const result = await loader.loadRelation(entities, 'posts');

      expect(result.length).assertEqual(0);
    });

    it('loadRelation should throw RelationNotFoundError for unregistered relation', 0, async () => {
      setupUserEntity();
      const loader = new RelationLoader('User');
      const entity = new EntityData('User');
      entity.addProperty('id', 1, 'number');

      let threw = false;
      let errorType = '';
      try {
        await loader.loadRelation([entity], 'invalidRelation');
      } catch (error) {
        threw = true;
        if (error instanceof RelationNotFoundError) {
          errorType = 'RelationNotFoundError';
        }
      }

      expect(threw).assertEqual(true);
      expect(errorType).assertEqual('RelationNotFoundError');
    });

    it('loadRelationsParallel should return entities when array is empty', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupOneToManyRelation();

      const loader = new RelationLoader('User');
      const entities: Array<EntityData> = [];
      const result = await loader.loadRelationsParallel(entities, ['posts']);

      expect(result.length).assertEqual(0);
    });

    it('loadRelationsParallel should return entities when relationNames is empty', 0, async () => {
      setupUserEntity();
      const loader = new RelationLoader('User');
      const entity = new EntityData('User');
      entity.addProperty('id', 1, 'number');

      const result = await loader.loadRelationsParallel([entity], []);
      expect(result.length).assertEqual(1);
    });

    it('loadRelation with ONE_TO_MANY should return entities without db', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupOneToManyRelation();

      const loader = new RelationLoader('User');
      const entity = new EntityData('User');
      entity.addProperty('id', 1, 'number');

      const result = await loader.loadRelation([entity], 'posts');
      expect(result.length).assertEqual(1);
    });

    it('loadRelation with MANY_TO_ONE should return entities without db', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupManyToOneRelation();

      const loader = new RelationLoader('Post');
      const entity = new EntityData('Post');
      entity.addProperty('id', 1, 'number');
      entity.addProperty('userId', 1, 'number');

      const result = await loader.loadRelation([entity], 'user');
      expect(result.length).assertEqual(1);
    });

    it('loadRelation with ONE_TO_ONE source side should return entities without db', 0, async () => {
      setupUserEntity();
      setupProfileEntity();
      setupOneToOneSourceRelation();

      const loader = new RelationLoader('User');
      const entity = new EntityData('User');
      entity.addProperty('id', 1, 'number');

      const result = await loader.loadRelation([entity], 'profile');
      expect(result.length).assertEqual(1);
    });

    it('loadRelation with ONE_TO_ONE target side should return entities without db', 0, async () => {
      setupUserEntity();
      setupProfileEntity();
      setupOneToOneTargetRelation();

      const loader = new RelationLoader('User');
      const entity = new EntityData('User');
      entity.addProperty('id', 1, 'number');

      const result = await loader.loadRelation([entity], 'profile');
      expect(result.length).assertEqual(1);
    });

    it('loadRelation with MANY_TO_MANY should return entities without db', 0, async () => {
      setupPostEntity();
      setupTagEntity();
      setupManyToManyRelation();

      const loader = new RelationLoader('Post');
      const entity = new EntityData('Post');
      entity.addProperty('id', 1, 'number');

      const result = await loader.loadRelation([entity], 'tags');
      expect(result.length).assertEqual(1);
    });

    it('loadRelation should handle entity without primary key', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupOneToManyRelation();

      const loader = new RelationLoader('User');
      const entity = new EntityData('User');
      entity.addProperty('name', 'Test', 'string');

      const result = await loader.loadRelation([entity], 'posts');
      expect(result.length).assertEqual(1);
    });

    it('loadRelation should handle entity with null primary key', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupOneToManyRelation();

      const loader = new RelationLoader('User');
      const entity = new EntityData('User');
      entity.addProperty('id', null, 'number');

      const result = await loader.loadRelation([entity], 'posts');
      expect(result.length).assertEqual(1);
    });

    it('loadRelation MANY_TO_ONE should handle entity without foreign key', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupManyToOneRelation();

      const loader = new RelationLoader('Post');
      const entity = new EntityData('Post');
      entity.addProperty('id', 1, 'number');

      const result = await loader.loadRelation([entity], 'user');
      expect(result.length).assertEqual(1);
      expect(entity.getRelatedSingle('user')).assertEqual(null);
    });

    it('loadRelation MANY_TO_ONE should handle entity with null foreign key', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupManyToOneRelation();

      const loader = new RelationLoader('Post');
      const entity = new EntityData('Post');
      entity.addProperty('id', 1, 'number');
      entity.addProperty('userId', null, 'number');

      const result = await loader.loadRelation([entity], 'user');
      expect(result.length).assertEqual(1);
      expect(entity.getRelatedSingle('user')).assertEqual(null);
    });

    it('loadRelationsParallel should handle single relation', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupOneToManyRelation();

      const loader = new RelationLoader('User');
      const entity = new EntityData('User');
      entity.addProperty('id', 1, 'number');

      const result = await loader.loadRelationsParallel([entity], ['posts']);
      expect(result.length).assertEqual(1);
    });

    it('loadRelationsParallel should handle multiple relations', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupProfileEntity();
      setupOneToManyRelation();
      setupOneToOneTargetRelation();

      const loader = new RelationLoader('User');
      const entity = new EntityData('User');
      entity.addProperty('id', 1, 'number');

      const result = await loader.loadRelationsParallel([entity], ['posts', 'profile']);
      expect(result.length).assertEqual(1);
    });

    it('loadRelationsParallel should handle invalid relation gracefully', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupOneToManyRelation();

      const loader = new RelationLoader('User');
      const entity = new EntityData('User');
      entity.addProperty('id', 1, 'number');

      const result = await loader.loadRelationsParallel([entity], ['invalidRelation']);
      expect(result.length).assertEqual(1);
    });

    it('loadRelationsParallel should handle mixed valid and invalid relations', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupOneToManyRelation();

      const loader = new RelationLoader('User');
      const entity = new EntityData('User');
      entity.addProperty('id', 1, 'number');

      const result = await loader.loadRelationsParallel([entity], ['posts', 'invalidRelation']);
      expect(result.length).assertEqual(1);
    });

    it('loadRelation with ONE_TO_ONE source should set null when no fk value', 0, async () => {
      setupUserEntity();
      setupProfileEntity();
      setupOneToOneSourceRelation();

      const loader = new RelationLoader('User');
      const entity = new EntityData('User');
      entity.addProperty('id', 1, 'number');

      const result = await loader.loadRelation([entity], 'profile');
      expect(result.length).assertEqual(1);
      expect(entity.getRelatedSingle('profile')).assertEqual(null);
    });

    it('loadRelation with ONE_TO_ONE target should set null when no pk value', 0, async () => {
      setupUserEntity();
      setupProfileEntity();
      setupOneToOneTargetRelation();

      const loader = new RelationLoader('User');
      const entity = new EntityData('User');

      const result = await loader.loadRelation([entity], 'profile');
      expect(result.length).assertEqual(1);
    });

    it('loadRelation with MANY_TO_MANY should set empty array when no pk', 0, async () => {
      setupPostEntity();
      setupTagEntity();
      setupManyToManyRelation();

      const loader = new RelationLoader('Post');
      const entity = new EntityData('Post');

      const result = await loader.loadRelation([entity], 'tags');
      expect(result.length).assertEqual(1);
    });
  });
}
