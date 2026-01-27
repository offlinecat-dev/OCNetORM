/**
 * 查询层模块统一导出
 */

// 查询条件
export { WhereCondition, LogicalOperator } from './WhereCondition'

// 查询构建器
export { QueryBuilder } from './QueryBuilder'

// 子查询构建器
export { SubQuery, SubQueryCallback } from './SubQuery'

// RdbPredicates 构建器
export { PredicateBuilder, PredicateBuildResult } from './PredicateBuilder'

// 查询执行器
export { QueryExecutor } from './QueryExecutor'

// 关联数据加载器
export { RelationLoader } from './RelationLoader'

// 分页相关
export { PaginationParams } from './PaginationParams'
export { PaginatedResult } from './PaginatedResult'

// 关联加载结果
export { RelationLoadResult, ParallelRelationLoadResult } from './RelationLoadResult'

// TaskPool 数据转换任务
export { TransformTaskParams, TransformTaskResult, TransformedEntityItem, RowData } from './DataTransformTask'

// 查询缓存
export { QueryCache, CacheEntry, QueryCacheConfig, CacheStatistics } from './QueryCache'
