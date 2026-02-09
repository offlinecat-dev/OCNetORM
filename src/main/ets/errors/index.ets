/**
 * 错误模块统一导出
 */

// 错误码
export {
  ERROR_ENTITY_NOT_REGISTERED,
  ERROR_DUPLICATE_ENTITY,
  ERROR_INVALID_COLUMN_TYPE,
  ERROR_COLUMN_NOT_FOUND,
  ERROR_PRIMARY_KEY_NOT_DEFINED,
  ERROR_INVALID_CONDITION,
  ERROR_PREDICATE_BUILD_FAILED,
  ERROR_INVALID_OPERATOR,
  ERROR_SUB_QUERY,
  ERROR_TYPE_CONVERSION_FAILED,
  ERROR_NULL_VALUE_NOT_ALLOWED,
  ERROR_MAPPING_FAILED,
  ERROR_TYPE_MISMATCH,
  ERROR_TRANSACTION_NOT_STARTED,
  ERROR_TRANSACTION_ROLLBACK,
  ERROR_TRANSACTION_COMMIT_FAILED,
  ERROR_DATABASE_CONNECTION_FAILED,
  ERROR_SQL_EXECUTION_FAILED,
  ERROR_DATABASE_NOT_INITIALIZED,
  ERROR_RELATION_NOT_FOUND,
  ERROR_INVALID_RELATION_TYPE,
  ERROR_INVALID_FOREIGN_KEY_SIDE,
  ERROR_JOIN_TABLE_NOT_FOUND,
  ERROR_HOOK_EXECUTION_FAILED,
  ERROR_SOFT_DELETE_NOT_ENABLED,
  ERROR_VALIDATION_FAILED,
  ERROR_VALIDATION_REQUIRED,
  ERROR_VALIDATION_LENGTH,
  ERROR_VALIDATION_EMAIL,
  ERROR_VALIDATION_MIN,
  ERROR_VALIDATION_MAX,
  ERROR_VALIDATION_RANGE,
  ERROR_VALIDATION_PATTERN,
  ERROR_VALIDATION_URL,
  ERROR_VALIDATION_PHONE,
  ERROR_VALIDATION_DATE,
  ERROR_VALIDATION_ENUM,
  ERROR_VALIDATION_CUSTOM,
  ERROR_VALIDATION_UNIQUE
} from './ErrorCodes'

// 错误国际化
export {
  ErrorLocale,
  ErrorLocaleMessages,
  setErrorLocale,
  getErrorLocale,
  registerErrorLocaleMessages,
  formatErrorMessage
} from './ErrorLocale'

// 基础错误类
export { OrmError, ErrorContext } from './OrmError'
export { sanitizeErrorMessage, sanitizeSqlPreview } from './ErrorSanitizer'

// 元数据错误
export {
  MetadataError,
  EntityNotRegisteredError,
  DuplicateEntityError,
  InvalidColumnTypeError,
  ColumnNotFoundError,
  PrimaryKeyNotDefinedError
} from './MetadataError'

// 查询错误
export {
  QueryError,
  InvalidConditionError,
  PredicateBuildError,
  InvalidOperatorError,
  SubQueryError,
  ScopeNotFoundError
} from './QueryError'

// 映射错误
export {
  MappingError,
  TypeConversionError,
  NullValueError,
  EntityMappingError,
  TypeMismatchError
} from './MappingError'

// 事务错误
export {
  TransactionError,
  TransactionNotStartedError,
  TransactionRollbackError,
  TransactionCommitError
} from './TransactionError'

// 数据库错误
export {
  DatabaseError,
  ConnectionError,
  ExecutionError,
  DatabaseNotInitializedError
} from './DatabaseError'

// 关联关系错误
export {
  RelationNotFoundError,
  InvalidRelationTypeError,
  InvalidForeignKeySideError,
  JoinTableNotFoundError
} from './RelationError'

// 钩子错误
export { HookExecutionError } from './HookError'

// 软删除错误
export { SoftDeleteNotEnabledError } from './SoftDeleteError'

// 验证错误
export {
  ValidationError,
  RequiredValidationError,
  LengthValidationError,
  EmailValidationError,
  MinValidationError,
  MaxValidationError,
  RangeValidationError,
  PatternValidationError,
  UrlValidationError,
  PhoneValidationError,
  DateValidationError,
  EnumValidationError,
  CustomValidationError,
  UniqueValidationError,
  EntityValidationError
} from './ValidationError'
