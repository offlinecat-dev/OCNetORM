import { describe, it, expect } from '@ohos/hypium';
import { EntityData, RelatedDataValue } from '../../main/ets/mapping/DataMapper';

export default function entityDataTest() {
  describe('entityDataTest', () => {
    it('addProperty/getProperty/getPropertyValue should store values', 0, () => {
      const data = new EntityData('User');
      data.addProperty('name', 'Alice', 'string');

      const prop = data.getProperty('name');
      expect(prop !== null).assertEqual(true);
      if (prop) {
        expect(prop.propertyName).assertEqual('name');
        expect(prop.value).assertEqual('Alice');
        expect(prop.propertyType).assertEqual('string');
      }

      expect(data.getPropertyValue('name')).assertEqual('Alice');
      expect(data.getPropertyValue('missing') === null).assertEqual(true);
    });

    it('setPropertyValue should sync propertyMap and properties', 0, () => {
      const data = new EntityData('User');
      data.addProperty('age', 20, 'number');
      data.setPropertyValue('age', 21);

      const prop = data.getProperty('age');
      expect(prop !== null).assertEqual(true);
      if (prop) {
        expect(prop.value).assertEqual(21);
      }
      expect(data.getPropertyValue('age')).assertEqual(21);

      data.setPropertyValue('nickname', 'Bob');
      expect(data.getProperty('nickname') === null).assertEqual(true);
      expect(data.getPropertyValue('nickname')).assertEqual('Bob');
    });

    it('transient data set/get/remove/keys should work', 0, () => {
      const data = new EntityData('User');
      data.setTransient('token', 'abc');
      data.setTransient('count', 2);

      expect(data.getTransient('token')).assertEqual('abc');
      expect(data.hasTransient('token')).assertEqual(true);

      const keys = data.getTransientKeys();
      expect(keys.length).assertEqual(2);
      expect(keys.includes('token')).assertEqual(true);
      expect(keys.includes('count')).assertEqual(true);

      data.removeTransient('token');
      expect(data.getTransient('token') === null).assertEqual(true);
      expect(data.hasTransient('token')).assertEqual(false);
      expect(data.getTransientKeys().length).assertEqual(1);
    });

    it('related data set/get/remove/isArray should work', 0, () => {
      const data = new EntityData('User');
      const post1 = new EntityData('Post');
      const post2 = new EntityData('Post');
      const profile = new EntityData('Profile');

      data.setRelatedArray('posts', [post1, post2]);
      data.setRelatedSingle('profile', profile);

      expect(data.hasRelated('posts')).assertEqual(true);
      expect(data.hasRelated('profile')).assertEqual(true);
      expect(data.isRelatedArray('posts')).assertEqual(true);
      expect(data.isRelatedArray('profile')).assertEqual(false);

      const posts = data.getRelatedArray('posts');
      expect(posts.length).assertEqual(2);
      expect(data.getRelatedSingle('profile') === profile).assertEqual(true);
      expect(data.getRelatedSingle('posts') === null).assertEqual(true);

      const names = data.getRelatedPropertyNames();
      expect(names.includes('posts')).assertEqual(true);
      expect(names.includes('profile')).assertEqual(true);

      data.removeRelated('posts');
      expect(data.hasRelated('posts')).assertEqual(false);
      expect(data.getRelatedArray('posts').length).assertEqual(0);
    });

    it('lazy relation loaders should load and cache values', 0, async () => {
      const data = new EntityData('User');
      const profile = new EntityData('Profile');
      const post = new EntityData('Post');
      let loadCount = 0;

      data.setLazyRelation('profile', async () => {
        loadCount++;
        return RelatedDataValue.fromSingle(profile);
      });

      expect(data.hasLazyRelation('profile')).assertEqual(true);

      const loadedProfile = await data.loadRelatedSingle('profile');
      expect(loadedProfile === profile).assertEqual(true);
      expect(loadCount).assertEqual(1);
      expect(data.hasLazyRelation('profile')).assertEqual(false);
      expect(data.hasRelated('profile')).assertEqual(true);

      const cachedProfile = await data.loadRelatedSingle('profile');
      expect(cachedProfile === profile).assertEqual(true);
      expect(loadCount).assertEqual(1);

      data.setLazyRelation('posts', async () => {
        loadCount++;
        return RelatedDataValue.fromArray([post]);
      });

      const posts = await data.loadRelatedArray('posts');
      expect(posts.length).assertEqual(1);
      expect(posts[0] === post).assertEqual(true);
      expect(data.hasLazyRelation('posts')).assertEqual(false);
    });
  });
}
