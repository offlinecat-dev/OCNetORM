import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { MetadataStorage } from '../../main/ets/core/MetadataStorage';
import { ColumnMetadata } from '../../main/ets/core/ColumnMetadata';
import { defineEntity } from '../../main/ets/core/EntitySchema';
import { RelationMetadata } from '../../main/ets/core/RelationMetadata';
import { ManyToManyMetadata } from '../../main/ets/core/ManyToManyMetadata';
import { MorphToMetadata } from '../../main/ets/core/MorphToMetadata';
import { RelationType } from '../../main/ets/types/RelationType';
import { ColumnType } from '../../main/ets/types/ColumnType';
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

      it('registerMorphTo should keep morph metadata', 0, () => {
        const storage = createStorage();
        storage.registerEntity('Comment');
        storage.registerEntity('Post');
        storage.registerEntity('User');

        storage.registerMorphTo('Comment', 'commentable', 'commentableId', 'commentableType', {
          post: 'Post',
          user: 'User'
        });

        const relation = storage.getMorphToRelation('Comment', 'commentable');
        expect(relation !== null).assertEqual(true);
        if (relation) {
          expect(relation.type).assertEqual(RelationType.MORPH_TO);
          expect(relation.idColumn).assertEqual('commentableId');
          expect(relation.typeColumn).assertEqual('commentableType');
          expect(relation.resolveTargetEntity('post')).assertEqual('Post');
          expect(relation instanceof MorphToMetadata).assertEqual(true);
        }
      });

      it('defineEntity should register morphTo metadata', 0, () => {
        const storage = createStorage();
        defineEntity('Post', {
          tableName: 'posts',
          columns: [{ property: 'id', type: ColumnType.INTEGER, primaryKey: true }]
        });
        defineEntity('Comment', {
          tableName: 'comments',
          columns: [
            { property: 'id', type: ColumnType.INTEGER, primaryKey: true },
            { property: 'commentableId', type: ColumnType.INTEGER },
            { property: 'commentableType', type: ColumnType.TEXT }
          ],
          morphTo: {
            name: 'commentable',
            idColumn: 'commentableId',
            typeColumn: 'commentableType',
            typeMap: { post: 'Post' }
          }
        });
        const relation = storage.getMorphToRelation('Comment', 'commentable');
        expect(relation !== null).assertEqual(true);
        if (relation) {
          expect(relation.idColumn).assertEqual('commentableId');
          expect(relation.typeColumn).assertEqual('commentableType');
        }
      });

      it('defineEntity should register index metadata', 0, () => {
        const storage = createStorage();
        const metadata = defineEntity('UserIndex', {
          tableName: 'users_index',
          columns: [
            { property: 'id', type: ColumnType.INTEGER, primaryKey: true },
            { property: 'email', type: ColumnType.TEXT },
            { property: 'status', name: 'user_status', type: ColumnType.TEXT }
          ],
          indexes: [
            { columns: ['email'], unique: true },
            { name: 'idx_user_status', columns: ['user_status'] }
          ]
        });
        expect(storage.getEntityMetadata('UserIndex') !== null).assertEqual(true);
        const indexes = metadata.getIndexes();
        expect(indexes.length).assertEqual(2);
        expect(indexes[0].unique).assertEqual(true);
        expect(indexes[0].columns[0]).assertEqual('email');
        expect(indexes[1].name).assertEqual('idx_user_status');
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
