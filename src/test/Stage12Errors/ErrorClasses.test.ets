import { describe, beforeEach, it, expect } from '@ohos/hypium';
import { OrmError, ErrorContext } from '../../main/ets/errors/OrmError';
import { DatabaseError, ConnectionError } from '../../main/ets/errors/DatabaseError';
import { MetadataError, EntityNotRegisteredError } from '../../main/ets/errors/MetadataError';
import { QueryError, InvalidConditionError } from '../../main/ets/errors/QueryError';
import { MappingError, TypeConversionError } from '../../main/ets/errors/MappingError';
import { TransactionError, TransactionNotStartedError } from '../../main/ets/errors/TransactionError';
import { RelationNotFoundError } from '../../main/ets/errors/RelationError';
import { HookExecutionError } from '../../main/ets/errors/HookError';
import { SoftDeleteNotEnabledError } from '../../main/ets/errors/SoftDeleteError';
import { ValidationError, RequiredValidationError } from '../../main/ets/errors/ValidationError';
import { ERROR_ENTITY_NOT_REGISTERED, ERROR_DATABASE_CONNECTION_FAILED, ERROR_INVALID_CONDITION, ERROR_TYPE_CONVERSION_FAILED, ERROR_TRANSACTION_NOT_STARTED, ERROR_RELATION_NOT_FOUND, ERROR_HOOK_EXECUTION_FAILED, ERROR_SOFT_DELETE_NOT_ENABLED, ERROR_VALIDATION_REQUIRED } from '../../main/ets/errors/ErrorCodes';
import { setErrorLocale } from '../../main/ets/errors/ErrorLocale';

export default function errorClassesTest() {
  describe('errorClassesTest', () => {
    beforeEach(() => {
      setErrorLocale('zh');
    });

    it('OrmError should have correct code and context', 0, () => {
      const context = new ErrorContext();
      context.entityName = 'User';
      const error = new OrmError('test', 'TEST001', context);
      expect(error.code).assertEqual('TEST001');
      expect(error.context.entityName).assertEqual('User');
    });

    it('OrmError.getFullMessage should include code', 0, () => {
      const error = new OrmError('test', 'TEST001');
      expect(error.getFullMessage().includes('[TEST001]')).assertEqual(true);
    });

    it('EntityNotRegisteredError should have correct code', 0, () => {
      const error = new EntityNotRegisteredError('User');
      expect(error.code).assertEqual(ERROR_ENTITY_NOT_REGISTERED);
      expect(error instanceof MetadataError).assertEqual(true);
    });

    it('ConnectionError should have correct code', 0, () => {
      const error = new ConnectionError('db', 'reason');
      expect(error.code).assertEqual(ERROR_DATABASE_CONNECTION_FAILED);
      expect(error instanceof DatabaseError).assertEqual(true);
    });

    it('InvalidConditionError should have correct code', 0, () => {
      const error = new InvalidConditionError('col', 'reason');
      expect(error.code).assertEqual(ERROR_INVALID_CONDITION);
      expect(error instanceof QueryError).assertEqual(true);
    });

    it('TypeConversionError should have correct code', 0, () => {
      const error = new TypeConversionError('str', 'num', 'col');
      expect(error.code).assertEqual(ERROR_TYPE_CONVERSION_FAILED);
      expect(error instanceof MappingError).assertEqual(true);
    });

    it('TransactionNotStartedError should have correct code', 0, () => {
      const error = new TransactionNotStartedError();
      expect(error.code).assertEqual(ERROR_TRANSACTION_NOT_STARTED);
      expect(error instanceof TransactionError).assertEqual(true);
    });

    it('RelationNotFoundError should have correct code', 0, () => {
      const error = new RelationNotFoundError('User', 'posts');
      expect(error.code).assertEqual(ERROR_RELATION_NOT_FOUND);
    });

    it('HookExecutionError should have correct code', 0, () => {
      const error = new HookExecutionError('User', 'beforeSave', 'error');
      expect(error.code).assertEqual(ERROR_HOOK_EXECUTION_FAILED);
    });

    it('SoftDeleteNotEnabledError should have correct code', 0, () => {
      const error = new SoftDeleteNotEnabledError('User');
      expect(error.code).assertEqual(ERROR_SOFT_DELETE_NOT_ENABLED);
    });

    it('RequiredValidationError should have correct code', 0, () => {
      const error = new RequiredValidationError('User', 'name');
      expect(error.code).assertEqual(ERROR_VALIDATION_REQUIRED);
      expect(error instanceof ValidationError).assertEqual(true);
    });

    it('ErrorContext should have defaults', 0, () => {
      const context = new ErrorContext();
      expect(context.entityName).assertEqual('');
      expect(context.columnName).assertEqual('');
    });

    it('all errors should extend OrmError', 0, () => {
      const errors: OrmError[] = [
        new EntityNotRegisteredError('Test'),
        new ConnectionError('db', 'r'),
        new InvalidConditionError('c', 'r'),
        new TransactionNotStartedError(),
        new RequiredValidationError('E', 'c')
      ];
      for (let i = 0; i < errors.length; i++) {
        expect(errors[i] instanceof OrmError).assertEqual(true);
      }
    });
  });
}
