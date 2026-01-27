import { describe, it, expect } from '@ohos/hypium';
import {
  ERROR_ENTITY_NOT_REGISTERED, ERROR_DUPLICATE_ENTITY, ERROR_INVALID_COLUMN_TYPE,
  ERROR_COLUMN_NOT_FOUND, ERROR_PRIMARY_KEY_NOT_DEFINED, ERROR_INVALID_CONDITION,
  ERROR_PREDICATE_BUILD_FAILED, ERROR_INVALID_OPERATOR, ERROR_SUB_QUERY,
  ERROR_TYPE_CONVERSION_FAILED, ERROR_NULL_VALUE_NOT_ALLOWED, ERROR_MAPPING_FAILED,
  ERROR_TYPE_MISMATCH, ERROR_TRANSACTION_NOT_STARTED, ERROR_TRANSACTION_ROLLBACK,
  ERROR_TRANSACTION_COMMIT_FAILED, ERROR_DATABASE_CONNECTION_FAILED,
  ERROR_SQL_EXECUTION_FAILED, ERROR_DATABASE_NOT_INITIALIZED, ERROR_RELATION_NOT_FOUND,
  ERROR_INVALID_RELATION_TYPE, ERROR_INVALID_FOREIGN_KEY_SIDE, ERROR_JOIN_TABLE_NOT_FOUND,
  ERROR_HOOK_EXECUTION_FAILED, ERROR_SOFT_DELETE_NOT_ENABLED, ERROR_VALIDATION_FAILED,
  ERROR_VALIDATION_REQUIRED, ERROR_VALIDATION_LENGTH, ERROR_VALIDATION_EMAIL
} from '../../main/ets/errors/ErrorCodes';

export default function errorCodesTest() {
  describe('errorCodesTest', () => {
    it('metadata error codes should be correct', 0, () => {
      expect(ERROR_ENTITY_NOT_REGISTERED).assertEqual('ORM001');
      expect(ERROR_DUPLICATE_ENTITY).assertEqual('ORM002');
      expect(ERROR_PRIMARY_KEY_NOT_DEFINED).assertEqual('ORM005');
    });

    it('query error codes should be correct', 0, () => {
      expect(ERROR_INVALID_CONDITION).assertEqual('ORM101');
      expect(ERROR_PREDICATE_BUILD_FAILED).assertEqual('ORM102');
    });

    it('mapping error codes should be correct', 0, () => {
      expect(ERROR_TYPE_CONVERSION_FAILED).assertEqual('ORM201');
      expect(ERROR_NULL_VALUE_NOT_ALLOWED).assertEqual('ORM202');
    });

    it('transaction error codes should be correct', 0, () => {
      expect(ERROR_TRANSACTION_NOT_STARTED).assertEqual('ORM301');
    });

    it('database error codes should be correct', 0, () => {
      expect(ERROR_DATABASE_CONNECTION_FAILED).assertEqual('ORM401');
      expect(ERROR_DATABASE_NOT_INITIALIZED).assertEqual('ORM403');
    });

    it('relation error codes should be correct', 0, () => {
      expect(ERROR_RELATION_NOT_FOUND).assertEqual('ORM501');
    });

    it('hook and soft delete error codes should be correct', 0, () => {
      expect(ERROR_HOOK_EXECUTION_FAILED).assertEqual('ORM601');
      expect(ERROR_SOFT_DELETE_NOT_ENABLED).assertEqual('ORM701');
    });

    it('validation error codes should be correct', 0, () => {
      expect(ERROR_VALIDATION_FAILED).assertEqual('ORM801');
      expect(ERROR_VALIDATION_REQUIRED).assertEqual('ORM802');
    });

    it('all error codes should start with ORM', 0, () => {
      expect(ERROR_ENTITY_NOT_REGISTERED.startsWith('ORM')).assertEqual(true);
      expect(ERROR_VALIDATION_EMAIL.startsWith('ORM')).assertEqual(true);
    });
  });
}
