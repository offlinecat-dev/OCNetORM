import { describe, beforeEach, it, expect } from '@ohos/hypium';
import { MetadataStorage } from '../../main/ets/core/MetadataStorage';
import { ColumnMetadata } from '../../main/ets/core/ColumnMetadata';
import { EntityNotRegisteredError } from '../../main/ets/errors/MetadataError';
import {
  RequiredValidationError,
  LengthValidationError,
  EmailValidationError,
  EntityValidationError
} from '../../main/ets/errors/ValidationError';
import { EntityData } from '../../main/ets/mapping/DataMapper';
import { EntityValidator } from '../../main/ets/validation/EntityValidator';
import { Required, Length, Email } from '../../main/ets/validation/ValidationDecorators';
import {
  ValidationMetadataStorage,
  ValidationRule,
  ValidationRuleType
} from '../../main/ets/validation/ValidationMetadataStorage';

type TestValue = string | number | boolean | null;

class ColumnEntry {
  propertyName: string;
  columnName: string;

  constructor(propertyName: string, columnName: string) {
    this.propertyName = propertyName;
    this.columnName = columnName;
  }
}

class ValueEntry {
  propertyName: string;
  value: TestValue;

  constructor(propertyName: string, value: TestValue) {
    this.propertyName = propertyName;
    this.value = value;
  }
}

class ValidationRuleItem implements ValidationRule {
  type: ValidationRuleType;
  min?: number;
  max?: number;

  constructor(type: ValidationRuleType, min?: number, max?: number) {
    this.type = type;
    if (min !== undefined) {
      this.min = min;
    }
    if (max !== undefined) {
      this.max = max;
    }
  }
}

const resetStorages = (): void => {
  MetadataStorage.resetInstance();
  ValidationMetadataStorage.resetInstance();
};

const registerEntity = (entityName: string, columns: Array<ColumnEntry> = []): void => {
  const storage = MetadataStorage.getInstance();
  storage.registerEntity(entityName);
  for (let i = 0; i < columns.length; i++) {
    const entry = columns[i];
    const column = new ColumnMetadata(entry.propertyName, entry.columnName);
    storage.registerColumn(entityName, column);
  }
};

const createEntityData = (entityName: string, values: Array<ValueEntry> = []): EntityData => {
  const data = new EntityData(entityName);
  for (let i = 0; i < values.length; i++) {
    const entry = values[i];
    data.setPropertyValue(entry.propertyName, entry.value);
  }
  return data;
};

const ruleRequired = (): ValidationRuleItem => {
  return new ValidationRuleItem('required');
};

const ruleEmail = (): ValidationRuleItem => {
  return new ValidationRuleItem('email');
};

const ruleLength = (min?: number, max?: number): ValidationRuleItem => {
  return new ValidationRuleItem('length', min, max);
};

