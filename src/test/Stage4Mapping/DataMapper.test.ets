import { describe, beforeEach, it, expect } from '@ohos/hypium';
import { MetadataStorage } from '../../main/ets/core/MetadataStorage';
import { ColumnMetadata } from '../../main/ets/core/ColumnMetadata';
import { ColumnType } from '../../main/ets/types/ColumnType';
import { DataMapper, EntityData, ResultSetRow } from '../../main/ets/mapping/DataMapper';
import { EntityMappingError, NullValueError } from '../../main/ets/errors/MappingError';

const setupUserMetadata = (): void => {
  const storage = MetadataStorage.getInstance();
  storage.registerEntity('User');

  const idColumn = new ColumnMetadata('id', 'id')
    .setType(ColumnType.INTEGER)
    .setPrimaryKey(true)
    .setAutoIncrement(true)
    .setNullable(false);
  storage.registerColumn('User', idColumn);

  const nameColumn = new ColumnMetadata('name', 'name')
    .setType(ColumnType.TEXT)
    .setNullable(false);
  storage.registerColumn('User', nameColumn);

  const statusColumn = new ColumnMetadata('status', 'status')
    .setType(ColumnType.TEXT)
    .setNullable(false)
    .setDefaultValue('active');
  storage.registerColumn('User', statusColumn);

  const ageColumn = new ColumnMetadata('age', 'age')
    .setType(ColumnType.INTEGER)
    .setNullable(true);
  storage.registerColumn('User', ageColumn);
};

const setupNoKeyMetadata = (): void => {
  const storage = MetadataStorage.getInstance();
  storage.registerEntity('NoKey');
  const nameColumn = new ColumnMetadata('name', 'name').setType(ColumnType.TEXT);
  storage.registerColumn('NoKey', nameColumn);
};

export default function dataMapperTest() {
  describe('dataMapperTest', () => {
    beforeEach(() => {
      MetadataStorage.resetInstance();
    });

    it('toValuesBucket should skip auto increment by default and include when requested', 0, () => {
      setupUserMetadata();
      const mapper = new DataMapper('User');
      const data = new EntityData('User');
      data.addProperty('id', 5, 'number');
      data.addProperty('name', 'Alice', 'string');

      const bucket = mapper.toValuesBucket(data);
      expect(bucket.has('id')).assertEqual(false);
      expect(bucket.get('name')).assertEqual('Alice');
      expect(bucket.get('status')).assertEqual('active');

      const bucketWithId = mapper.toValuesBucket(data, true);
      expect(bucketWithId.has('id')).assertEqual(true);
      expect(bucketWithId.get('id')).assertEqual(5);
    });

    it('toValuesBucket should use propertyMap when properties missing', 0, () => {
      setupUserMetadata();
      const mapper = new DataMapper('User');
      const data = new EntityData('User');
      data.setPropertyValue('name', 'MapName');

      const bucket = mapper.toValuesBucket(data);
      expect(data.getProperty('name') === null).assertEqual(true);
      expect(bucket.get('name')).assertEqual('MapName');
    });

    it('toValuesBucket should throw NullValueError for missing non-nullable values', 0, () => {
      setupUserMetadata();
      const mapper = new DataMapper('User');
      const data = new EntityData('User');

      let threw = false;
      try {
        mapper.toValuesBucket(data);
      } catch (error) {
        threw = error instanceof NullValueError;
      }

      expect(threw).assertEqual(true);
    });

    it('fromResultSetRow should convert types and apply defaults', 0, () => {
      setupUserMetadata();
      const mapper = new DataMapper('User');
      const row = new ResultSetRow();
      row.set('id', 7);
      row.set('name', 123);
      row.set('age', '42');

      const data = mapper.fromResultSetRow(row);
      const nameProp = data.getProperty('name');
      const ageProp = data.getProperty('age');
      const statusProp = data.getProperty('status');

      expect(nameProp !== null).assertEqual(true);
      if (nameProp) {
        expect(nameProp.value).assertEqual('123');
      }

      expect(ageProp !== null).assertEqual(true);
      if (ageProp) {
        expect(ageProp.value).assertEqual(42);
      }

      expect(statusProp !== null).assertEqual(true);
      if (statusProp) {
        expect(statusProp.value).assertEqual('active');
      }
    });

    it('getPrimaryKeyValue/setPrimaryKeyValue/isNewRecord should work', 0, () => {
      setupUserMetadata();
      const mapper = new DataMapper('User');

      const data = new EntityData('User');
      data.addProperty('id', 0, 'number');
      expect(mapper.getPrimaryKeyValue(data)).assertEqual(0);
      expect(mapper.isNewRecord(data)).assertEqual(true);

      mapper.setPrimaryKeyValue(data, 9);
      expect(mapper.getPrimaryKeyValue(data)).assertEqual(9);
      expect(data.getPropertyValue('id')).assertEqual(9);
      expect(mapper.isNewRecord(data)).assertEqual(false);

      const mapOnly = new EntityData('User');
      mapOnly.setPropertyValue('id', 3);
      expect(mapper.getPrimaryKeyValue(mapOnly)).assertEqual(3);

      const noId = new EntityData('User');
      expect(mapper.isNewRecord(noId)).assertEqual(true);
    });

    it('setPrimaryKeyValue should throw when entity has no primary key', 0, () => {
      setupNoKeyMetadata();
      const mapper = new DataMapper('NoKey');
      const data = new EntityData('NoKey');

      let threw = false;
      try {
        mapper.setPrimaryKeyValue(data, 1);
      } catch (error) {
        threw = error instanceof EntityMappingError;
      }

      expect(threw).assertEqual(true);
    });
  });
}
