import { describe, it, expect } from '@ohos/hypium';
import { relationalStore } from '@kit.ArkData';
import { ResultSetUtils } from '../../main/ets/mapping/ResultSetUtils';
import { ColumnType } from '../../main/ets/types/ColumnType';
import { EntityMetadata } from '../../main/ets/core/EntityMetadata';
import { ColumnMetadata } from '../../main/ets/core/ColumnMetadata';
import { DbValueType } from '../../main/ets/types/ValueTypes';
import sendableRelationalStore from '@ohos.data.sendableRelationalStore';
import collections from '@arkts.collections';

class RowData {
  private values: Map<string, DbValueType> = new Map();

  set(key: string, value: DbValueType): RowData {
    this.values.set(key, value);
    return this;
  }

  get(key: string): DbValueType {
    const value = this.values.get(key);
    return value === undefined ? null : value;
  }

  toRecord(): Record<string, DbValueType> {
    const record = new Object() as Record<string, DbValueType>;
    this.values.forEach((value, key) => {
      record[key] = value;
    });
    return record;
  }
}

const expectBlobEqual = (actual: DbValueType, expected: Uint8Array): void => {
  expect(actual instanceof Uint8Array).assertEqual(true);
  if (!(actual instanceof Uint8Array)) {
    return;
  }
  expect(actual.length).assertEqual(expected.length);
  for (let i = 0; i < expected.length; i += 1) {
    expect(actual[i]).assertEqual(expected[i]);
  }
};

class FakeResultSet implements relationalStore.ResultSet {
  columnNames: Array<string>;
  private rows: Array<RowData>;
  rowIndex: number = -1;
  private columnTypes: Map<string, relationalStore.ColumnType> = new Map();
  private throwOnColumnIndex: Set<string> = new Set();
  private throwOnNextRow: boolean = false;
  private throwOnGet: Set<string> = new Set();
  closeCount: number = 0;
  throwOnClose: boolean = false;
  isClosed: boolean = false;

  constructor(columnNames: Array<string>, rows: Array<RowData>) {
    this.columnNames = columnNames;
    this.rows = rows;
  }

  setRowIndex(index: number): void {
    this.rowIndex = index;
  }

  setColumnType(name: string, type: relationalStore.ColumnType): void {
    this.columnTypes.set(name, type);
  }

  setThrowOnColumnIndex(name: string): void {
    this.throwOnColumnIndex.add(name);
  }

  setThrowOnNextRow(value: boolean): void {
    this.throwOnNextRow = value;
  }

  setThrowOnGet(method: string): void {
    this.throwOnGet.add(method);
  }

  getColumnIndex(columnName: string): number {
    if (this.throwOnColumnIndex.has(columnName)) {
      throw new Error('bad column');
    }
    const index = this.columnNames.indexOf(columnName);
    if (index < 0) {
      throw new Error('missing column');
    }
    return index;
  }

  getColumnName(columnIndex: number): string {
    const name = this.columnNames[columnIndex];
    return name === undefined ? '' : name;
  }

  isColumnNull(index: number): boolean {
    const value = this.getDbValue(index);
    return value === null || value === undefined;
  }

  getString(index: number): string {
    if (this.throwOnGet.has('string')) {
      throw new Error('string error');
    }
    const value = this.getValue(index);
    if (value === null || value === undefined) {
      return '';
    }
    return String(value);
  }

  getLong(index: number): number {
    if (this.throwOnGet.has('long')) {
      throw new Error('long error');
    }
    const value = this.getValue(index);
    return Number(value);
  }

  getDouble(index: number): number {
    if (this.throwOnGet.has('double')) {
      throw new Error('double error');
    }
    const value = this.getValue(index);
    return Number(value);
  }

  getBlob(index: number): Uint8Array {
    if (this.throwOnGet.has('blob')) {
      throw new Error('blob error');
    }
    const value = this.getDbValue(index);
    return value as Uint8Array;
  }

  getAsset(columnIndex: number): relationalStore.Asset {
    return this.getValue(columnIndex) as relationalStore.Asset;
  }

