export { MainPage } from './src/main/ets/components/MainPage';

// 导出错误模块
export {
  // 错误码
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
  // 错误国际化
  ErrorLocale,
  ErrorLocaleMessages,
  setErrorLocale,
  getErrorLocale,
  registerErrorLocaleMessages,
  formatErrorMessage,
  sanitizeErrorMessage,
  sanitizeSqlPreview,
  // 基础错误类
  OrmError,
  ErrorContext,
  // 元数据错误
  MetadataError,
  EntityNotRegisteredError,
  DuplicateEntityError,
  InvalidColumnTypeError,
  ColumnNotFoundError,
  PrimaryKeyNotDefinedError,
  // 查询错误
  QueryError,
  InvalidConditionError,
  PredicateBuildError,
  InvalidOperatorError,
  SubQueryError,
  // 映射错误
  MappingError,
  TypeConversionError,
  NullValueError,
  EntityMappingError,
  TypeMismatchError,
  // 事务错误
  TransactionError,
  TransactionNotStartedError,
  TransactionRollbackError,
  TransactionCommitError,
  // 数据库错误
  DatabaseError,
  ConnectionError,
  ExecutionError,
  DatabaseNotInitializedError,
  // 关联关系错误
  RelationNotFoundError,
  InvalidRelationTypeError,
  InvalidForeignKeySideError,
  JoinTableNotFoundError,
  // 钩子错误
  HookExecutionError,
  // 软删除错误
  SoftDeleteNotEnabledError,
  // 验证错误
  ValidationError,
  RequiredValidationError,
  LengthValidationError,
  EmailValidationError,
  EntityValidationError
} from './src/main/ets/errors/index'

// 导出类型定义模块
export {
  // 列类型枚举
  ColumnType,
  // 条件操作符枚举
  ConditionOperator,
  // 值类型
  ValueType,
  DbValueType,
  SortDirection,
  OrderByClause,
  // 实体注册相关
  EntityInfo,
  EntityRegistry,
  // 关系类型枚举
  RelationType,
  // 实体钩子
  HookCallback,
  EntityHooks,
  // 列定义基类
  ColumnDef
} from './src/main/ets/types/index'

// 导出核心模块
export {
  // 列元数据
  ColumnMetadata,
  // 实体元数据
  EntityMetadata,
  // 元数据存储
  MetadataStorage,
  // 关系元数据
  RelationMetadata,
  CascadeOptions,
  CascadeSetting,
  // 多对多关系元数据
  ManyToManyMetadata,
  // 钩子处理器
  HooksProcessor,
  // ORM 上下文（依赖注入）
  OrmContext,
  OrmContextConfig,
  // 统一初始化入口
  OCORMInit,
  OCORMInitOptions,
  // 快速实体注册工具
  defineEntity,
  EntitySchema,
  ColumnSchema,
  SoftDeleteSchema
} from './src/main/ets/core/index'

// 导出装饰器模块
export {
  // 实体装饰器
  EntityOptions,
  registerEntity,
  createEntityOptions,
  Table,
  // 列装饰器
  ColumnOptions,
  DecoratorColumnOptions,
  PrimaryKeyOptions,
  registerColumn,
  registerPrimaryKey,
  registerAutoIncrementPrimaryKey,
  createColumnOptions,
  Column,
  PrimaryKey,
  CreatedAt,
  UpdatedAt,
  SoftDelete,
  inferColumnType
} from './src/main/ets/decorators/index'

// 导出 Schema 层模块
export {
  // Schema 构建器
  SchemaBuilder,
  CreateTableResult,
  CreateAllTablesResult,
  SchemaInspector,
  ColumnInfo,
  TableInfo,
  SchemaDiffer,
  SchemaDiffResult,
  SchemaChange,
  SchemaChangeType,
  // 迁移相关
  Migration,
  MigrationResult,
  MigrationDirection,
  MigrationLogManager,
  MigrationLogRecord,
  MigrationManager,
  MigrationExecutionResult,
  MigrationManagerOptions,
  AutoMigrationMode,
  AutoMigrationOptions,
  SchemaMigrationExecutionResult
} from './src/main/ets/schema/index'

// 导出映射层模块
export {
  // 类型转换器
  TypeConverter,
  TypeConversionOptions,
  // 数据映射器
  ValuesBucket,
  EntityPropertyValue,
  RelatedDataValue,
  EntityData,
  ResultSetRow,
  DataMapper,
  // 实体数据输入
  EntityDataInput,
  // 泛型实体数据
  TypedEntityData,
  // ViewModel 映射器
  PropertyMapper,
  ReversePropertyMapper,
  ViewModelFactory,
  ViewModelMappingConfig,
  ViewModelMapper,
  // ResultSet 工具类
  ResultSetUtils
} from './src/main/ets/mapping/index'

// 导出查询层模块
export {
  // 查询条件
  WhereCondition,
  LogicalOperator,
  // 查询构建器
  QueryBuilder,
  // 子查询构建器
  SubQuery,
  SubQueryCallback,
  // RdbPredicates 构建器
  PredicateBuilder,
  PredicateBuildResult,
  // 查询执行器
  QueryExecutor,
  // 关联数据加载器
  RelationLoader,
  // 分页相关
  PaginationParams,
  PaginatedResult,
  // 关联加载结果
  RelationLoadResult,
  ParallelRelationLoadResult,
  // TaskPool 数据转换任务
  TransformTaskParams,
  TransformTaskResult,
  TransformedEntityItem,
  RowData,
  // 查询缓存
  QueryCache,
  CacheEntry,
  QueryCacheConfig,
  CacheStatistics
} from './src/main/ets/query/index'

// 导出数据库模块
export {
  // 数据库配置
  DatabaseConfig,
  // 数据库管理器
  DatabaseManager
} from './src/main/ets/database/index'

// 导出仓库模块
export {
  // 仓库类
  Repository,
  SaveResult,
  DeleteResult,
  TransactionResult,
  TransactionCallback,
  // 批量插入相关
  BatchInsertOptions,
  BatchInsertResult,
  // 事务选项
  TransactionOptions,
  TransactionOptionsConfig,
  IsolationLevel,
  // 级联处理器
  CascadeHandler,
  CascadeOperation,
  CascadeRepository,
  CascadeRepositoryFactory,
  CascadeResultLike
} from './src/main/ets/repository/index'

// 导出日志模块
export {
  // 日志级别
  LogLevel,
  // 日志类
  Logger
} from './src/main/ets/logging/index'

// 导出验证模块
export {
  ValidationMetadataStorage,
  ValidationRuleType,
  ValidationRule,
  Required,
  Length,
  Email,
  LengthOptions,
  EntityValidator,
  ValidationResult
} from './src/main/ets/validation/index'
