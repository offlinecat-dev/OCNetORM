/**
 * 实体生命周期钩子类型定义
 * 定义实体在保存、加载、删除等操作前后的回调函数
 */

import { EntityData } from '../mapping/EntityData'

/**
 * 钩子回调函数类型
 * 接收 EntityData 参数，可以返回 void 或 Promise<void>
 */
export type HookCallback = (data: EntityData) => void | Promise<void>

/**
 * 实体钩子类
 * 定义实体生命周期的回调函数
 */
export class EntityHooks {
  /** 保存前钩子 */
  beforeSave: HookCallback | null = null
  /** 加载后钩子 */
  afterLoad: HookCallback | null = null
  /** 删除前钩子 */
  beforeDelete: HookCallback | null = null

  /**
   * 构造函数
   * @param beforeSave 保存前钩子
   * @param afterLoad 加载后钩子
   * @param beforeDelete 删除前钩子
   */
  constructor(
    beforeSave?: HookCallback | null,
    afterLoad?: HookCallback | null,
    beforeDelete?: HookCallback | null
  ) {
    if (beforeSave !== undefined) {
      this.beforeSave = beforeSave
    }
    if (afterLoad !== undefined) {
      this.afterLoad = afterLoad
    }
    if (beforeDelete !== undefined) {
      this.beforeDelete = beforeDelete
    }
  }
}