  getAssets(columnIndex: number): relationalStore.Assets {
    return this.getValue(columnIndex) as relationalStore.Assets;
  }

  getValue(columnIndex: number): relationalStore.ValueType {
    return this.getDbValue(columnIndex) as relationalStore.ValueType;
  }

  getRow(): relationalStore.ValuesBucket {
    const record = this.getRowRecord();
    return record as relationalStore.ValuesBucket;
  }

  getRows(maxCount: number, position?: number): Promise<Array<relationalStore.ValuesBucket>> {
    const start = position ?? 0;
    const results: Array<relationalStore.ValuesBucket> = [];
    for (let i = start; i < this.rows.length && results.length < maxCount; i += 1) {
      const record = this.rows[i].toRecord() as relationalStore.ValuesBucket;
      results.push(record);
    }
    return Promise.resolve(results);
  }

  getSendableRow(): sendableRelationalStore.ValuesBucket {
    try {
      const row = this.getRow();
      return sendableRelationalStore.toSendableValuesBucket(row);
    } catch (e) {
      return new collections.Map<string, sendableRelationalStore.ValueType>();
    }
  }

  getColumnType(columnIdentifier: number | string): Promise<relationalStore.ColumnType> {
    return Promise.resolve(this.getColumnTypeSync(columnIdentifier));
  }

  getColumnTypeSync(columnIdentifier: number | string): relationalStore.ColumnType {
    const index = typeof columnIdentifier === 'number'
      ? columnIdentifier
      : this.getColumnIndex(columnIdentifier);
    const name = this.columnNames[index];
    const value = this.columnTypes.get(name);
    if (value !== undefined) {
      return value;
    }
    const currentValue = this.getDbValue(index);
    if (currentValue === null || currentValue === undefined) {
      return 0 as relationalStore.ColumnType;
    }
    if (currentValue instanceof Uint8Array) {
      return 4 as relationalStore.ColumnType;
    }
    if (typeof currentValue === 'number') {
      return Number.isInteger(currentValue)
        ? (1 as relationalStore.ColumnType)
        : (2 as relationalStore.ColumnType);
    }
    return 3 as relationalStore.ColumnType;
  }

  get columnCount(): number {
    return this.columnNames.length;
  }

  get rowCount(): number {
    return this.rows.length;
  }

  get isAtFirstRow(): boolean {
    return this.rowIndex === 0 && this.rows.length > 0;
  }

  get isAtLastRow(): boolean {
    return this.rowIndex === this.rows.length - 1 && this.rows.length > 0;
  }

  get isEnded(): boolean {
    return this.rowIndex >= this.rows.length;
  }

  get isStarted(): boolean {
    return this.rowIndex < 0;
  }

  get isBeforeFirstRow(): boolean {
    return this.rowIndex < 0;
  }

  get isAfterLastRow(): boolean {
    return this.rowIndex >= this.rows.length;
  }

  goToFirstRow(): boolean {
    if (this.rows.length === 0) {
      return false;
    }
    this.rowIndex = 0;
    return true;
  }

  goToLastRow(): boolean {
    if (this.rows.length === 0) {
      return false;
    }
    this.rowIndex = this.rows.length - 1;
    return true;
  }

  goToNextRow(): boolean {
    if (this.throwOnNextRow && this.rowIndex >= 0) {
      throw new Error('row error');
    }
    this.rowIndex += 1;
    return this.rowIndex < this.rows.length;
  }

  goTo(offset: number): boolean {
    return this.goToRow(this.rowIndex + offset);
  }

  goToPreviousRow(): boolean {
    if (this.rowIndex <= 0) {
      this.rowIndex = -1;
      return false;
    }
    this.rowIndex -= 1;
    return true;
  }

  goToRow(position: number): boolean {
    if (position < 0 || position >= this.rows.length) {
      this.rowIndex = this.rows.length;
      return false;
    }
    this.rowIndex = position;
    return true;
  }

