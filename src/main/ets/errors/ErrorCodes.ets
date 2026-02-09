/**
 * ORM 错误码常量定义
 * 用于标识不同类型的错误
 */

// 元数据错误码 (ORM001-ORM099)
export const ERROR_ENTITY_NOT_REGISTERED: string = 'ORM001'
export const ERROR_DUPLICATE_ENTITY: string = 'ORM002'
export const ERROR_INVALID_COLUMN_TYPE: string = 'ORM003'
export const ERROR_COLUMN_NOT_FOUND: string = 'ORM004'
export const ERROR_PRIMARY_KEY_NOT_DEFINED: string = 'ORM005'

// 查询错误码 (ORM101-ORM199)
export const ERROR_INVALID_CONDITION: string = 'ORM101'
export const ERROR_PREDICATE_BUILD_FAILED: string = 'ORM102'
export const ERROR_INVALID_OPERATOR: string = 'ORM103'
export const ERROR_SUB_QUERY: string = 'ORM104'

// 映射错误码 (ORM201-ORM299)
export const ERROR_TYPE_CONVERSION_FAILED: string = 'ORM201'
export const ERROR_NULL_VALUE_NOT_ALLOWED: string = 'ORM202'
export const ERROR_MAPPING_FAILED: string = 'ORM203'
export const ERROR_TYPE_MISMATCH: string = 'ORM204'

// 事务错误码 (ORM301-ORM399)
export const ERROR_TRANSACTION_NOT_STARTED: string = 'ORM301'
export const ERROR_TRANSACTION_ROLLBACK: string = 'ORM302'
export const ERROR_TRANSACTION_COMMIT_FAILED: string = 'ORM303'

// 数据库错误码 (ORM401-ORM499)
export const ERROR_DATABASE_CONNECTION_FAILED: string = 'ORM401'
export const ERROR_SQL_EXECUTION_FAILED: string = 'ORM402'
export const ERROR_DATABASE_NOT_INITIALIZED: string = 'ORM403'

// 关联关系错误码 (ORM501-ORM599)
export const ERROR_RELATION_NOT_FOUND: string = 'ORM501'
export const ERROR_INVALID_RELATION_TYPE: string = 'ORM502'
export const ERROR_INVALID_FOREIGN_KEY_SIDE: string = 'ORM503'
export const ERROR_JOIN_TABLE_NOT_FOUND: string = 'ORM504'

// 钩子错误码 (ORM601-ORM699)
export const ERROR_HOOK_EXECUTION_FAILED: string = 'ORM601'

// 软删除错误码 (ORM701-ORM799)
export const ERROR_SOFT_DELETE_NOT_ENABLED: string = 'ORM701'

// 验证错误码 (ORM801-ORM899)
export const ERROR_VALIDATION_FAILED: string = 'ORM801'
export const ERROR_VALIDATION_REQUIRED: string = 'ORM802'
export const ERROR_VALIDATION_LENGTH: string = 'ORM803'
export const ERROR_VALIDATION_EMAIL: string = 'ORM804'
export const ERROR_VALIDATION_MIN: string = 'ORM805'
export const ERROR_VALIDATION_MAX: string = 'ORM806'
export const ERROR_VALIDATION_RANGE: string = 'ORM807'
export const ERROR_VALIDATION_PATTERN: string = 'ORM808'
export const ERROR_VALIDATION_URL: string = 'ORM809'
export const ERROR_VALIDATION_PHONE: string = 'ORM810'
export const ERROR_VALIDATION_DATE: string = 'ORM811'
export const ERROR_VALIDATION_ENUM: string = 'ORM812'
export const ERROR_VALIDATION_CUSTOM: string = 'ORM813'
export const ERROR_VALIDATION_UNIQUE: string = 'ORM814'
