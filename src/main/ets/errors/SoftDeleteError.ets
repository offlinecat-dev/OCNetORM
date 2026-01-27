/**
 * 软删除错误类
 * 用于处理软删除功能相关的错误
 */

import { OrmError, ErrorContext } from './OrmError'
import { ERROR_SOFT_DELETE_NOT_ENABLED } from './ErrorCodes'

/**
 * 软删除未启用错误
 * 当对未启用软删除的实体调用 restore 方法时抛出
 */
export class SoftDeleteNotEnabledError extends OrmError {
  /**
   * 构造函数
   * @param entityName 实体名称
   */
  constructor(entityName: string) {
    const context = new ErrorContext()
    context.entityName = entityName
    context.details = '该实体未启用软删除功能'
    super(`实体 '${entityName}' 未启用软删除功能，无法执行恢复操作`, ERROR_SOFT_DELETE_NOT_ENABLED, context)
    this.name = 'SoftDeleteNotEnabledError'
  }
}
