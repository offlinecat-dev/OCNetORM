import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { MetadataStorage } from '../../main/ets/core/MetadataStorage';
import { ColumnMetadata } from '../../main/ets/core/ColumnMetadata';
import { RelationMetadata } from '../../main/ets/core/RelationMetadata';
import { ManyToManyMetadata } from '../../main/ets/core/ManyToManyMetadata';
import { RelationType } from '../../main/ets/types/RelationType';
import { DuplicateEntityError, EntityNotRegisteredError } from '../../main/ets/errors/MetadataError';

const createStorage = (): MetadataStorage => {
  MetadataStorage.resetInstance();
  return MetadataStorage.getInstance();
};

export default function localUnitTest() {
  describe('localUnitTest', () => {
    beforeAll(() => {
    });
    beforeEach(() => {
    });
    afterEach(() => {
    });
    afterAll(() => {
    });

    describe('MetadataStorage', () => {
      it('registerEntity should set table name and allow custom name', 0, () => {
        const storage = createStorage();
        storage.registerEntity('User');
        const userMetadata = storage.getEntityMetadata('User');
        expect(userMetadata !== null).assertEqual(true);
        if (userMetadata) {
          expect(userMetadata.tableName).assertEqual('User');
        }

        storage.registerEntity('Post', 'posts');
        const postMetadata = storage.getEntityMetadata('Post');
        expect(postMetadata !== null).assertEqual(true);
        if (postMetadata) {
          expect(postMetadata.tableName).assertEqual('posts');
        }
      });

      it('registerEntity should throw on duplicate', 0, () => {
        const storage = createStorage();
        storage.registerEntity('User');
        let isDuplicate = false;
        try {
          storage.registerEntity('User');
        } catch (error) {
          isDuplicate = error instanceof DuplicateEntityError;
        }
        expect(isDuplicate).assertEqual(true);
      });

      it('registerColumn should throw if entity not registered', 0, () => {
        const storage = createStorage();
        const column = new ColumnMetadata('name', 'user_name');
        let isNotRegistered = false;
        try {
          storage.registerColumn('User', column);
        } catch (error) {
          isNotRegistered = error instanceof EntityNotRegisteredError;
        }
        expect(isNotRegistered).assertEqual(true);
      });

      it('registerColumn should map property and column names', 0, () => {
        const storage = createStorage();
        storage.registerEntity('User');
        const column = new ColumnMetadata('name', 'user_name');
        storage.registerColumn('User', column);
        const metadata = storage.getEntityMetadata('User');
        expect(metadata !== null).assertEqual(true);
        if (metadata) {
          expect(metadata.getColumnByProperty('name') === column).assertEqual(true);
          expect(metadata.getColumnByName('user_name') === column).assertEqual(true);
        }
      });

      it('getEntityMetadata should return null for missing entity', 0, () => {
        const storage = createStorage();
        expect(storage.getEntityMetadata('Missing') === null).assertEqual(true);
      });

      it('getAllEntities should match entity count', 0, () => {
        const storage = createStorage();
        storage.registerEntity('User');
        storage.registerEntity('Post');
        const allEntities = storage.getAllEntities();
        expect(allEntities.length).assertEqual(2);
        expect(storage.getEntityCount()).assertEqual(allEntities.length);
      });

      it('registerInstanceMapping should resolve metadata by instance id', 0, () => {
        const storage = createStorage();
        storage.registerEntity('User');
        storage.registerInstanceMapping('instance-1', 'User');
        const metadata = storage.getMetadataByInstanceId('instance-1');
        expect(metadata !== null).assertEqual(true);
        if (metadata) {
          expect(metadata.entityName).assertEqual('User');
        }
        expect(storage.getMetadataByInstanceId('missing') === null).assertEqual(true);
      });

      it('registerRelation should support single and multiple relations', 0, () => {
        const storage = createStorage();
        storage.registerEntity('User');
        storage.registerEntity('Post');
        storage.registerEntity('Profile');

        const postsRelation = new RelationMetadata(RelationType.ONE_TO_MANY, 'User', 'Post', 'posts', 'user_id');
        const profileRelation = new RelationMetadata(RelationType.ONE_TO_ONE, 'User', 'Profile', 'profile', 'user_id');

        storage.registerRelation('User', postsRelation);
        storage.registerRelation('User', profileRelation);

        expect(storage.getRelation('User', 'posts') === postsRelation).assertEqual(true);
        expect(storage.hasRelation('User', 'profile')).assertEqual(true);
        expect(storage.getRelation('User', 'missing') === null).assertEqual(true);
        expect(storage.getRelations('User').length).assertEqual(2);
      });

      it('registerManyToMany should keep join table metadata', 0, () => {
        const storage = createStorage();
        storage.registerEntity('User');
        storage.registerEntity('Tag');

        storage.registerManyToMany('User', 'Tag', 'tags', 'user_tags', 'user_id', 'tag_id');
        const relation = storage.getManyToManyRelation('User', 'tags');
        expect(relation !== null).assertEqual(true);
        if (relation) {
          expect(relation.joinTable).assertEqual('user_tags');
          expect(relation.joinSourceKey).assertEqual('user_id');
          expect(relation.joinTargetKey).assertEqual('tag_id');
          expect(relation.type).assertEqual(RelationType.MANY_TO_MANY);
          expect(relation instanceof ManyToManyMetadata).assertEqual(true);
        }
      });

      it('clear and resetInstance should remove all metadata', 0, () => {
        const storage = createStorage();
        storage.registerEntity('User');
        storage.registerEntity('Post');
        storage.registerInstanceMapping('instance-1', 'User');
        const relation = new RelationMetadata(RelationType.ONE_TO_MANY, 'User', 'Post', 'posts', 'user_id');
        storage.registerRelation('User', relation);

        storage.clear();
        expect(storage.getEntityCount()).assertEqual(0);
        expect(storage.getAllEntities().length).assertEqual(0);
        expect(storage.getMetadataByInstanceId('instance-1') === null).assertEqual(true);
        expect(storage.getRelations('User').length).assertEqual(0);

        MetadataStorage.resetInstance();
        const freshStorage = MetadataStorage.getInstance();
        expect(freshStorage.getEntityCount()).assertEqual(0);
      });
    });

  });
}