  close(): void {
    this.closeCount += 1;
    if (this.throwOnClose) {
      throw new Error('close error');
    }
    this.isClosed = true;
  }

  private getDbValue(index: number): DbValueType {
    const name = this.columnNames[index];
    const row = this.rows[this.rowIndex];
    if (!row) {
      return null;
    }
    return row.get(name);
  }

  private getRowRecord(): Record<string, DbValueType> {
    const row = this.rows[this.rowIndex];
    if (!row) {
      return new Object() as Record<string, DbValueType>;
    }
    return row.toRecord();
  }
}

const createMetadata = (): EntityMetadata => {
  const metadata = new EntityMetadata('User');
  const idColumn = new ColumnMetadata('id', 'id').setType(ColumnType.INTEGER).setNullable(false);
  const nameColumn = new ColumnMetadata('name', 'name').setType(ColumnType.TEXT);
  const scoreColumn = new ColumnMetadata('score', 'score').setType(ColumnType.REAL);
  const blobColumn = new ColumnMetadata('blob', 'blob').setType(ColumnType.BLOB);
  metadata.addColumn(idColumn);
  metadata.addColumn(nameColumn);
  metadata.addColumn(scoreColumn);
  metadata.addColumn(blobColumn);
  return metadata;
};

export default function resultSetUtilsTest() {
  describe('resultSetUtilsTest', () => {
    it('toRow should handle empty and error columns', 0, () => {
      const metadata = createMetadata();
      const columns: Array<string> = ['id', 'name', 'unknown', 'broken'];
      const rows: Array<RowData> = [
        new RowData().set('id', 7).set('name', 'Alice').set('unknown', 99).set('broken', 'bad')
      ];
      const fake = new FakeResultSet(columns, rows);
      fake.setThrowOnColumnIndex('broken');
      fake.setRowIndex(0);
      const row = ResultSetUtils.toRow(fake, metadata);
      expect(row.get('id')).assertEqual(7);
      expect(row.get('name')).assertEqual('Alice');
      expect(row.get('unknown')).assertEqual('99');
      expect(row.get('broken') === null).assertEqual(true);

      const emptyColumns: Array<string> = [];
      const emptyRows: Array<RowData> = [new RowData()];
      const emptyFake = new FakeResultSet(emptyColumns, emptyRows);
      emptyFake.setRowIndex(0);
      const emptyRow = ResultSetUtils.toRow(emptyFake, metadata);
      expect(emptyRow.getColumnNames().length).assertEqual(0);
    });

    it('toRowArray should return rows and tolerate failures', 0, () => {
      const metadata = createMetadata();
      const columns: Array<string> = ['id', 'name'];
      const rows: Array<RowData> = [
        new RowData().set('id', 1).set('name', 'A'),
        new RowData().set('id', 2).set('name', 'B')
      ];
      const fake = new FakeResultSet(columns, rows);
      const resultRows = ResultSetUtils.toRowArray(fake, metadata);
      expect(resultRows.length).assertEqual(2);
      expect(resultRows[1].get('id')).assertEqual(2);

      const failingColumns: Array<string> = ['id'];
      const failingRows: Array<RowData> = [new RowData().set('id', 1), new RowData().set('id', 2)];
      const failing = new FakeResultSet(failingColumns, failingRows);
      failing.setThrowOnNextRow(true);
      const partial = ResultSetUtils.toRowArray(failing, metadata);
      expect(partial.length).assertEqual(1);
    });

    it('getValueByType/getValueByRuntimeType should return values', 0, () => {
      const blob = new Uint8Array([1, 2, 3]);
      const columns: Array<string> = ['id', 'score', 'name', 'blob'];
      const rows: Array<RowData> = [
        new RowData().set('id', 5).set('score', 4.5).set('name', 'C').set('blob', blob)
      ];
      const fake = new FakeResultSet(columns, rows);
      fake.setRowIndex(0);
      const resultSet = fake;
      expect(ResultSetUtils.getValueByType(resultSet, 0, ColumnType.INTEGER)).assertEqual(5);
      expect(ResultSetUtils.getValueByType(resultSet, 1, ColumnType.REAL)).assertEqual(4.5);
      expect(ResultSetUtils.getValueByType(resultSet, 2, ColumnType.TEXT)).assertEqual('C');
      expect(ResultSetUtils.getValueByType(resultSet, 3, ColumnType.BLOB) === blob).assertEqual(true);

      const failingColumns: Array<string> = ['score'];
      const failingRows: Array<RowData> = [new RowData().set('score', 3.2)];
      const failing = new FakeResultSet(failingColumns, failingRows);
      failing.setRowIndex(0);
      failing.setThrowOnGet('double');
      const failureValue = ResultSetUtils.getValueByType(
        failing,
        0,
        ColumnType.REAL
      );
      expect(failureValue === null).assertEqual(true);

      const runtimeColumns: Array<string> = ['int', 'real', 'text', 'blob', 'null'];
      const runtimeRows: Array<RowData> = [
        new RowData()
          .set('int', 2)
          .set('real', 2.5)
          .set('text', 'hello')
          .set('blob', blob)
          .set('null', null)
      ];
      const runtimeFake = new FakeResultSet(runtimeColumns, runtimeRows);
      runtimeFake.setRowIndex(0);
      runtimeFake.setColumnType('int', 1 as relationalStore.ColumnType);
      runtimeFake.setColumnType('real', 2 as relationalStore.ColumnType);
      runtimeFake.setColumnType('text', 3 as relationalStore.ColumnType);
      runtimeFake.setColumnType('blob', 4 as relationalStore.ColumnType);
      runtimeFake.setColumnType('null', 0 as relationalStore.ColumnType);
      const runtimeSet = runtimeFake;
      expect(ResultSetUtils.getValueByRuntimeType(runtimeSet, 0)).assertEqual(2);
      expect(ResultSetUtils.getValueByRuntimeType(runtimeSet, 1)).assertEqual(2.5);
      expect(ResultSetUtils.getValueByRuntimeType(runtimeSet, 2)).assertEqual('hello');
      expectBlobEqual(ResultSetUtils.getValueByRuntimeType(runtimeSet, 3), blob);
      expect(ResultSetUtils.getValueByRuntimeType(runtimeSet, 4) === null).assertEqual(true);
    });

    it('getColumnValues should support metadata and runtime types', 0, () => {
      const metadata = createMetadata();
      const columns: Array<string> = ['id'];
      const rows: Array<RowData> = [
        new RowData().set('id', 1),
        new RowData().set('id', 2),
        new RowData().set('id', null)
      ];
      const fake = new FakeResultSet(columns, rows);
      const values = ResultSetUtils.getColumnValues(
        fake,
        'id',
        metadata
      );
      expect(values.length).assertEqual(2);
      expect(values[0]).assertEqual(1);
      expect(values[1]).assertEqual(2);

      const runtimeColumns: Array<string> = ['name'];
      const runtimeRows: Array<RowData> = [
        new RowData().set('name', 'Ann'),
        new RowData().set('name', 'Bob')
      ];
      const runtimeFake = new FakeResultSet(runtimeColumns, runtimeRows);
      const runtimeValues = ResultSetUtils.getColumnValues(
        runtimeFake,
        'name'
      );
      expect(runtimeValues.length).assertEqual(2);
      expect(runtimeValues[1]).assertEqual('Bob');
    });

    it('safeClose should ignore repeated calls and errors', 0, () => {
      const columns: Array<string> = ['id'];
      const rows: Array<RowData> = [new RowData().set('id', 1)];
      const fake = new FakeResultSet(columns, rows);
      ResultSetUtils.safeClose(fake);
      ResultSetUtils.safeClose(fake);
      expect(fake.closeCount).assertEqual(2);

      const failing = new FakeResultSet(columns, [new RowData().set('id', 1)]);
      failing.throwOnClose = true;
      ResultSetUtils.safeClose(failing);
      expect(failing.closeCount).assertEqual(1);

      ResultSetUtils.safeClose(null);
    });
  });
}
