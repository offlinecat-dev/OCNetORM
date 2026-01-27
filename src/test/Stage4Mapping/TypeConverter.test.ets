import { describe, it, expect } from '@ohos/hypium';
import { ColumnType } from '../../main/ets/types/ColumnType';
import { TypeConverter } from '../../main/ets/mapping/TypeConverter';
import { TypeConversionError } from '../../main/ets/errors/MappingError';
import { DbValueType } from '../../main/ets/types/ValueTypes';

class JsonPayload {
  name: string;
  age: number;

  constructor(name: string, age: number) {
    this.name = name;
    this.age = age;
  }
}

export default function typeConverterTest() {
  describe('typeConverterTest', () => {
    it('should convert Date/boolean/object helpers', 0, () => {
      const date = new Date(2024, 0, 1, 12, 30, 0);
      const timestamp = TypeConverter.dateToTimestamp(date);
      const restored = TypeConverter.timestampToDate(timestamp);
      expect(restored.getTime()).assertEqual(timestamp);

      expect(TypeConverter.booleanToInt(true)).assertEqual(1);
      expect(TypeConverter.booleanToInt(false)).assertEqual(0);
      expect(TypeConverter.intToBoolean(0)).assertEqual(false);
      expect(TypeConverter.intToBoolean(2)).assertEqual(true);

      const payload = new JsonPayload('Alice', 20);
      const json = TypeConverter.objectToJson(payload);
      const parsed = TypeConverter.jsonToObject(json);
      expect(JSON.stringify(parsed)).assertEqual(json);
    });

    it('toDbValue should handle column type conversions', 0, () => {
      const textValue = TypeConverter.toDbValue(123, ColumnType.TEXT, 'number');
      expect(textValue).assertEqual('123');

      const intValue = TypeConverter.toDbValue(3.8, ColumnType.INTEGER, 'number');
      expect(intValue).assertEqual(3);
      const boolValue = TypeConverter.toDbValue(true, ColumnType.INTEGER, 'boolean');
      expect(boolValue).assertEqual(1);

      const realValue = TypeConverter.toDbValue('3.5', ColumnType.REAL, 'string');
      expect(realValue).assertEqual(0);

      const blobString = TypeConverter.toDbValue('blob', ColumnType.BLOB, 'string');
      expect(blobString).assertEqual('blob');
      const blobNumber = TypeConverter.toDbValue(12, ColumnType.BLOB, 'number');
      expect(blobNumber).assertEqual('12');

      const objectJson = TypeConverter.toDbValue('{"k":"v"}', ColumnType.TEXT, 'object');
      expect(objectJson).assertEqual('{"k":"v"}');
    });

    it('fromDbValue should convert and throw on mismatch', 0, () => {
      const stringValue = TypeConverter.fromDbValue(42, 'string', 'col');
      expect(stringValue).assertEqual('42');

      const numberValue = TypeConverter.fromDbValue('3.14', 'number', 'col');
      expect(numberValue).assertEqual(3.14);

      const booleanValue = TypeConverter.fromDbValue(1, 'boolean', 'col');
      expect(booleanValue).assertEqual(true);

      const dateValue = TypeConverter.fromDbValue(1000, 'Date', 'col');
      expect(dateValue).assertEqual(1000);

      const objectValue = TypeConverter.fromDbValue('{"a":1}', 'object', 'col');
      expect(objectValue).assertEqual('{"a":1}');

      const invalidValue: DbValueType = new Uint8Array([1]);
      let threw = false;
      try {
        TypeConverter.fromDbValue(invalidValue, 'string', 'col');
      } catch (error) {
        threw = error instanceof TypeConversionError;
      }
      expect(threw).assertEqual(true);
    });
  });
}