export default function validationTest() {
  describe('validationTest', () => {
    describe('ValidationDecorators', () => {
      beforeEach(() => {
        resetStorages();
      });

      it('Required/Length/Email should register validation rules', 0, () => {
        class UserEntity {}
        const userInstance = new UserEntity();
        registerEntity(userInstance.constructor.name);

        Required()(userInstance, 'name');
        Length({ min: 2, max: 5 })(userInstance, 'name');
        Email()(userInstance, 'email');

        const storage = ValidationMetadataStorage.getInstance();
        const nameRules = storage.getRulesForProperty(userInstance.constructor.name, 'name');
        const emailRules = storage.getRulesForProperty(userInstance.constructor.name, 'email');

        expect(nameRules.length).assertEqual(2);
        expect(nameRules[0].type).assertEqual('required');
        expect(nameRules[1].type).assertEqual('length');
        expect(nameRules[1].min).assertEqual(2);
        expect(nameRules[1].max).assertEqual(5);

        expect(emailRules.length).assertEqual(1);
        expect(emailRules[0].type).assertEqual('email');
      });

      it('decorators should throw EntityNotRegisteredError when entity missing', 0, () => {
        class UserEntity {}
        const userInstance = new UserEntity();
        let caught = false;
        try {
          Required()(userInstance, 'name');
        } catch (error) {
          caught = error instanceof EntityNotRegisteredError;
        }
        expect(caught).assertEqual(true);
      });
    });

    describe('ValidationMetadataStorage', () => {
      beforeEach(() => {
        resetStorages();
      });

      it('registerRule should append multiple rules', 0, () => {
        registerEntity('UserEntity');
        const storage = ValidationMetadataStorage.getInstance();
        storage.registerRule('UserEntity', 'name', ruleRequired());
        storage.registerRule('UserEntity', 'name', ruleLength(1, 3));

        const rules = storage.getRulesForProperty('UserEntity', 'name');
        expect(rules.length).assertEqual(2);
        expect(rules[0].type).assertEqual('required');
        expect(rules[1].type).assertEqual('length');
      });

      it('getRules/getRulesForProperty/hasRules should reflect stored rules', 0, () => {
        registerEntity('UserEntity');
        const storage = ValidationMetadataStorage.getInstance();
        storage.registerRule('UserEntity', 'name', ruleRequired());
        storage.registerRule('UserEntity', 'email', ruleEmail());

        const rules = storage.getRules('UserEntity');
        expect(rules.size).assertEqual(2);
        expect(storage.hasRules('UserEntity')).assertEqual(true);
        expect(storage.getRulesForProperty('UserEntity', 'name').length).assertEqual(1);
      });

      it('clear should remove all rules', 0, () => {
        registerEntity('UserEntity');
        const storage = ValidationMetadataStorage.getInstance();
        storage.registerRule('UserEntity', 'name', ruleRequired());
        storage.clear();

        expect(storage.hasRules('UserEntity')).assertEqual(false);
        expect(storage.getRules('UserEntity').size).assertEqual(0);
      });

      it('resetInstance should drop stored rules', 0, () => {
        registerEntity('UserEntity');
        const storage = ValidationMetadataStorage.getInstance();
        storage.registerRule('UserEntity', 'name', ruleRequired());

        ValidationMetadataStorage.resetInstance();
        const newStorage = ValidationMetadataStorage.getInstance();
        expect(newStorage.hasRules('UserEntity')).assertEqual(false);
      });
    });

    describe('EntityValidator', () => {
      beforeEach(() => {
        resetStorages();
      });

      it('validate should pass when no rules', 0, () => {
        registerEntity('UserEntity');
        const data = createEntityData('UserEntity', [new ValueEntry('name', 'Alice')]);
        const result = EntityValidator.validate('UserEntity', data);
        expect(result.isValid()).assertEqual(true);
        expect(result.errors.length).assertEqual(0);
      });

      it('required should fail on missing/null/empty values', 0, () => {
        registerEntity('UserEntity');
        const storage = ValidationMetadataStorage.getInstance();
        storage.registerRule('UserEntity', 'name', ruleRequired());

        const missing = EntityValidator.validate('UserEntity', createEntityData('UserEntity'));
        expect(missing.errors.length).assertEqual(1);
        expect(missing.errors[0] instanceof RequiredValidationError).assertEqual(true);

        const nullValue = EntityValidator.validate(
          'UserEntity',
          createEntityData('UserEntity', [new ValueEntry('name', null)])
        );
        expect(nullValue.errors.length).assertEqual(1);
        expect(nullValue.errors[0] instanceof RequiredValidationError).assertEqual(true);

        const emptyValue = EntityValidator.validate(
          'UserEntity',
          createEntityData('UserEntity', [new ValueEntry('name', '  ')])
        );
        expect(emptyValue.errors.length).assertEqual(1);
        expect(emptyValue.errors[0] instanceof RequiredValidationError).assertEqual(true);
      });

      it('length should enforce min/max and skip non-string values', 0, () => {
        registerEntity('UserEntity');
        const storage = ValidationMetadataStorage.getInstance();
        storage.registerRule('UserEntity', 'title', ruleLength(2, 4));

        const tooShort = EntityValidator.validate(
          'UserEntity',
          createEntityData('UserEntity', [new ValueEntry('title', 'a')])
        );
        expect(tooShort.errors.length).assertEqual(1);
        expect(tooShort.errors[0] instanceof LengthValidationError).assertEqual(true);

        const within = EntityValidator.validate(
          'UserEntity',
          createEntityData('UserEntity', [new ValueEntry('title', 'abcd')])
        );
        expect(within.errors.length).assertEqual(0);

        const tooLong = EntityValidator.validate(
          'UserEntity',
          createEntityData('UserEntity', [new ValueEntry('title', 'abcde')])
        );
        expect(tooLong.errors.length).assertEqual(1);
        expect(tooLong.errors[0] instanceof LengthValidationError).assertEqual(true);

        const nonString = EntityValidator.validate(
          'UserEntity',
          createEntityData('UserEntity', [new ValueEntry('title', 123)])
        );
        expect(nonString.errors.length).assertEqual(0);
      });

      it('email should validate format and ignore empty values', 0, () => {
        registerEntity('UserEntity');
        const storage = ValidationMetadataStorage.getInstance();
        storage.registerRule('UserEntity', 'email', ruleEmail());

        const invalid = EntityValidator.validate(
          'UserEntity',
          createEntityData('UserEntity', [new ValueEntry('email', 'bad@')])
        );
        expect(invalid.errors.length).assertEqual(1);
        expect(invalid.errors[0] instanceof EmailValidationError).assertEqual(true);

        const empty = EntityValidator.validate(
          'UserEntity',
          createEntityData('UserEntity', [new ValueEntry('email', '  ')])
        );
        expect(empty.errors.length).assertEqual(0);

        const nullValue = EntityValidator.validate(
          'UserEntity',
          createEntityData('UserEntity', [new ValueEntry('email', null)])
        );
        expect(nullValue.errors.length).assertEqual(0);
      });

      it('validateOrThrow should throw single error and aggregate multiple errors', 0, () => {
        registerEntity('UserEntity', [
          new ColumnEntry('name', 'user_name'),
          new ColumnEntry('email', 'user_email')
        ]);
        const storage = ValidationMetadataStorage.getInstance();
        storage.registerRule('UserEntity', 'name', ruleRequired());

        let singleError = false;
        try {
          EntityValidator.validateOrThrow('UserEntity', createEntityData('UserEntity'));
        } catch (error) {
          singleError = error instanceof RequiredValidationError;
        }
        expect(singleError).assertEqual(true);

        storage.registerRule('UserEntity', 'email', ruleEmail());
        const data = createEntityData('UserEntity', [
          new ValueEntry('name', ''),
          new ValueEntry('email', 'bad@')
        ]);
        let multipleError = false;
        try {
          EntityValidator.validateOrThrow('UserEntity', data);
        } catch (error) {
          multipleError = error instanceof EntityValidationError;
        }
        expect(multipleError).assertEqual(true);
      });
    });
  });
}
