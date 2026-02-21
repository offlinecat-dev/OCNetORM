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
 * 钩子名称
 */
export type HookName =
  'beforeSave' |
  'afterLoad' |
  'beforeDelete' |
  'beforeInsert' |
  'afterInsert' |
  'beforeUpdate' |
  'afterUpdate' |
  'afterDelete' |
  'afterSave' |
  'beforeRestore' |
  'afterRestore'

/**
 * 全局钩子回调
 * 接收实体名与实体数据
 */
export type GlobalHookCallback = (entityName: string, data: EntityData) => void | Promise<void>

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
  /** 插入前钩子 */
  beforeInsert: HookCallback | null = null
  /** 插入后钩子 */
  afterInsert: HookCallback | null = null
  /** 更新前钩子 */
  beforeUpdate: HookCallback | null = null
  /** 更新后钩子 */
  afterUpdate: HookCallback | null = null
  /** 删除后钩子 */
  afterDelete: HookCallback | null = null
  /** 保存后钩子 */
  afterSave: HookCallback | null = null
  /** 恢复前钩子 */
  beforeRestore: HookCallback | null = null
  /** 恢复后钩子 */
  afterRestore: HookCallback | null = null

  /**
   * 构造函数
   * @param beforeSave 保存前钩子
   * @param afterLoad 加载后钩子
   * @param beforeDelete 删除前钩子
   * @param beforeInsert 插入前钩子
   * @param afterInsert 插入后钩子
   * @param beforeUpdate 更新前钩子
   * @param afterUpdate 更新后钩子
   * @param afterDelete 删除后钩子
   * @param afterSave 保存后钩子
   * @param beforeRestore 恢复前钩子
   * @param afterRestore 恢复后钩子
   */
  constructor(
    beforeSave?: HookCallback | null,
    afterLoad?: HookCallback | null,
    beforeDelete?: HookCallback | null,
    beforeInsert?: HookCallback | null,
    afterInsert?: HookCallback | null,
    beforeUpdate?: HookCallback | null,
    afterUpdate?: HookCallback | null,
    afterDelete?: HookCallback | null,
    afterSave?: HookCallback | null,
    beforeRestore?: HookCallback | null,
    afterRestore?: HookCallback | null
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
    if (beforeInsert !== undefined) {
      this.beforeInsert = beforeInsert
    }
    if (afterInsert !== undefined) {
      this.afterInsert = afterInsert
    }
    if (beforeUpdate !== undefined) {
      this.beforeUpdate = beforeUpdate
    }
    if (afterUpdate !== undefined) {
      this.afterUpdate = afterUpdate
    }
    if (afterDelete !== undefined) {
      this.afterDelete = afterDelete
    }
    if (afterSave !== undefined) {
      this.afterSave = afterSave
    }
    if (beforeRestore !== undefined) {
      this.beforeRestore = beforeRestore
    }
    if (afterRestore !== undefined) {
      this.afterRestore = afterRestore
    }
  }
}
