import { describe, beforeEach, it, expect } from '@ohos/hypium';
import { MetadataStorage } from '../../main/ets/core/MetadataStorage';
import { ColumnMetadata } from '../../main/ets/core/ColumnMetadata';
import { RelationMetadata } from '../../main/ets/core/RelationMetadata';
import { ManyToManyMetadata } from '../../main/ets/core/ManyToManyMetadata';
import { ColumnType } from '../../main/ets/types/ColumnType';
import { RelationType } from '../../main/ets/types/RelationType';
import { RelationLoader } from '../../main/ets/query/RelationLoader';
import { EntityData } from '../../main/ets/mapping/DataMapper';
import { RelationNotFoundError } from '../../main/ets/errors/RelationError';
import { CascadeHandler, CascadeRepository, CascadeResultLike } from '../../main/ets/repository/CascadeHandler';
import { ExecutionError } from '../../main/ets/errors/DatabaseError';
import { ValueType } from '../../main/ets/types/ValueTypes';
import { Repository } from '../../main/ets/repository/Repository';
import { HooksProcessor } from '../../main/ets/core/HooksProcessor';

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

const setupUserEntityNoPrimaryKey = (): void => {
  const storage = MetadataStorage.getInstance();
  storage.registerEntity('UserNoPK', 'users_no_pk');

  const nameColumn = new ColumnMetadata('name', 'user_name')
    .setType(ColumnType.TEXT);
  storage.registerColumn('UserNoPK', nameColumn);
};

const setupPostEntity = (): void => {
  const storage = MetadataStorage.getInstance();
  storage.registerEntity('Post', 'posts');

  const idColumn = new ColumnMetadata('id', 'id')
    .setType(ColumnType.INTEGER)
    .setPrimaryKey(true)
    .setAutoIncrement(true);
  storage.registerColumn('Post', idColumn);

  const userIdColumn = new ColumnMetadata('userId', 'user_id')
    .setType(ColumnType.INTEGER);
  storage.registerColumn('Post', userIdColumn);

  const titleColumn = new ColumnMetadata('title', 'title')
    .setType(ColumnType.TEXT);
  storage.registerColumn('Post', titleColumn);
};

const setupPostEntityNoForeignKey = (): void => {
  const storage = MetadataStorage.getInstance();
  storage.registerEntity('PostNoFK', 'posts_no_fk');

  const idColumn = new ColumnMetadata('id', 'id')
    .setType(ColumnType.INTEGER)
    .setPrimaryKey(true)
    .setAutoIncrement(true);
  storage.registerColumn('PostNoFK', idColumn);

  const titleColumn = new ColumnMetadata('title', 'title')
    .setType(ColumnType.TEXT);
  storage.registerColumn('PostNoFK', titleColumn);
};

const setupProfileEntity = (): void => {
  const storage = MetadataStorage.getInstance();
  storage.registerEntity('Profile', 'profiles');

  const idColumn = new ColumnMetadata('id', 'id')
    .setType(ColumnType.INTEGER)
    .setPrimaryKey(true)
    .setAutoIncrement(true);
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
    .setPrimaryKey(true)
    .setAutoIncrement(true);
  storage.registerColumn('Tag', idColumn);

  const nameColumn = new ColumnMetadata('name', 'name')
    .setType(ColumnType.TEXT);
  storage.registerColumn('Tag', nameColumn);
};

const setupOneToOneSourceRelation = (cascade: boolean = false): void => {
  const storage = MetadataStorage.getInstance();
  const relation = new RelationMetadata(
    RelationType.ONE_TO_ONE,
    'Profile',
    'User',
    'user',
    'user_id',
    'source',
    cascade ? true : null
  );
  storage.registerRelation('Profile', relation);
};

const setupOneToOneTargetRelation = (cascade: boolean = false): void => {
  const storage = MetadataStorage.getInstance();
  const relation = new RelationMetadata(
    RelationType.ONE_TO_ONE,
    'User',
    'Profile',
    'profile',
    'user_id',
    'target',
    cascade ? true : null
  );
  storage.registerRelation('User', relation);
};

