import { describe, it, expect } from '@ohos/hypium';
import { EntityData } from '../../main/ets/mapping/DataMapper';
import { TypedEntityData } from '../../main/ets/mapping/TypedEntityData';

interface UserSchema {
  id: number;
  name: string;
  age: number;
  active: boolean;
}

export default function typedEntityDataTest() {
  describe('typedEntityDataTest', () => {
    it('get/set typed values should work', 0, () => {
      const data = new TypedEntityData<UserSchema>('User');
      data.setString('name', 'Alice');
      data.setNumber('age', 21);
      data.setBoolean('active', true);
      data.setValue('score', 95.5);

      expect(data.getString('name')).assertEqual('Alice');
      expect(data.getNumber('age')).assertEqual(21);
      expect(data.getBoolean('active')).assertEqual(true);
      expect(data.getValue('score')).assertEqual(95.5);
      expect(data.getNumber('name') === null).assertEqual(true);
      expect(data.getString('age')).assertEqual('21');
      expect(data.hasValue('score')).assertEqual(true);

      const names = data.getPropertyNames();
      expect(names.includes('name')).assertEqual(true);
      expect(names.includes('age')).assertEqual(true);
    });

    it('related data set/get/has should work', 0, () => {
      const data = new TypedEntityData<UserSchema>('User');
      const post = new EntityData('Post');
      const profile = new EntityData('Profile');

      data.setRelatedArray('posts', [post]);
      data.setRelatedSingle('profile', profile);

      expect(data.hasRelated('posts')).assertEqual(true);
      expect(data.hasRelated('profile')).assertEqual(true);

      const posts = data.getRelatedArray('posts');
      expect(posts.length).assertEqual(1);
      expect(posts[0] === post).assertEqual(true);

      const loadedProfile = data.getRelatedSingle('profile');
      expect(loadedProfile === profile).assertEqual(true);
      expect(data.getRelatedSingle('posts') === null).assertEqual(true);
    });

    it('fromEntityData/toEntityData should keep values and related data', 0, () => {
      const entity = new EntityData('User');
      entity.addProperty('id', 5, 'number');
      entity.addProperty('name', 'Zoe', 'string');
      const profile = new EntityData('Profile');
      entity.setRelatedSingle('profile', profile);

      const typed = TypedEntityData.fromEntityData<UserSchema>(entity);
      expect(typed.entityName).assertEqual('User');
      expect(typed.getNumber('id')).assertEqual(5);
      expect(typed.getString('name')).assertEqual('Zoe');
      expect(typed.getRelatedSingle('profile') === profile).assertEqual(true);

      const post = new EntityData('Post');
      typed.setNumber('age', 30);
      typed.setBoolean('active', false);
      typed.setRelatedArray('posts', [post]);

      const converted = typed.toEntityData();
      expect(converted.entityName).assertEqual('User');
      expect(converted.getPropertyValue('id')).assertEqual(5);
      expect(converted.getPropertyValue('name')).assertEqual('Zoe');
      expect(converted.getPropertyValue('age')).assertEqual(30);
      expect(converted.getPropertyValue('active')).assertEqual(false);
      expect(converted.getRelatedArray('posts')[0] === post).assertEqual(true);

      const activeProp = converted.getProperty('active');
      expect(activeProp !== null).assertEqual(true);
      if (activeProp) {
        expect(activeProp.propertyType).assertEqual('boolean');
      }
    });

    it('clear and getPropertyCount should reset data', 0, () => {
      const data = new TypedEntityData<UserSchema>('User');
      data.setString('name', 'Bob');
      data.setNumber('age', 40);
      data.setRelatedSingle('profile', new EntityData('Profile'));
      expect(data.getPropertyCount()).assertEqual(2);

      data.clear();
      expect(data.getPropertyCount()).assertEqual(0);
      expect(data.getPropertyNames().length).assertEqual(0);
      expect(data.hasRelated('profile')).assertEqual(false);
    });
  });
}
