/**
 * 关联关系错误类
 * 用于处理关联关系相关的错误
 */

import { OrmError, ErrorContext } from './OrmError'
import {
  ERROR_RELATION_NOT_FOUND,
  ERROR_INVALID_RELATION_TYPE,
  ERROR_INVALID_FOREIGN_KEY_SIDE,
  ERROR_JOIN_TABLE_NOT_FOUND
} from './ErrorCodes'

/**
 * 关联关系未找到错误
 * 当查询时指定的关联关系未注册时抛出
 */
export class RelationNotFoundError extends OrmError {
  /**
   * 构造函数
   * @param entityName 实体名称
   * @param relationName 关联关系名称
   */
  constructor(entityName: string, relationName: string) {
    const context = new ErrorContext()
    context.entityName = entityName
    context.details = `关联关系 '${relationName}' 未注册`
    super(`实体 '${entityName}' 的关联关系 '${relationName}' 未找到`, ERROR_RELATION_NOT_FOUND, context)
    this.name = 'RelationNotFoundError'
  }
}

/**
 * 无效关系类型错误
 * 当注册的关系类型无效时抛出
 */
export class InvalidRelationTypeError extends OrmError {
  /**
   * 构造函数
   * @param relationType 无效的关系类型
   */
  constructor(relationType: string) {
    const context = new ErrorContext()
    context.details = `无效的关系类型: ${relationType}`
    super(`无效的关系类型: '${relationType}'，仅支持 ONE_TO_ONE、ONE_TO_MANY、MANY_TO_ONE、MANY_TO_MANY 和 MORPH_TO`, ERROR_INVALID_RELATION_TYPE, context)
    this.name = 'InvalidRelationTypeError'
  }
}

/**
 * 无效外键位置错误
 * 当 ONE_TO_ONE 关系的 foreignKeySide 配置无效时抛出
 */
export class InvalidForeignKeySideError extends OrmError {
  /**
   * 构造函数
   * @param foreignKeySide 无效的外键位置配置
   */
  constructor(foreignKeySide: string) {
    const context = new ErrorContext()
    context.operation = '配置外键位置'
    context.details = `无效的外键位置: ${foreignKeySide}`
    super(`无效的外键位置配置: '${foreignKeySide}'，有效值为 'source' 或 'target'`, ERROR_INVALID_FOREIGN_KEY_SIDE, context)
    this.name = 'InvalidForeignKeySideError'
  }
}

/**
 * 中间表未找到错误
 * 当多对多关联的中间表不存在时抛出
 */
export class JoinTableNotFoundError extends OrmError {
  /**
   * 构造函数
   * @param joinTable 中间表名称
   */
  constructor(joinTable: string) {
    const context = new ErrorContext()
    context.tableName = joinTable
    context.operation = '加载多对多关联'
    context.details = `中间表 '${joinTable}' 不存在`
    super(`多对多关联中间表 '${joinTable}' 未找到`, ERROR_JOIN_TABLE_NOT_FOUND, context)
    this.name = 'JoinTableNotFoundError'
  }
}
