import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { EntityMetadata } from '../../main/ets/core/EntityMetadata';
import { ColumnMetadata } from '../../main/ets/core/ColumnMetadata';
import { EntityHooks } from '../../main/ets/types/EntityHooks';

class EntityMetadataBundle {
  metadata: EntityMetadata;
  idColumn: ColumnMetadata;
  nameColumn: ColumnMetadata;

  constructor(metadata: EntityMetadata, idColumn: ColumnMetadata, nameColumn: ColumnMetadata) {
    this.metadata = metadata;
    this.idColumn = idColumn;
    this.nameColumn = nameColumn;
  }
}

const createEntityMetadata = (): EntityMetadataBundle => {
  const metadata = new EntityMetadata('User', 'users');
  const idColumn = new ColumnMetadata('id', 'id');
  idColumn.setPrimaryKey(true);
  const nameColumn = new ColumnMetadata('name', 'user_name');
  metadata.addColumn(idColumn);
  metadata.addColumn(nameColumn);
  return new EntityMetadataBundle(metadata, idColumn, nameColumn);
};

export default function entityMetadataTest() {
  describe('entityMetadataTest', () => {
    beforeAll(() => {
    });
    beforeEach(() => {
    });
    afterEach(() => {
    });
    afterAll(() => {
    });

    it('getColumnByProperty/getColumnByName should map correctly', 0, () => {
      const bundle = createEntityMetadata();
      const metadata = bundle.metadata;
      const nameColumn = bundle.nameColumn;
      expect(metadata.getColumnByProperty('name') === nameColumn).assertEqual(true);
      expect(metadata.getColumnByName('user_name') === nameColumn).assertEqual(true);
    });

    it('getPrimaryKeyColumn/hasPrimaryKey should detect primary key', 0, () => {
      const bundle = createEntityMetadata();
      const metadata = bundle.metadata;
      const idColumn = bundle.idColumn;
      expect(metadata.hasPrimaryKey()).assertEqual(true);
      expect(metadata.getPrimaryKeyColumn() === idColumn).assertEqual(true);
    });

    it('getNonPrimaryKeyColumns should exclude primary key', 0, () => {
      const bundle = createEntityMetadata();
      const metadata = bundle.metadata;
      const nameColumn = bundle.nameColumn;
      const nonPrimary = metadata.getNonPrimaryKeyColumns();
      expect(nonPrimary.length).assertEqual(1);
      expect(nonPrimary[0] === nameColumn).assertEqual(true);
    });

    it('softDelete flag and deletedAtColumn should update', 0, () => {
      const metadata = new EntityMetadata('User');
      expect(metadata.isSoftDeleteEnabled()).assertEqual(false);
      expect(metadata.getDeletedAtColumn()).assertEqual('deleted_at');

      metadata.setSoftDelete(true, 'deleted_time');
      expect(metadata.isSoftDeleteEnabled()).assertEqual(true);
      expect(metadata.getDeletedAtColumn()).assertEqual('deleted_time');
    });

    it('hooks set/get/has should behave correctly', 0, () => {
      const metadata = new EntityMetadata('User');
      const hooks = new EntityHooks();
      metadata.setHooks(hooks);
      expect(metadata.getHooks() === hooks).assertEqual(true);
      expect(metadata.hasHooks()).assertEqual(true);

      metadata.setHooks(null);
      expect(metadata.getHooks() === null).assertEqual(true);
      expect(metadata.hasHooks()).assertEqual(false);
    });
  });
}
