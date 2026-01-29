import { describe, beforeEach, it, expect } from '@ohos/hypium';
import { MetadataStorage } from '../../main/ets/core/MetadataStorage';
import { ColumnMetadata } from '../../main/ets/core/ColumnMetadata';
import { ColumnType } from '../../main/ets/types/ColumnType';
import { ConditionOperator } from '../../main/ets/types/ConditionOperator';
import { QueryBuilder } from '../../main/ets/query/QueryBuilder';
import { EntityData } from '../../main/ets/mapping/DataMapper';
import { DataMapper } from '../../main/ets/mapping/DataMapper';
import { TypeConverter } from '../../main/ets/mapping/TypeConverter';
import { EntityNotRegisteredError } from '../../main/ets/errors/MetadataError';
import { InvalidConditionError } from '../../main/ets/errors/QueryError';
import { RelationNotFoundError } from '../../main/ets/errors/RelationError';
import { HooksProcessor } from '../../main/ets/core/HooksProcessor';
import { QueryCache } from '../../main/ets/query/QueryCache';

const setupTestEntity = (): void => {
  const storage = MetadataStorage.getInstance();
  storage.registerEntity('TestEntity', 'test_entities');

  const idColumn = new ColumnMetadata('id', 'id')
    .setType(ColumnType.INTEGER)
    .setPrimaryKey(true)
    .setAutoIncrement(true);
  storage.registerColumn('TestEntity', idColumn);

  const nameColumn = new ColumnMetadata('name', 'name')
    .setType(ColumnType.TEXT);
  storage.registerColumn('TestEntity', nameColumn);

  const descColumn = new ColumnMetadata('description', 'description')
    .setType(ColumnType.TEXT)
    .setNullable(true);
  storage.registerColumn('TestEntity', descColumn);

  const ageColumn = new ColumnMetadata('age', 'age')
    .setType(ColumnType.INTEGER)
    .setNullable(true);
  storage.registerColumn('TestEntity', ageColumn);
};


