/**
 * 仓库模块统一导出
 */

// 仓库类
export { Repository, SaveResult, DeleteResult, TransactionResult, TransactionCallback } from './Repository'

// 批量插入相关
export { BatchInsertOptions } from './BatchInsertOptions'
export { BatchInsertResult } from './BatchInsertResult'

// 事务选项
export { TransactionOptions, TransactionOptionsConfig, IsolationLevel } from './TransactionOptions'

// 级联处理器
export { CascadeHandler, CascadeOperation, CascadeRepository, CascadeRepositoryFactory, CascadeResultLike } from './CascadeHandler'