const setupOneToManyRelation = (cascade: boolean = false): void => {
  const storage = MetadataStorage.getInstance();
  const relation = new RelationMetadata(
    RelationType.ONE_TO_MANY,
    'User',
    'Post',
    'posts',
    'user_id',
    'source',
    cascade ? true : null
  );
  storage.registerRelation('User', relation);
};

const setupOneToManyRelationNoPK = (): void => {
  const storage = MetadataStorage.getInstance();
  const relation = new RelationMetadata(
    RelationType.ONE_TO_MANY,
    'UserNoPK',
    'Post',
    'posts',
    'user_id'
  );
  storage.registerRelation('UserNoPK', relation);
};

const setupOneToManyRelationNoFK = (): void => {
  const storage = MetadataStorage.getInstance();
  const relation = new RelationMetadata(
    RelationType.ONE_TO_MANY,
    'User',
    'PostNoFK',
    'posts',
    'user_id'
  );
  storage.registerRelation('User', relation);
};

const setupManyToOneRelation = (cascade: boolean = false): void => {
  const storage = MetadataStorage.getInstance();
  const relation = new RelationMetadata(
    RelationType.MANY_TO_ONE,
    'Post',
    'User',
    'user',
    'user_id',
    'source',
    cascade ? true : null
  );
  storage.registerRelation('Post', relation);
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

class MockCascadeRepository implements CascadeRepository {
  saveCallCount: number = 0;
  removeCallCount: number = 0;
  syncCallCount: number = 0;
  shouldFail: boolean = false;
  savedEntities: Array<EntityData> = [];
  removedEntities: Array<EntityData> = [];

  async save(entityData: EntityData): Promise<CascadeResultLike> {
    this.saveCallCount++;
    this.savedEntities.push(entityData);
    if (this.shouldFail) {
      return { success: false, errorMessage: 'Mock save failed' };
    }
    return { success: true };
  }

  async remove(entityData: EntityData): Promise<CascadeResultLike> {
    this.removeCallCount++;
    this.removedEntities.push(entityData);
    if (this.shouldFail) {
      return { success: false, errorMessage: 'Mock remove failed' };
    }
    return { success: true };
  }

  async sync(sourceId: ValueType, targetIds: Array<ValueType>, relationName: string): Promise<CascadeResultLike> {
    this.syncCallCount++;
    if (this.shouldFail) {
      return { success: false, errorMessage: 'Mock sync failed' };
    }
    return { success: true };
  }
}

export default function relationsTest() {
  describe('Stage13_Relations_Test', () => {
    beforeEach(() => {
      MetadataStorage.resetInstance();
      HooksProcessor.resetInstance();
    });

    it('OneToOne_source_register_correctly', 0, () => {
      setupUserEntity();
      setupProfileEntity();
      setupOneToOneSourceRelation();
      const storage = MetadataStorage.getInstance();
      const relation = storage.getRelation('Profile', 'user');
      expect(relation !== null).assertEqual(true);
      expect(relation?.type).assertEqual(RelationType.ONE_TO_ONE);
      expect(relation?.foreignKeySide).assertEqual('source');
    });

    it('OneToOne_target_register_correctly', 0, () => {
      setupUserEntity();
      setupProfileEntity();
      setupOneToOneTargetRelation();
      const storage = MetadataStorage.getInstance();
      const relation = storage.getRelation('User', 'profile');
      expect(relation !== null).assertEqual(true);
      expect(relation?.type).assertEqual(RelationType.ONE_TO_ONE);
      expect(relation?.foreignKeySide).assertEqual('target');
    });

    it('OneToOne_source_load_without_db', 0, async () => {
      setupUserEntity();
      setupProfileEntity();
      setupOneToOneSourceRelation();
      const loader = new RelationLoader('Profile');
      const entity = new EntityData('Profile');
      entity.addProperty('id', 1, 'number');
      entity.addProperty('userId', 1, 'number');
      const result = await loader.loadRelation([entity], 'user');
      expect(result.length).assertEqual(1);
    });

    it('OneToOne_target_load_without_db', 0, async () => {
      setupUserEntity();
      setupProfileEntity();
      setupOneToOneTargetRelation();
      const loader = new RelationLoader('User');
      const entity = new EntityData('User');
      entity.addProperty('id', 1, 'number');
      const result = await loader.loadRelation([entity], 'profile');
      expect(result.length).assertEqual(1);
    });

    it('OneToOne_source_null_when_fk_empty', 0, async () => {
      setupUserEntity();
      setupProfileEntity();
      setupOneToOneSourceRelation();
      const loader = new RelationLoader('Profile');
      const entity = new EntityData('Profile');
      entity.addProperty('id', 1, 'number');
      const result = await loader.loadRelation([entity], 'user');
      expect(result.length).assertEqual(1);
      expect(entity.getRelatedSingle('user')).assertEqual(null);
    });

    it('OneToOne_target_null_when_pk_empty', 0, async () => {
      setupUserEntity();
      setupProfileEntity();
      setupOneToOneTargetRelation();
      const loader = new RelationLoader('User');
      const entity = new EntityData('User');
      entity.addProperty('name', 'Test', 'string');
      const result = await loader.loadRelation([entity], 'profile');
      expect(result.length).assertEqual(1);
    });

    it('OneToOne_handle_multiple_entities', 0, async () => {
      setupUserEntity();
      setupProfileEntity();
      setupOneToOneSourceRelation();
      const loader = new RelationLoader('Profile');
      const entity1 = new EntityData('Profile');
      entity1.addProperty('id', 1, 'number');
      entity1.addProperty('userId', 1, 'number');
      const entity2 = new EntityData('Profile');
      entity2.addProperty('id', 2, 'number');
      entity2.addProperty('userId', 2, 'number');
      const result = await loader.loadRelation([entity1, entity2], 'user');
      expect(result.length).assertEqual(2);
    });

    it('OneToOne_source_cascade_save', 0, async () => {
      setupUserEntity();
      setupProfileEntity();
      setupOneToOneSourceRelation(true);
      const handler = CascadeHandler.getInstance();
      const mockRepo = new MockCascadeRepository();
      const userData = new EntityData('User');
      userData.addProperty('id', 1, 'number');
      userData.addProperty('name', 'Test User', 'string');
      const profileData = new EntityData('Profile');
      profileData.addProperty('bio', 'Test Bio', 'string');
      profileData.setRelatedSingle('user', userData);
      await handler.handleBeforeSave('Profile', profileData, 'insert', () => mockRepo);
      expect(mockRepo.saveCallCount).assertEqual(1);
    });

    it('OneToOne_target_cascade_save', 0, async () => {
      setupUserEntity();
      setupProfileEntity();
      setupOneToOneTargetRelation(true);
      const handler = CascadeHandler.getInstance();
      const mockRepo = new MockCascadeRepository();
      const profileData = new EntityData('Profile');
      profileData.addProperty('bio', 'Test Bio', 'string');
      const userData = new EntityData('User');
      userData.addProperty('id', 1, 'number');
      userData.addProperty('name', 'Test User', 'string');
      userData.setRelatedSingle('profile', profileData);
      await handler.handleAfterSave('User', userData, 'insert', mockRepo, () => mockRepo);
      expect(mockRepo.saveCallCount).assertEqual(1);
    });

    it('OneToMany_register_correctly', 0, () => {
      setupUserEntity();
      setupPostEntity();
      setupOneToManyRelation();
      const storage = MetadataStorage.getInstance();
      const relation = storage.getRelation('User', 'posts');
      expect(relation !== null).assertEqual(true);
      expect(relation?.type).assertEqual(RelationType.ONE_TO_MANY);
    });

    it('OneToMany_entity_without_pk', 0, async () => {
      setupUserEntityNoPrimaryKey();
      setupPostEntity();
      setupOneToManyRelationNoPK();
      const loader = new RelationLoader('UserNoPK');
      const entity = new EntityData('UserNoPK');
      entity.addProperty('name', 'Test', 'string');
      const result = await loader.loadRelation([entity], 'posts');
      expect(result.length).assertEqual(1);
    });

    it('OneToMany_entity_with_null_pk', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupOneToManyRelation();
      const loader = new RelationLoader('User');
      const entity = new EntityData('User');
      entity.addProperty('id', null, 'number');
      entity.addProperty('name', 'Test', 'string');
      const result = await loader.loadRelation([entity], 'posts');
      expect(result.length).assertEqual(1);
    });

    it('OneToMany_child_without_fk_column', 0, async () => {
      setupUserEntity();
      setupPostEntityNoForeignKey();
      setupOneToManyRelationNoFK();
      const loader = new RelationLoader('User');
      const entity = new EntityData('User');
      entity.addProperty('id', 1, 'number');
      const result = await loader.loadRelation([entity], 'posts');
      expect(result.length).assertEqual(1);
    });

    it('OneToMany_load_multiple_children', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupOneToManyRelation();
      const loader = new RelationLoader('User');
      const entity = new EntityData('User');
      entity.addProperty('id', 1, 'number');
      entity.addProperty('name', 'Test User', 'string');
      const result = await loader.loadRelation([entity], 'posts');
      expect(result.length).assertEqual(1);
    });

    it('OneToMany_cascade_save_children', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupOneToManyRelation(true);
      const handler = CascadeHandler.getInstance();
      const mockRepo = new MockCascadeRepository();
      const postData1 = new EntityData('Post');
      postData1.addProperty('title', 'Post 1', 'string');
      const postData2 = new EntityData('Post');
      postData2.addProperty('title', 'Post 2', 'string');
      const userData = new EntityData('User');
      userData.addProperty('id', 1, 'number');
      userData.addProperty('name', 'Test User', 'string');
      userData.setRelatedArray('posts', [postData1, postData2]);
      await handler.handleAfterSave('User', userData, 'insert', mockRepo, () => mockRepo);
      expect(mockRepo.saveCallCount).assertEqual(2);
    });

    it('OneToMany_cascade_delete_children', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupOneToManyRelation(true);
      const handler = CascadeHandler.getInstance();
      const mockRepo = new MockCascadeRepository();
      const postData = new EntityData('Post');
      postData.addProperty('id', 1, 'number');
      postData.addProperty('title', 'Test Post', 'string');
      const userData = new EntityData('User');
      userData.addProperty('id', 1, 'number');
      userData.addProperty('name', 'Test User', 'string');
      userData.setRelatedArray('posts', [postData]);
      await handler.handleBeforeRemove('User', userData, mockRepo, () => mockRepo);
      expect(mockRepo.removeCallCount).assertEqual(1);
    });

    it('OneToMany_skip_cascade_when_no_pk', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupOneToManyRelation(true);
      const handler = CascadeHandler.getInstance();
      const mockRepo = new MockCascadeRepository();
      const postData = new EntityData('Post');
      postData.addProperty('title', 'Test Post', 'string');
      const userData = new EntityData('User');
      userData.addProperty('name', 'Test User', 'string');
      userData.setRelatedArray('posts', [postData]);
      await handler.handleAfterSave('User', userData, 'insert', mockRepo, () => mockRepo);
      expect(mockRepo.saveCallCount).assertEqual(0);
    });

    it('ManyToOne_register_correctly', 0, () => {
      setupUserEntity();
      setupPostEntity();
      setupManyToOneRelation();
      const storage = MetadataStorage.getInstance();
      const relation = storage.getRelation('Post', 'user');
      expect(relation !== null).assertEqual(true);
      expect(relation?.type).assertEqual(RelationType.MANY_TO_ONE);
    });

    it('ManyToOne_handle_empty_fk', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupManyToOneRelation();
      const loader = new RelationLoader('Post');
      const entity = new EntityData('Post');
      entity.addProperty('id', 1, 'number');
      entity.addProperty('title', 'Test Post', 'string');
      const result = await loader.loadRelation([entity], 'user');
      expect(result.length).assertEqual(1);
      expect(entity.getRelatedSingle('user')).assertEqual(null);
    });

    it('ManyToOne_handle_null_fk', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupManyToOneRelation();
      const loader = new RelationLoader('Post');
      const entity = new EntityData('Post');
      entity.addProperty('id', 1, 'number');
      entity.addProperty('userId', null, 'number');
      entity.addProperty('title', 'Test Post', 'string');
      const result = await loader.loadRelation([entity], 'user');
      expect(result.length).assertEqual(1);
      expect(entity.getRelatedSingle('user')).assertEqual(null);
    });

    it('ManyToOne_handle_duplicate_fks', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupManyToOneRelation();
      const loader = new RelationLoader('Post');
      const entity1 = new EntityData('Post');
      entity1.addProperty('id', 1, 'number');
      entity1.addProperty('userId', 1, 'number');
      const entity2 = new EntityData('Post');
      entity2.addProperty('id', 2, 'number');
      entity2.addProperty('userId', 1, 'number');
      const entity3 = new EntityData('Post');
      entity3.addProperty('id', 3, 'number');
      entity3.addProperty('userId', 1, 'number');
      const result = await loader.loadRelation([entity1, entity2, entity3], 'user');
      expect(result.length).assertEqual(3);
    });

    it('ManyToOne_cascade_save_parent', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupManyToOneRelation(true);
      const handler = CascadeHandler.getInstance();
      const mockRepo = new MockCascadeRepository();
      const userData = new EntityData('User');
      userData.addProperty('id', 1, 'number');
      userData.addProperty('name', 'Test User', 'string');
      const postData = new EntityData('Post');
      postData.addProperty('title', 'Test Post', 'string');
      postData.setRelatedSingle('user', userData);
      await handler.handleBeforeSave('Post', postData, 'insert', () => mockRepo);
      expect(mockRepo.saveCallCount).assertEqual(1);
    });

    it('ManyToOne_cascade_throw_error_on_fail', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupManyToOneRelation(true);
      const handler = CascadeHandler.getInstance();
      const mockRepo = new MockCascadeRepository();
      mockRepo.shouldFail = true;
      const userData = new EntityData('User');
      userData.addProperty('name', 'Test User', 'string');
      const postData = new EntityData('Post');
      postData.addProperty('title', 'Test Post', 'string');
      postData.setRelatedSingle('user', userData);
      let threw = false;
      let errorType = '';
      try {
        await handler.handleBeforeSave('Post', postData, 'insert', () => mockRepo);
      } catch (e) {
        threw = true;
        if (e instanceof ExecutionError) {
          errorType = 'ExecutionError';
        }
      }
      expect(threw).assertEqual(true);
      expect(errorType).assertEqual('ExecutionError');
    });

    it('ManyToMany_register_correctly', 0, () => {
      setupPostEntity();
      setupTagEntity();
      setupManyToManyRelation();
      const storage = MetadataStorage.getInstance();
      const relation = storage.getManyToManyRelation('Post', 'tags');
      expect(relation !== null).assertEqual(true);
      expect(relation?.joinTable).assertEqual('post_tags');
      expect(relation?.joinSourceKey).assertEqual('post_id');
      expect(relation?.joinTargetKey).assertEqual('tag_id');
    });

    it('ManyToMany_null_for_missing_join_table', 0, () => {
      setupPostEntity();
      setupTagEntity();
      const storage = MetadataStorage.getInstance();
      const relation = storage.getManyToManyRelation('Post', 'tags');
      expect(relation).assertEqual(null);
    });

    it('ManyToMany_handle_duplicate_registration', 0, () => {
      setupPostEntity();
      setupTagEntity();
      const storage = MetadataStorage.getInstance();
      storage.registerManyToMany('Post', 'Tag', 'tags', 'post_tags', 'post_id', 'tag_id');
      storage.registerManyToMany('Post', 'Tag', 'tags', 'post_tags', 'post_id', 'tag_id');
      const relation = storage.getManyToManyRelation('Post', 'tags');
      expect(relation !== null).assertEqual(true);
    });

    it('ManyToMany_load_without_db', 0, async () => {
      setupPostEntity();
      setupTagEntity();
      setupManyToManyRelation();
      const loader = new RelationLoader('Post');
      const entity = new EntityData('Post');
      entity.addProperty('id', 1, 'number');
      entity.addProperty('title', 'Test Post', 'string');
      const result = await loader.loadRelation([entity], 'tags');
      expect(result.length).assertEqual(1);
    });

    it('ManyToMany_entity_without_pk', 0, async () => {
      setupPostEntity();
      setupTagEntity();
      setupManyToManyRelation();
      const loader = new RelationLoader('Post');
      const entity = new EntityData('Post');
      entity.addProperty('title', 'Test Post', 'string');
      const result = await loader.loadRelation([entity], 'tags');
      expect(result.length).assertEqual(1);
    });

    it('ManyToMany_attach_throw_for_unregistered', 0, async () => {
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

    it('ManyToMany_detach_throw_for_unregistered', 0, async () => {
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

    it('ManyToMany_sync_throw_for_unregistered', 0, async () => {
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

    it('ManyToMany_failure_when_db_not_init', 0, async () => {
      setupPostEntity();
      setupTagEntity();
      setupManyToManyRelation();
      const repo = new Repository('Post');
      const result = await repo.attach(1, 1, 'tags');
      expect(result.success).assertEqual(false);
      expect(result.errorMessage.length > 0).assertEqual(true);
    });

    it('Cascade_before_save_hooks', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupManyToOneRelation(true);
      const handler = CascadeHandler.getInstance();
      const mockRepo = new MockCascadeRepository();
      const userData = new EntityData('User');
      userData.addProperty('id', 1, 'number');
      userData.addProperty('name', 'Parent', 'string');
      const postData = new EntityData('Post');
      postData.addProperty('title', 'Child', 'string');
      postData.setRelatedSingle('user', userData);
      let threw = false;
      try {
        await handler.handleBeforeSave('Post', postData, 'insert', () => mockRepo);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertEqual(false);
      expect(mockRepo.saveCallCount).assertEqual(1);
    });

    it('Cascade_after_save_hooks', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupOneToManyRelation(true);
      const handler = CascadeHandler.getInstance();
      const mockRepo = new MockCascadeRepository();
      const postData = new EntityData('Post');
      postData.addProperty('title', 'Child', 'string');
      const userData = new EntityData('User');
      userData.addProperty('id', 1, 'number');
      userData.addProperty('name', 'Parent', 'string');
      userData.setRelatedArray('posts', [postData]);
      let threw = false;
      try {
        await handler.handleAfterSave('User', userData, 'insert', mockRepo, () => mockRepo);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertEqual(false);
      expect(mockRepo.saveCallCount).assertEqual(1);
    });

    it('Cascade_before_remove_hooks', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupOneToManyRelation(true);
      const handler = CascadeHandler.getInstance();
      const mockRepo = new MockCascadeRepository();
      const postData = new EntityData('Post');
      postData.addProperty('id', 1, 'number');
      postData.addProperty('title', 'Child', 'string');
      const userData = new EntityData('User');
      userData.addProperty('id', 1, 'number');
      userData.addProperty('name', 'Parent', 'string');
      userData.setRelatedArray('posts', [postData]);
      let threw = false;
      try {
        await handler.handleBeforeRemove('User', userData, mockRepo, () => mockRepo);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertEqual(false);
      expect(mockRepo.removeCallCount).assertEqual(1);
    });

    it('Cascade_throw_on_save_fail', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupOneToManyRelation(true);
      const handler = CascadeHandler.getInstance();
      const mockRepo = new MockCascadeRepository();
      mockRepo.shouldFail = true;
      const postData = new EntityData('Post');
      postData.addProperty('title', 'Child', 'string');
      const userData = new EntityData('User');
      userData.addProperty('id', 1, 'number');
      userData.addProperty('name', 'Parent', 'string');
      userData.setRelatedArray('posts', [postData]);
      let threw = false;
      let errorType = '';
      try {
        await handler.handleAfterSave('User', userData, 'insert', mockRepo, () => mockRepo);
      } catch (e) {
        threw = true;
        if (e instanceof ExecutionError) {
          errorType = 'ExecutionError';
        }
      }
      expect(threw).assertEqual(true);
      expect(errorType).assertEqual('ExecutionError');
    });

    it('Cascade_throw_on_remove_fail', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupOneToManyRelation(true);
      const handler = CascadeHandler.getInstance();
      const mockRepo = new MockCascadeRepository();
      mockRepo.shouldFail = true;
      const postData = new EntityData('Post');
      postData.addProperty('id', 1, 'number');
      postData.addProperty('title', 'Child', 'string');
      const userData = new EntityData('User');
      userData.addProperty('id', 1, 'number');
      userData.addProperty('name', 'Parent', 'string');
      userData.setRelatedArray('posts', [postData]);
      let threw = false;
      let errorType = '';
      try {
        await handler.handleBeforeRemove('User', userData, mockRepo, () => mockRepo);
      } catch (e) {
        threw = true;
        if (e instanceof ExecutionError) {
          errorType = 'ExecutionError';
        }
      }
      expect(threw).assertEqual(true);
      expect(errorType).assertEqual('ExecutionError');
    });

    it('Cascade_skip_when_not_enabled', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupOneToManyRelation(false);
      const handler = CascadeHandler.getInstance();
      const mockRepo = new MockCascadeRepository();
      const postData = new EntityData('Post');
      postData.addProperty('title', 'Child', 'string');
      const userData = new EntityData('User');
      userData.addProperty('id', 1, 'number');
      userData.addProperty('name', 'Parent', 'string');
      userData.setRelatedArray('posts', [postData]);
      await handler.handleAfterSave('User', userData, 'insert', mockRepo, () => mockRepo);
      expect(mockRepo.saveCallCount).assertEqual(0);
    });

    it('Cascade_skip_when_no_related_data', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupOneToManyRelation(true);
      const handler = CascadeHandler.getInstance();
      const mockRepo = new MockCascadeRepository();
      const userData = new EntityData('User');
      userData.addProperty('id', 1, 'number');
      userData.addProperty('name', 'Parent', 'string');
      await handler.handleAfterSave('User', userData, 'insert', mockRepo, () => mockRepo);
      expect(mockRepo.saveCallCount).assertEqual(0);
    });

    it('Cascade_handle_empty_array', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupOneToManyRelation(true);
      const handler = CascadeHandler.getInstance();
      const mockRepo = new MockCascadeRepository();
      const userData = new EntityData('User');
      userData.addProperty('id', 1, 'number');
      userData.addProperty('name', 'Parent', 'string');
      userData.setRelatedArray('posts', []);
      await handler.handleAfterSave('User', userData, 'insert', mockRepo, () => mockRepo);
      expect(mockRepo.saveCallCount).assertEqual(0);
    });

    it('Cascade_handle_multiple_entities', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupOneToManyRelation(true);
      const handler = CascadeHandler.getInstance();
      const mockRepo = new MockCascadeRepository();
      const posts: Array<EntityData> = [];
      for (let i = 0; i < 5; i++) {
        const postData = new EntityData('Post');
        postData.addProperty('title', `Post ${i}`, 'string');
        posts.push(postData);
      }
      const userData = new EntityData('User');
      userData.addProperty('id', 1, 'number');
      userData.addProperty('name', 'Parent', 'string');
      userData.setRelatedArray('posts', posts);
      await handler.handleAfterSave('User', userData, 'insert', mockRepo, () => mockRepo);
      expect(mockRepo.saveCallCount).assertEqual(5);
    });

    it('RelationMetadata_store_all_properties', 0, () => {
      const relation = new RelationMetadata(
        RelationType.ONE_TO_ONE,
        'User',
        'Profile',
        'profile',
        'user_id',
        'target',
        true
      );
      expect(relation.type).assertEqual(RelationType.ONE_TO_ONE);
      expect(relation.sourceEntity).assertEqual('User');
      expect(relation.targetEntity).assertEqual('Profile');
      expect(relation.propertyName).assertEqual('profile');
      expect(relation.inverseKey).assertEqual('user_id');
      expect(relation.foreignKeySide).assertEqual('target');
      expect(relation.cascade).assertEqual(true);
    });

    it('ManyToManyMetadata_store_all_properties', 0, () => {
      const metadata = new ManyToManyMetadata(
        'Post',
        'Tag',
        'tags',
        'post_tags',
        'post_id',
        'tag_id'
      );
      expect(metadata.type).assertEqual(RelationType.MANY_TO_MANY);
      expect(metadata.sourceEntity).assertEqual('Post');
      expect(metadata.targetEntity).assertEqual('Tag');
      expect(metadata.propertyName).assertEqual('tags');
      expect(metadata.joinTable).assertEqual('post_tags');
      expect(metadata.joinSourceKey).assertEqual('post_id');
      expect(metadata.joinTargetKey).assertEqual('tag_id');
    });

    it('hasRelation_return_true_for_registered', 0, () => {
      setupUserEntity();
      setupPostEntity();
      setupOneToManyRelation();
      const storage = MetadataStorage.getInstance();
      expect(storage.hasRelation('User', 'posts')).assertEqual(true);
    });

    it('hasRelation_return_false_for_unregistered', 0, () => {
      setupUserEntity();
      const storage = MetadataStorage.getInstance();
      expect(storage.hasRelation('User', 'posts')).assertEqual(false);
    });

    it('getRelations_return_all_for_entity', 0, () => {
      setupUserEntity();
      setupPostEntity();
      setupProfileEntity();
      setupOneToManyRelation();
      setupOneToOneTargetRelation();
      const storage = MetadataStorage.getInstance();
      const relations = storage.getRelations('User');
      expect(relations.length).assertEqual(2);
    });

    it('getRelation_return_null_for_nonexistent_entity', 0, () => {
      const storage = MetadataStorage.getInstance();
      const relation = storage.getRelation('NonExistent', 'relation');
      expect(relation).assertEqual(null);
    });

    it('getRelation_return_null_for_nonexistent_relation', 0, () => {
      setupUserEntity();
      const storage = MetadataStorage.getInstance();
      const relation = storage.getRelation('User', 'nonExistent');
      expect(relation).assertEqual(null);
    });

    it('loadRelationsParallel_handle_empty_entities', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupOneToManyRelation();
      const loader = new RelationLoader('User');
      const result = await loader.loadRelationsParallel([], ['posts']);
      expect(result.length).assertEqual(0);
    });

    it('loadRelationsParallel_handle_empty_relation_names', 0, async () => {
      setupUserEntity();
      const loader = new RelationLoader('User');
      const entity = new EntityData('User');
      entity.addProperty('id', 1, 'number');
      const result = await loader.loadRelationsParallel([entity], []);
      expect(result.length).assertEqual(1);
    });

    it('loadRelationsParallel_handle_single_relation', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupOneToManyRelation();
      const loader = new RelationLoader('User');
      const entity = new EntityData('User');
      entity.addProperty('id', 1, 'number');
      const result = await loader.loadRelationsParallel([entity], ['posts']);
      expect(result.length).assertEqual(1);
    });

    it('loadRelationsParallel_handle_multiple_relations', 0, async () => {
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

    it('loadRelationsParallel_handle_invalid_relation', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupOneToManyRelation();
      const loader = new RelationLoader('User');
      const entity = new EntityData('User');
      entity.addProperty('id', 1, 'number');
      const result = await loader.loadRelationsParallel([entity], ['invalidRelation']);
      expect(result.length).assertEqual(1);
    });

    it('loadRelationsParallel_handle_mixed_relations', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupOneToManyRelation();
      const loader = new RelationLoader('User');
      const entity = new EntityData('User');
      entity.addProperty('id', 1, 'number');
      const result = await loader.loadRelationsParallel([entity], ['posts', 'invalidRelation']);
      expect(result.length).assertEqual(1);
    });
  });
}