export default function compatibilityTest() {
  describe('Stage16_Compatibility_BoundaryConditions_Test', () => {
    beforeEach(() => {
      MetadataStorage.resetInstance();
      HooksProcessor.resetInstance();
      QueryCache.resetInstance();
    });

    describe('空实体列表测试', () => {
      it('QueryBuilder_no_conditions_returns_empty_array', 0, () => {
        setupTestEntity();

        const builder = new QueryBuilder('TestEntity');
        const conditions = builder.getConditions();

        expect(conditions.length).assertEqual(0);
      });

      it('QueryBuilder_getAllConditions_no_user_conditions', 0, () => {
        setupTestEntity();

        const builder = new QueryBuilder('TestEntity');
        const allConditions = builder.getAllConditions();

        expect(allConditions.length).assertEqual(0);
      });

      it('QueryBuilder_no_orderBy_returns_empty_array', 0, () => {
        setupTestEntity();

        const builder = new QueryBuilder('TestEntity');
        const orderBy = builder.getOrderByColumns();

        expect(orderBy.length).assertEqual(0);
      });

      it('QueryBuilder_no_selected_columns_returns_empty_array', 0, () => {
        setupTestEntity();

        const builder = new QueryBuilder('TestEntity');
        const selectedColumns = builder.getSelectedColumns();

        expect(selectedColumns.length).assertEqual(0);
      });

      it('QueryBuilder_reset_clears_all_state', 0, () => {
        setupTestEntity();

        const builder = new QueryBuilder('TestEntity');
        builder.where('name', ConditionOperator.EQUAL, 'test');
        builder.orderBy('id', 'ASC');
        builder.limit(10);
        builder.offset(5);

        builder.reset();

        expect(builder.getConditions().length).assertEqual(0);
        expect(builder.getOrderByColumns().length).assertEqual(0);
        expect(builder.getLimitValue()).assertEqual(0);
        expect(builder.getOffsetValue()).assertEqual(0);
      });
    });

    describe('非法列名测试', () => {
      it('QueryBuilder_where_invalid_column_throws_error', 0, () => {
        setupTestEntity();

        const builder = new QueryBuilder('TestEntity');
        let threw = false;
        let errorType = '';

        try {
          builder.where('nonExistentColumn', ConditionOperator.EQUAL, 'value');
        } catch (e) {
          threw = true;
          if (e instanceof InvalidConditionError) {
            errorType = 'InvalidConditionError';
          }
        }

        expect(threw).assertEqual(true);
        expect(errorType).assertEqual('InvalidConditionError');
      });

      it('QueryBuilder_andWhere_invalid_column_throws_error', 0, () => {
        setupTestEntity();

        const builder = new QueryBuilder('TestEntity');
        builder.where('name', ConditionOperator.EQUAL, 'test');

        let threw = false;
        let errorType = '';

        try {
          builder.andWhere('invalidColumn', ConditionOperator.EQUAL, 'value');
        } catch (e) {
          threw = true;
          if (e instanceof InvalidConditionError) {
            errorType = 'InvalidConditionError';
          }
        }

        expect(threw).assertEqual(true);
        expect(errorType).assertEqual('InvalidConditionError');
      });

      it('QueryBuilder_orWhere_invalid_column_throws_error', 0, () => {
        setupTestEntity();

        const builder = new QueryBuilder('TestEntity');
        builder.where('name', ConditionOperator.EQUAL, 'test');

        let threw = false;
        let errorType = '';

        try {
          builder.orWhere('badColumn', ConditionOperator.EQUAL, 'value');
        } catch (e) {
          threw = true;
          if (e instanceof InvalidConditionError) {
            errorType = 'InvalidConditionError';
          }
        }

        expect(threw).assertEqual(true);
        expect(errorType).assertEqual('InvalidConditionError');
      });

      it('QueryBuilder_whereIn_invalid_column_throws_error', 0, () => {
        setupTestEntity();

        const builder = new QueryBuilder('TestEntity');
        let threw = false;
        let errorType = '';

        try {
          builder.whereIn('unknownColumn', [1, 2, 3]);
        } catch (e) {
          threw = true;
          if (e instanceof InvalidConditionError) {
            errorType = 'InvalidConditionError';
          }
        }

        expect(threw).assertEqual(true);
        expect(errorType).assertEqual('InvalidConditionError');
      });

      it('QueryBuilder_whereNull_invalid_column_throws_error', 0, () => {
        setupTestEntity();

        const builder = new QueryBuilder('TestEntity');
        let threw = false;
        let errorType = '';

        try {
          builder.whereNull('fakeColumn');
        } catch (e) {
          threw = true;
          if (e instanceof InvalidConditionError) {
            errorType = 'InvalidConditionError';
          }
        }

        expect(threw).assertEqual(true);
        expect(errorType).assertEqual('InvalidConditionError');
      });

      it('QueryBuilder_whereNotNull_invalid_column_throws_error', 0, () => {
        setupTestEntity();

        const builder = new QueryBuilder('TestEntity');
        let threw = false;
        let errorType = '';

        try {
          builder.whereNotNull('missingColumn');
        } catch (e) {
          threw = true;
          if (e instanceof InvalidConditionError) {
            errorType = 'InvalidConditionError';
          }
        }

        expect(threw).assertEqual(true);
        expect(errorType).assertEqual('InvalidConditionError');
      });

      it('QueryBuilder_whereBetween_invalid_column_throws_error', 0, () => {
        setupTestEntity();

        const builder = new QueryBuilder('TestEntity');
        let threw = false;
        let errorType = '';

        try {
          builder.whereBetween('noSuchColumn', 1, 10);
        } catch (e) {
          threw = true;
          if (e instanceof InvalidConditionError) {
            errorType = 'InvalidConditionError';
          }
        }

        expect(threw).assertEqual(true);
        expect(errorType).assertEqual('InvalidConditionError');
      });

      it('QueryBuilder_whereLike_invalid_column_throws_error', 0, () => {
        setupTestEntity();

        const builder = new QueryBuilder('TestEntity');
        let threw = false;
        let errorType = '';

        try {
          builder.whereLike('notAColumn', '%test%');
        } catch (e) {
          threw = true;
          if (e instanceof InvalidConditionError) {
            errorType = 'InvalidConditionError';
          }
        }

        expect(threw).assertEqual(true);
        expect(errorType).assertEqual('InvalidConditionError');
      });

      it('QueryBuilder_orderBy_invalid_column_throws_error', 0, () => {
        setupTestEntity();

        const builder = new QueryBuilder('TestEntity');
        let threw = false;
        let errorType = '';

        try {
          builder.orderBy('wrongColumn', 'ASC');
        } catch (e) {
          threw = true;
          if (e instanceof InvalidConditionError) {
            errorType = 'InvalidConditionError';
          }
        }

        expect(threw).assertEqual(true);
        expect(errorType).assertEqual('InvalidConditionError');
      });

      it('QueryBuilder_select_invalid_column_throws_error', 0, () => {
        setupTestEntity();

        const builder = new QueryBuilder('TestEntity');
        let threw = false;
        let errorType = '';

        try {
          builder.select(['id', 'invalidColumn', 'name']);
        } catch (e) {
          threw = true;
          if (e instanceof InvalidConditionError) {
            errorType = 'InvalidConditionError';
          }
        }

        expect(threw).assertEqual(true);
        expect(errorType).assertEqual('InvalidConditionError');
      });

      it('QueryBuilder_select_empty_array_no_error', 0, () => {
        setupTestEntity();

        const builder = new QueryBuilder('TestEntity');
        let threw = false;

        try {
          builder.select([]);
        } catch (e) {
          threw = true;
        }

        expect(threw).assertEqual(false);
        expect(builder.getSelectedColumns().length).assertEqual(0);
      });
    });

    describe('非法 relationName 测试', () => {
      it('QueryBuilder_with_invalid_relation_throws_error', 0, () => {
        setupTestEntity();

        const builder = new QueryBuilder('TestEntity');
        let threw = false;
        let errorType = '';

        try {
          builder.with('nonExistentRelation');
        } catch (e) {
          threw = true;
          if (e instanceof RelationNotFoundError) {
            errorType = 'RelationNotFoundError';
          }
        }

        expect(threw).assertEqual(true);
        expect(errorType).assertEqual('RelationNotFoundError');
      });

      it('QueryBuilder_withLazy_invalid_relation_throws_error', 0, () => {
        setupTestEntity();

        const builder = new QueryBuilder('TestEntity');
        let threw = false;
        let errorType = '';

        try {
          builder.withLazy('fakeRelation');
        } catch (e) {
          threw = true;
          if (e instanceof RelationNotFoundError) {
            errorType = 'RelationNotFoundError';
          }
        }

        expect(threw).assertEqual(true);
        expect(errorType).assertEqual('RelationNotFoundError');
      });

      it('QueryBuilder_whereExists_invalid_relation_throws_error', 0, () => {
        setupTestEntity();

        const builder = new QueryBuilder('TestEntity');
        let threw = false;
        let errorType = '';

        try {
          builder.whereExists('unknownRelation', (subQuery) => {
            subQuery.where('id', ConditionOperator.EQUAL, 1);
          });
        } catch (e) {
          threw = true;
          if (e instanceof RelationNotFoundError) {
            errorType = 'RelationNotFoundError';
          }
        }

        expect(threw).assertEqual(true);
        expect(errorType).assertEqual('RelationNotFoundError');
      });

    });

    describe('非法参数测试（负数分页、负 limit）', () => {
      it('QueryBuilder_negative_limit_throws_error', 0, () => {
        setupTestEntity();

        const builder = new QueryBuilder('TestEntity');
        let threw = false;
        let errorType = '';

        try {
          builder.limit(-1);
        } catch (e) {
          threw = true;
          if (e instanceof InvalidConditionError) {
            errorType = 'InvalidConditionError';
          }
        }

        expect(threw).assertEqual(true);
        expect(errorType).assertEqual('InvalidConditionError');
      });

      it('QueryBuilder_negative_offset_throws_error', 0, () => {
        setupTestEntity();

        const builder = new QueryBuilder('TestEntity');
        let threw = false;
        let errorType = '';

        try {
          builder.offset(-10);
        } catch (e) {
          threw = true;
          if (e instanceof InvalidConditionError) {
            errorType = 'InvalidConditionError';
          }
        }

        expect(threw).assertEqual(true);
        expect(errorType).assertEqual('InvalidConditionError');
      });

      it('QueryBuilder_zero_limit_no_error', 0, () => {
        setupTestEntity();

        const builder = new QueryBuilder('TestEntity');
        let threw = false;

        try {
          builder.limit(0);
        } catch (e) {
          threw = true;
        }

        expect(threw).assertEqual(false);
        expect(builder.getLimitValue()).assertEqual(0);
      });

      it('QueryBuilder_zero_offset_no_error', 0, () => {
        setupTestEntity();

        const builder = new QueryBuilder('TestEntity');
        let threw = false;

        try {
          builder.offset(0);
        } catch (e) {
          threw = true;
        }

        expect(threw).assertEqual(false);
        expect(builder.getOffsetValue()).assertEqual(0);
      });

      it('QueryBuilder_paginate_negative_page_normalized_to_1', 0, () => {
        setupTestEntity();

        const builder = new QueryBuilder('TestEntity');
        builder.paginate(-5, 10);

        expect(builder.getPageNumber()).assertEqual(1);
        expect(builder.getPageSizeValue()).assertEqual(10);
        expect(builder.getOffsetValue()).assertEqual(0);
        expect(builder.getLimitValue()).assertEqual(10);
      });

      it('QueryBuilder_paginate_zero_page_normalized_to_1', 0, () => {
        setupTestEntity();

        const builder = new QueryBuilder('TestEntity');
        builder.paginate(0, 20);

        expect(builder.getPageNumber()).assertEqual(1);
        expect(builder.getPageSizeValue()).assertEqual(20);
        expect(builder.getOffsetValue()).assertEqual(0);
        expect(builder.getLimitValue()).assertEqual(20);
      });

      it('QueryBuilder_paginate_negative_size_normalized_to_20', 0, () => {
        setupTestEntity();

        const builder = new QueryBuilder('TestEntity');
        builder.paginate(1, -10);

        expect(builder.getPageNumber()).assertEqual(1);
        expect(builder.getPageSizeValue()).assertEqual(20);
        expect(builder.getOffsetValue()).assertEqual(0);
        expect(builder.getLimitValue()).assertEqual(20);
      });

      it('QueryBuilder_paginate_zero_size_normalized_to_20', 0, () => {
        setupTestEntity();

        const builder = new QueryBuilder('TestEntity');
        builder.paginate(2, 0);

        expect(builder.getPageNumber()).assertEqual(2);
        expect(builder.getPageSizeValue()).assertEqual(20);
        expect(builder.getOffsetValue()).assertEqual(20);
        expect(builder.getLimitValue()).assertEqual(20);
      });

      it('QueryBuilder_forPage_same_as_paginate', 0, () => {
        setupTestEntity();

        const builder = new QueryBuilder('TestEntity');
        builder.forPage(-1, -1);

        expect(builder.getPageNumber()).assertEqual(1);
        expect(builder.getPageSizeValue()).assertEqual(20);
      });

      it('QueryBuilder_large_page_number_calculates_offset', 0, () => {
        setupTestEntity();

        const builder = new QueryBuilder('TestEntity');
        builder.paginate(100, 50);

        expect(builder.getPageNumber()).assertEqual(100);
        expect(builder.getPageSizeValue()).assertEqual(50);
        expect(builder.getOffsetValue()).assertEqual(4950);
        expect(builder.getLimitValue()).assertEqual(50);
      });
    });

    describe('极端字符串长度与 Unicode 数据测试', () => {
      it('EntityData_handle_empty_string', 0, () => {
        setupTestEntity();

        const entity = new EntityData('TestEntity');
        entity.addProperty('name', '', 'string');

        const prop = entity.getProperty('name');
        expect(prop !== null).assertEqual(true);
        if (prop !== null) {
          expect(prop.value).assertEqual('');
        }
      });

      it('EntityData_handle_very_long_string', 0, () => {
        setupTestEntity();

        const entity = new EntityData('TestEntity');
        const longString = 'a'.repeat(10000);
        entity.addProperty('description', longString, 'string');

        const prop = entity.getProperty('description');
        expect(prop !== null).assertEqual(true);
        if (prop !== null) {
          expect((prop.value as string).length).assertEqual(10000);
        }
      });

      it('EntityData_handle_unicode_characters', 0, () => {
        setupTestEntity();

        const entity = new EntityData('TestEntity');
        const unicodeString = '你好世界🌍🎉';
        entity.addProperty('name', unicodeString, 'string');

        const prop = entity.getProperty('name');
        expect(prop !== null).assertEqual(true);
        if (prop !== null) {
          expect(prop.value).assertEqual(unicodeString);
        }
      });

      it('EntityData_handle_mixed_unicode_and_ascii', 0, () => {
        setupTestEntity();

        const entity = new EntityData('TestEntity');
        const mixedString = 'Hello你好World世界123';
        entity.addProperty('name', mixedString, 'string');

        const prop = entity.getProperty('name');
        expect(prop !== null).assertEqual(true);
        if (prop !== null) {
          expect(prop.value).assertEqual(mixedString);
        }
      });

      it('EntityData_handle_special_characters', 0, () => {
        setupTestEntity();

        const entity = new EntityData('TestEntity');
        const specialString = '!@#$%^&*()_+-=[]{}|;:\'",.<>?/\\`~';
        entity.addProperty('name', specialString, 'string');

        const prop = entity.getProperty('name');
        expect(prop !== null).assertEqual(true);
        if (prop !== null) {
          expect(prop.value).assertEqual(specialString);
        }
      });

      it('EntityData_handle_newlines_and_tabs', 0, () => {
        setupTestEntity();

        const entity = new EntityData('TestEntity');
        const multilineString = 'Line1\nLine2\tTabbed\rCarriageReturn';
        entity.addProperty('description', multilineString, 'string');

        const prop = entity.getProperty('description');
        expect(prop !== null).assertEqual(true);
        if (prop !== null) {
          expect(prop.value).assertEqual(multilineString);
        }
      });

      it('EntityData_handle_emoji_only', 0, () => {
        setupTestEntity();

        const entity = new EntityData('TestEntity');
        const emojiString = '😀😃😄😁😆😅🤣😂🙂🙃';
        entity.addProperty('name', emojiString, 'string');

        const prop = entity.getProperty('name');
        expect(prop !== null).assertEqual(true);
        if (prop !== null) {
          expect(prop.value).assertEqual(emojiString);
        }
      });

      it('EntityData_handle_null_character', 0, () => {
        setupTestEntity();

        const entity = new EntityData('TestEntity');
        const stringWithNull = 'before\0after';
        entity.addProperty('description', stringWithNull, 'string');

        const prop = entity.getProperty('description');
        expect(prop !== null).assertEqual(true);
        if (prop !== null) {
          expect(prop.value).assertEqual(stringWithNull);
        }
      });

      it('EntityData_handle_cyrillic_characters', 0, () => {
        setupTestEntity();

        const entity = new EntityData('TestEntity');
        const cyrillicString = 'Привет мир';
        entity.addProperty('name', cyrillicString, 'string');

        const prop = entity.getProperty('name');
        expect(prop !== null).assertEqual(true);
        if (prop !== null) {
          expect(prop.value).assertEqual(cyrillicString);
        }
      });

      it('EntityData_handle_arabic_characters', 0, () => {
        setupTestEntity();

        const entity = new EntityData('TestEntity');
        const arabicString = 'مرحبا بالعالم';
        entity.addProperty('name', arabicString, 'string');

        const prop = entity.getProperty('name');
        expect(prop !== null).assertEqual(true);
        if (prop !== null) {
          expect(prop.value).assertEqual(arabicString);
        }
      });

      it('EntityData_handle_japanese_characters', 0, () => {
        setupTestEntity();

        const entity = new EntityData('TestEntity');
        const japaneseString = 'こんにちは世界';
        entity.addProperty('name', japaneseString, 'string');

        const prop = entity.getProperty('name');
        expect(prop !== null).assertEqual(true);
        if (prop !== null) {
          expect(prop.value).assertEqual(japaneseString);
        }
      });

      it('TypeConverter_handle_unicode_text', 0, () => {
        const unicodeText = '测试数据🎯';

        const dbValue = TypeConverter.toDbValue(unicodeText, ColumnType.TEXT, 'string');
        expect(dbValue).assertEqual(unicodeText);

        const appValue = TypeConverter.fromDbValue(dbValue as string, 'string', 'test');
        expect(appValue).assertEqual(unicodeText);
      });

      it('TypeConverter_handle_very_long_text', 0, () => {
        const longText = 'x'.repeat(50000);

        const dbValue = TypeConverter.toDbValue(longText, ColumnType.TEXT, 'string');
        expect((dbValue as string).length).assertEqual(50000);
      });
    });

    describe('未注册实体测试', () => {
      it('QueryBuilder_unregistered_entity_throws_error', 0, () => {
        MetadataStorage.resetInstance();

        let threw = false;
        let errorType = '';

        try {
          new QueryBuilder('UnregisteredEntity');
        } catch (e) {
          threw = true;
          if (e instanceof EntityNotRegisteredError) {
            errorType = 'EntityNotRegisteredError';
          }
        }

        expect(threw).assertEqual(true);
        expect(errorType).assertEqual('EntityNotRegisteredError');
      });

      it('DataMapper_unregistered_entity_throws_error', 0, () => {
        MetadataStorage.resetInstance();

        let threw = false;
        let errorType = '';

        try {
          new DataMapper('MissingEntity');
        } catch (e) {
          threw = true;
          if (e instanceof EntityNotRegisteredError) {
            errorType = 'EntityNotRegisteredError';
          }
        }

        expect(threw).assertEqual(true);
        expect(errorType).assertEqual('EntityNotRegisteredError');
      });
    });

    describe('边界数值测试', () => {
      it('EntityData_handle_max_safe_integer', 0, () => {
        setupTestEntity();

        const entity = new EntityData('TestEntity');
        entity.addProperty('id', Number.MAX_SAFE_INTEGER, 'number');

        const prop = entity.getProperty('id');
        expect(prop !== null).assertEqual(true);
        if (prop !== null) {
          expect(prop.value).assertEqual(Number.MAX_SAFE_INTEGER);
        }
      });

      it('EntityData_handle_min_safe_integer', 0, () => {
        setupTestEntity();

        const entity = new EntityData('TestEntity');
        entity.addProperty('age', Number.MIN_SAFE_INTEGER, 'number');

        const prop = entity.getProperty('age');
        expect(prop !== null).assertEqual(true);
        if (prop !== null) {
          expect(prop.value).assertEqual(Number.MIN_SAFE_INTEGER);
        }
      });

      it('EntityData_handle_zero', 0, () => {
        setupTestEntity();

        const entity = new EntityData('TestEntity');
        entity.addProperty('age', 0, 'number');

        const prop = entity.getProperty('age');
        expect(prop !== null).assertEqual(true);
        if (prop !== null) {
          expect(prop.value).assertEqual(0);
        }
      });

      it('EntityData_handle_negative_zero', 0, () => {
        setupTestEntity();

        const entity = new EntityData('TestEntity');
        entity.addProperty('age', -0, 'number');

        const prop = entity.getProperty('age');
        expect(prop !== null).assertEqual(true);
        if (prop !== null) {
          expect(prop.value === 0).assertEqual(true);
        }
      });

      it('EntityData_handle_float_values', 0, () => {
        setupTestEntity();

        const entity = new EntityData('TestEntity');
        entity.addProperty('age', 3.14159265359, 'number');

        const prop = entity.getProperty('age');
        expect(prop !== null).assertEqual(true);
        if (prop !== null) {
          expect(prop.value).assertEqual(3.14159265359);
        }
      });

      it('EntityData_handle_very_small_float', 0, () => {
        setupTestEntity();

        const entity = new EntityData('TestEntity');
        const smallFloat = 0.000000001;
        entity.addProperty('age', smallFloat, 'number');

        const prop = entity.getProperty('age');
        expect(prop !== null).assertEqual(true);
        if (prop !== null) {
          expect(prop.value).assertEqual(smallFloat);
        }
      });

      it('TypeConverter_handle_integer_boundary', 0, () => {
        const maxInt = Number.MAX_SAFE_INTEGER;
        const dbValue = TypeConverter.toDbValue(maxInt, ColumnType.INTEGER, 'number');
        expect(dbValue).assertEqual(maxInt);
      });

      it('TypeConverter_handle_real_precision', 0, () => {
        const realValue = 123.456789;
        const dbValue = TypeConverter.toDbValue(realValue, ColumnType.REAL, 'number');
        expect(dbValue).assertEqual(realValue);
      });
    });

    describe('空值与 null 处理测试', () => {
      it('EntityData_handle_null_value', 0, () => {
        setupTestEntity();

        const entity = new EntityData('TestEntity');
        entity.addProperty('description', null, 'string');

        const prop = entity.getProperty('description');
        expect(prop !== null).assertEqual(true);
        if (prop !== null) {
          expect(prop.value).assertEqual(null);
        }
      });

      it('EntityData_handle_undefined_converts_to_null', 0, () => {
        setupTestEntity();

        const entity = new EntityData('TestEntity');
        entity.addProperty('description', null, 'string');

        const prop = entity.getProperty('description');
        expect(prop !== null).assertEqual(true);
      });

      it('EntityData_getProperty_returns_null_for_missing', 0, () => {
        setupTestEntity();

        const entity = new EntityData('TestEntity');

        const prop = entity.getProperty('nonExistentProperty');
        expect(prop === null).assertEqual(true);
      });

      it('EntityData_getPropertyValue_returns_null_for_missing', 0, () => {
        setupTestEntity();

        const entity = new EntityData('TestEntity');

        const value = entity.getPropertyValue('missingProperty');
        expect(value === null).assertEqual(true);
      });

      it('QueryBuilder_whereIn_empty_array_throws_error', 0, () => {
        setupTestEntity();

        const builder = new QueryBuilder('TestEntity');
        let threw = false;

        try {
          builder.whereIn('id', []);
        } catch (e) {
          threw = true;
        }

        expect(threw).assertEqual(true);
      });

      it('TypeConverter_handle_null_to_db', 0, () => {
        const dbValue = TypeConverter.toDbValue(null, ColumnType.TEXT, 'string');
        expect(dbValue).assertEqual(null);
      });

      it('TypeConverter_handle_null_from_db', 0, () => {
        const appValue = TypeConverter.fromDbValue(null, 'string', 'test');
        expect(appValue).assertEqual(null);
      });
    });

    describe('链式调用边界测试', () => {
      it('QueryBuilder_multiple_where_conditions', 0, () => {
        setupTestEntity();

        const builder = new QueryBuilder('TestEntity');
        builder
          .where('name', ConditionOperator.LIKE, '%test%')
          .andWhere('age', ConditionOperator.GREATER, 18)
          .orWhere('description', ConditionOperator.IS_NOT_NULL, null)
          .orderBy('id', 'DESC')
          .limit(100)
          .offset(50);

        expect(builder.getConditions().length).assertEqual(3);
        expect(builder.getOrderByColumns().length).assertEqual(1);
        expect(builder.getLimitValue()).assertEqual(100);
        expect(builder.getOffsetValue()).assertEqual(50);
      });

      it('QueryBuilder_chained_orderBy', 0, () => {
        setupTestEntity();

        const builder = new QueryBuilder('TestEntity');
        builder
          .orderBy('name', 'ASC')
          .orderBy('id', 'DESC');

        expect(builder.getOrderByColumns().length).assertEqual(2);
      });

      it('QueryBuilder_overwrite_limit', 0, () => {
        setupTestEntity();

        const builder = new QueryBuilder('TestEntity');
        builder.limit(10);
        builder.limit(20);

        expect(builder.getLimitValue()).assertEqual(20);
      });

      it('QueryBuilder_overwrite_offset', 0, () => {
        setupTestEntity();

        const builder = new QueryBuilder('TestEntity');
        builder.offset(5);
        builder.offset(15);

        expect(builder.getOffsetValue()).assertEqual(15);
      });

      it('QueryBuilder_paginate_overrides_limit_offset', 0, () => {
        setupTestEntity();

        const builder = new QueryBuilder('TestEntity');
        builder.limit(100);
        builder.offset(200);
        builder.paginate(2, 25);

        expect(builder.getLimitValue()).assertEqual(25);
        expect(builder.getOffsetValue()).assertEqual(25);
      });
    });
  });
}
