import { describe, beforeEach, it, expect } from '@ohos/hypium';
import { relationalStore } from '@kit.ArkData';
import { MetadataStorage } from '../../main/ets/core/MetadataStorage';
import { ColumnMetadata } from '../../main/ets/core/ColumnMetadata';
import { ColumnType } from '../../main/ets/types/ColumnType';
import { QueryBuilder } from '../../main/ets/query/QueryBuilder';
import { SubQuery } from '../../main/ets/query/SubQuery';
import { SubQueryExecutor } from '../../main/ets/query/SubQueryExecutor';
import { SubQueryRelationExecutor } from '../../main/ets/query/SubQueryRelationExecutor';
import { Logger } from '../../main/ets/logging/Logger';
import { ValueType } from '../../main/ets/types/ValueTypes';

class FakeRuntimeResultSet {
  rowCount: number;
  columnNames: Array<string>;
  private rows: Array<Record<string, ValueType>>;
  private index: number = -1;

  constructor(columns: Array<string>, rows: Array<Record<string, ValueType>>) {
    this.columnNames = columns;
    this.rows = rows;
    this.rowCount = rows.length;
  }

  goToNextRow(): boolean {
    this.index++;
    return this.index < this.rows.length;
  }

  getColumnIndex(name: string): number {
    return this.columnNames.indexOf(name);
  }

  isColumnNull(columnIndex: number): boolean {
    const value = this.rows[this.index][this.columnNames[columnIndex]];
    return value === null || value === undefined;
  }

  getColumnTypeSync(columnIndex: number): relationalStore.ColumnType {
    const value = this.rows[this.index][this.columnNames[columnIndex]];
    if (value === null || value === undefined) {
      return relationalStore.ColumnType.NULL;
    }
    if (typeof value === 'number') {
      return relationalStore.ColumnType.INTEGER;
    }
    if (value instanceof Uint8Array) {
      return relationalStore.ColumnType.BLOB;
    }
    return relationalStore.ColumnType.TEXT;
  }

  getLong(columnIndex: number): number {
    return Number(this.rows[this.index][this.columnNames[columnIndex]]);
  }

  getDouble(columnIndex: number): number {
    return Number(this.rows[this.index][this.columnNames[columnIndex]]);
  }

  getString(columnIndex: number): string {
    return String(this.rows[this.index][this.columnNames[columnIndex]]);
  }

  getBlob(_columnIndex: number): Uint8Array {
    return new Uint8Array();
  }

  close(): void {
  }
}

const setupUserMetadata = (): void => {
  const storage = MetadataStorage.getInstance();
  storage.registerEntity('User', 'users');
  storage.registerColumn('User', new ColumnMetadata('id', 'id').setType(ColumnType.TEXT).setPrimaryKey(true));
};

const setupManyToManyMetadata = (): void => {
  const storage = MetadataStorage.getInstance();
  setupUserMetadata();
  storage.registerEntity('Role', 'roles');
  storage.registerColumn('Role', new ColumnMetadata('id', 'role_id').setType(ColumnType.TEXT).setPrimaryKey(true));
  storage.registerManyToMany('User', 'Role', 'roles', 'user_role', 'user_id', 'role_id');
};

export default function subQueryExecutorFixTest() {
  describe('subQueryExecutorFixTest', () => {
    beforeEach(() => {
      MetadataStorage.resetInstance();
    });

    it('SubQueryExecutor should preserve leading-zero string ids', 0, async () => {
      setupUserMetadata();
      const fakeBuilder = {
        getSubQueries: () => [new SubQuery('s1'), new SubQuery('s2')],
        getEntityName: () => 'User'
      } as unknown as QueryBuilder;

      const executor = new SubQueryExecutor({
        queryBuilder: fakeBuilder,
        logger: Logger.getInstance(),
        getStore: () => ({}) as relationalStore.RdbStore,
        executeOneSubQuery: async (subQuery: SubQuery) => {
          if (subQuery.getRelationName() === 's1') {
            return ['00123', 7];
          }
          return ['00123', '7'];
        }
      });

      const ids = await executor.executeSubQueries();
      expect(ids.length).assertEqual(1);
      expect(ids[0]).assertEqual('00123');
    });

    it('SubQueryRelationExecutor should keep string ids in many-to-many', 0, async () => {
      setupManyToManyMetadata();
      let queryCount = 0;
      const fakeStore = {
        query: async () => {
          queryCount++;
          if (queryCount === 1) {
            return new FakeRuntimeResultSet(['role_id'], [{ role_id: '0001' }]);
          }
          return new FakeRuntimeResultSet(['user_id'], [{ user_id: '00123' }]);
        }
      } as unknown as relationalStore.RdbStore;

      const relationExecutor = new SubQueryRelationExecutor({
        logger: Logger.getInstance(),
        withQueryTimeout: async (task: Promise<relationalStore.ResultSet>) => await task,
        closeResultSet: (resultSet: relationalStore.ResultSet | null) => {
          if (resultSet !== null) {
            resultSet.close();
          }
        },
        toRdbValue: (value: ValueType | Array<ValueType> | null) => value as relationalStore.ValueType
      });

      const result = await relationExecutor.executeOneSubQuery(new SubQuery('roles'), fakeStore, 'User', 'id');
      expect(result.length).assertEqual(1);
      expect(result[0]).assertEqual('00123');
    });
  });
}
