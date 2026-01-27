import { describe, beforeEach, it, expect } from '@ohos/hypium';
import { MetadataStorage } from '../../main/ets/core/MetadataStorage';
import { ColumnMetadata } from '../../main/ets/core/ColumnMetadata';
import { RelationMetadata } from '../../main/ets/core/RelationMetadata';
import { ColumnType } from '../../main/ets/types/ColumnType';
import { RelationType } from '../../main/ets/types/RelationType';
import { CascadeHandler, CascadeOperation, CascadeRepository, CascadeResultLike } from '../../main/ets/repository/CascadeHandler';
import { EntityData } from '../../main/ets/mapping/DataMapper';
import { ExecutionError } from '../../main/ets/errors/DatabaseError';
import { ValueType } from '../../main/ets/types/ValueTypes';

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

const setupOneToOneRelationSource = (cascade: boolean = false): void => {
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

const setupOneToOneRelationTarget = (cascade: boolean = false): void => {
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

class MockRepository implements CascadeRepository {
  saveCallCount: number = 0;
  removeCallCount: number = 0;
  syncCallCount: number = 0;
  shouldFail: boolean = false;

  async save(entityData: EntityData): Promise<CascadeResultLike> {
    this.saveCallCount++;
    if (this.shouldFail) {
      return { success: false, errorMessage: 'Mock save failed' };
    }
    return { success: true };
  }

  async remove(entityData: EntityData): Promise<CascadeResultLike> {
    this.removeCallCount++;
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

export default function cascadeHandlerTest() {
  describe('cascadeHandlerTest', () => {
    beforeEach(() => {
      MetadataStorage.resetInstance();
    });

    it('CascadeHandler should be singleton', 0, () => {
      const handler1 = CascadeHandler.getInstance();
      const handler2 = CascadeHandler.getInstance();
      expect(handler1 === handler2).assertEqual(true);
    });

    it('handleBeforeSave should do nothing for insert without cascade relations', 0, async () => {
      setupUserEntity();
      const handler = CascadeHandler.getInstance();
      const entityData = new EntityData('User');
      entityData.addProperty('name', 'Test', 'string');

      const mockRepo = new MockRepository();
      let threw = false;
      try {
        await handler.handleBeforeSave('User', entityData, 'insert', () => mockRepo);
      } catch (e) {
        threw = true;
      }

      expect(threw).assertEqual(false);
      expect(mockRepo.saveCallCount).assertEqual(0);
    });

    it('handleBeforeSave should do nothing for update without cascade relations', 0, async () => {
      setupUserEntity();
      const handler = CascadeHandler.getInstance();
      const entityData = new EntityData('User');
      entityData.addProperty('id', 1, 'number');
      entityData.addProperty('name', 'Test', 'string');

      const mockRepo = new MockRepository();
      let threw = false;
      try {
        await handler.handleBeforeSave('User', entityData, 'update', () => mockRepo);
      } catch (e) {
        threw = true;
      }

      expect(threw).assertEqual(false);
      expect(mockRepo.saveCallCount).assertEqual(0);
    });

    it('handleBeforeSave should skip remove operation', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupManyToOneRelation(true);
      const handler = CascadeHandler.getInstance();
      const entityData = new EntityData('Post');
      entityData.addProperty('id', 1, 'number');

      const mockRepo = new MockRepository();
      let threw = false;
      try {
        await handler.handleBeforeSave('Post', entityData, 'remove' as CascadeOperation, () => mockRepo);
      } catch (e) {
        threw = true;
      }

      expect(threw).assertEqual(false);
      expect(mockRepo.saveCallCount).assertEqual(0);
    });

    it('handleBeforeSave should process ManyToOne relation with cascade', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupManyToOneRelation(true);
      const handler = CascadeHandler.getInstance();

      const userData = new EntityData('User');
      userData.addProperty('id', 1, 'number');
      userData.addProperty('name', 'Test User', 'string');

      const postData = new EntityData('Post');
      postData.addProperty('title', 'Test Post', 'string');
      postData.setRelatedSingle('user', userData);

      const mockRepo = new MockRepository();
      let threw = false;
      try {
        await handler.handleBeforeSave('Post', postData, 'insert', () => mockRepo);
      } catch (e) {
        threw = true;
      }

      expect(threw).assertEqual(false);
      expect(mockRepo.saveCallCount).assertEqual(1);
    });

    it('handleBeforeSave should throw ExecutionError when cascade save fails', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupManyToOneRelation(true);
      const handler = CascadeHandler.getInstance();

      const userData = new EntityData('User');
      userData.addProperty('name', 'Test User', 'string');

      const postData = new EntityData('Post');
      postData.addProperty('title', 'Test Post', 'string');
      postData.setRelatedSingle('user', userData);

      const mockRepo = new MockRepository();
      mockRepo.shouldFail = true;

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

    it('handleAfterSave should do nothing without cascade relations', 0, async () => {
      setupUserEntity();
      const handler = CascadeHandler.getInstance();
      const entityData = new EntityData('User');
      entityData.addProperty('id', 1, 'number');
      entityData.addProperty('name', 'Test', 'string');

      const mockRepo = new MockRepository();
      let threw = false;
      try {
        await handler.handleAfterSave('User', entityData, 'insert', mockRepo, () => mockRepo);
      } catch (e) {
        threw = true;
      }

      expect(threw).assertEqual(false);
      expect(mockRepo.saveCallCount).assertEqual(0);
    });

    it('handleAfterSave should skip when source has no primary key', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupOneToManyRelation(true);
      const handler = CascadeHandler.getInstance();

      const entityData = new EntityData('User');
      entityData.addProperty('name', 'Test', 'string');

      const mockRepo = new MockRepository();
      let threw = false;
      try {
        await handler.handleAfterSave('User', entityData, 'insert', mockRepo, () => mockRepo);
      } catch (e) {
        threw = true;
      }

      expect(threw).assertEqual(false);
      expect(mockRepo.saveCallCount).assertEqual(0);
    });

    it('handleAfterSave should process OneToMany relation with cascade', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupOneToManyRelation(true);
      const handler = CascadeHandler.getInstance();

      const postData = new EntityData('Post');
      postData.addProperty('title', 'Test Post', 'string');

      const userData = new EntityData('User');
      userData.addProperty('id', 1, 'number');
      userData.addProperty('name', 'Test User', 'string');
      userData.setRelatedArray('posts', [postData]);

      const mockRepo = new MockRepository();
      let threw = false;
      try {
        await handler.handleAfterSave('User', userData, 'insert', mockRepo, () => mockRepo);
      } catch (e) {
        threw = true;
      }

      expect(threw).assertEqual(false);
      expect(mockRepo.saveCallCount).assertEqual(1);
    });

    it('handleAfterSave should throw ExecutionError when cascade save fails', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupOneToManyRelation(true);
      const handler = CascadeHandler.getInstance();

      const postData = new EntityData('Post');
      postData.addProperty('title', 'Test Post', 'string');

      const userData = new EntityData('User');
      userData.addProperty('id', 1, 'number');
      userData.addProperty('name', 'Test User', 'string');
      userData.setRelatedArray('posts', [postData]);

      const mockRepo = new MockRepository();
      mockRepo.shouldFail = true;

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

    it('handleBeforeRemove should do nothing without cascade relations', 0, async () => {
      setupUserEntity();
      const handler = CascadeHandler.getInstance();
      const entityData = new EntityData('User');
      entityData.addProperty('id', 1, 'number');
      entityData.addProperty('name', 'Test', 'string');

      const mockRepo = new MockRepository();
      let threw = false;
      try {
        await handler.handleBeforeRemove('User', entityData, mockRepo, () => mockRepo);
      } catch (e) {
        threw = true;
      }

      expect(threw).assertEqual(false);
      expect(mockRepo.removeCallCount).assertEqual(0);
    });

    it('handleBeforeRemove should process OneToMany relation with cascade', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupOneToManyRelation(true);
      const handler = CascadeHandler.getInstance();

      const postData = new EntityData('Post');
      postData.addProperty('id', 1, 'number');
      postData.addProperty('title', 'Test Post', 'string');

      const userData = new EntityData('User');
      userData.addProperty('id', 1, 'number');
      userData.addProperty('name', 'Test User', 'string');
      userData.setRelatedArray('posts', [postData]);

      const mockRepo = new MockRepository();
      let threw = false;
      try {
        await handler.handleBeforeRemove('User', userData, mockRepo, () => mockRepo);
      } catch (e) {
        threw = true;
      }

      expect(threw).assertEqual(false);
      expect(mockRepo.removeCallCount).assertEqual(1);
    });

    it('handleBeforeRemove should throw ExecutionError when cascade remove fails', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupOneToManyRelation(true);
      const handler = CascadeHandler.getInstance();

      const postData = new EntityData('Post');
      postData.addProperty('id', 1, 'number');
      postData.addProperty('title', 'Test Post', 'string');

      const userData = new EntityData('User');
      userData.addProperty('id', 1, 'number');
      userData.addProperty('name', 'Test User', 'string');
      userData.setRelatedArray('posts', [postData]);

      const mockRepo = new MockRepository();
      mockRepo.shouldFail = true;

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

    it('should handle OneToOne source side cascade', 0, async () => {
      setupUserEntity();
      setupProfileEntity();
      setupOneToOneRelationSource(true);
      const handler = CascadeHandler.getInstance();

      const userData = new EntityData('User');
      userData.addProperty('id', 1, 'number');
      userData.addProperty('name', 'Test User', 'string');

      const profileData = new EntityData('Profile');
      profileData.addProperty('bio', 'Test Bio', 'string');
      profileData.setRelatedSingle('user', userData);

      const mockRepo = new MockRepository();
      let threw = false;
      try {
        await handler.handleBeforeSave('Profile', profileData, 'insert', () => mockRepo);
      } catch (e) {
        threw = true;
      }

      expect(threw).assertEqual(false);
      expect(mockRepo.saveCallCount).assertEqual(1);
    });

    it('should handle OneToOne target side cascade', 0, async () => {
      setupUserEntity();
      setupProfileEntity();
      setupOneToOneRelationTarget(true);
      const handler = CascadeHandler.getInstance();

      const profileData = new EntityData('Profile');
      profileData.addProperty('bio', 'Test Bio', 'string');

      const userData = new EntityData('User');
      userData.addProperty('id', 1, 'number');
      userData.addProperty('name', 'Test User', 'string');
      userData.setRelatedSingle('profile', profileData);

      const mockRepo = new MockRepository();
      let threw = false;
      try {
        await handler.handleAfterSave('User', userData, 'insert', mockRepo, () => mockRepo);
      } catch (e) {
        threw = true;
      }

      expect(threw).assertEqual(false);
      expect(mockRepo.saveCallCount).assertEqual(1);
    });

    it('should skip relations without cascade enabled', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupOneToManyRelation(false);
      const handler = CascadeHandler.getInstance();

      const postData = new EntityData('Post');
      postData.addProperty('title', 'Test Post', 'string');

      const userData = new EntityData('User');
      userData.addProperty('id', 1, 'number');
      userData.addProperty('name', 'Test User', 'string');
      userData.setRelatedArray('posts', [postData]);

      const mockRepo = new MockRepository();
      let threw = false;
      try {
        await handler.handleAfterSave('User', userData, 'insert', mockRepo, () => mockRepo);
      } catch (e) {
        threw = true;
      }

      expect(threw).assertEqual(false);
      expect(mockRepo.saveCallCount).assertEqual(0);
    });

    it('should skip when no related data', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupOneToManyRelation(true);
      const handler = CascadeHandler.getInstance();

      const userData = new EntityData('User');
      userData.addProperty('id', 1, 'number');
      userData.addProperty('name', 'Test User', 'string');

      const mockRepo = new MockRepository();
      let threw = false;
      try {
        await handler.handleAfterSave('User', userData, 'insert', mockRepo, () => mockRepo);
      } catch (e) {
        threw = true;
      }

      expect(threw).assertEqual(false);
      expect(mockRepo.saveCallCount).assertEqual(0);
    });

    it('should handle empty related array', 0, async () => {
      setupUserEntity();
      setupPostEntity();
      setupOneToManyRelation(true);
      const handler = CascadeHandler.getInstance();

      const userData = new EntityData('User');
      userData.addProperty('id', 1, 'number');
      userData.addProperty('name', 'Test User', 'string');
      userData.setRelatedArray('posts', []);

      const mockRepo = new MockRepository();
      let threw = false;
      try {
        await handler.handleAfterSave('User', userData, 'insert', mockRepo, () => mockRepo);
      } catch (e) {
        threw = true;
      }

      expect(threw).assertEqual(false);
      expect(mockRepo.saveCallCount).assertEqual(0);
    });
  });
}
