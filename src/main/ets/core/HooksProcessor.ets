/**
 * 钩子处理器
 * 管理和执行实体生命周期钩子
 */

import { EntityData } from '../mapping/EntityData'
import { MetadataStorage } from './MetadataStorage'
import { EntityHooks, HookCallback, HookName, GlobalHookCallback } from '../types/EntityHooks'
import { HookExecutionError } from '../errors/HookError'

/**
 * 钩子处理器类
 * 负责执行实体的生命周期钩子函数
 */
export class HooksProcessor {
  /** 单例实例 */
  private static instance: HooksProcessor = new HooksProcessor()
  /** 全局钩子注册表 */
  private globalHooks: Map<HookName, Array<GlobalHookCallback>> = new Map()

  /**
   * 私有构造函数，防止外部实例化
   */
  private constructor() {
    this.initializeGlobalHooks()
  }

  private initializeGlobalHooks(): void {
    this.globalHooks.set('beforeSave', [])
    this.globalHooks.set('afterLoad', [])
    this.globalHooks.set('beforeDelete', [])
    this.globalHooks.set('beforeInsert', [])
    this.globalHooks.set('afterInsert', [])
    this.globalHooks.set('beforeUpdate', [])
    this.globalHooks.set('afterUpdate', [])
    this.globalHooks.set('afterDelete', [])
    this.globalHooks.set('afterSave', [])
    this.globalHooks.set('beforeRestore', [])
    this.globalHooks.set('afterRestore', [])
  }

  /**
   * 获取单例实例
   * @returns HooksProcessor 实例
   */
  static getInstance(): HooksProcessor {
    return HooksProcessor.instance
  }

  /**
   * 重置单例实例（主要用于测试）
   */
  static resetInstance(): void {
    HooksProcessor.instance = new HooksProcessor()
  }

  registerGlobalHook(hookName: HookName, callback: GlobalHookCallback): void {
    const callbacks = this.globalHooks.get(hookName)
    if (callbacks === undefined) {
      this.globalHooks.set(hookName, [callback])
      return
    }
    callbacks.push(callback)
  }

  clearGlobalHooks(hookName?: HookName): void {
    if (hookName !== undefined) {
      const callbacks = this.globalHooks.get(hookName)
      if (callbacks !== undefined) {
        callbacks.splice(0, callbacks.length)
      }
      return
    }
    this.globalHooks.forEach((callbacks) => {
      callbacks.splice(0, callbacks.length)
    })
  }

  /**
   * 获取实体的钩子配置
   * @param entityName 实体名称
   * @returns 实体钩子配置，如果不存在返回 null
   */
  private getHooks(entityName: string): EntityHooks | null {
    const metadata = MetadataStorage.getInstance().getEntityMetadata(entityName)
    if (metadata === null) {
      return null
    }
    return metadata.getHooks()
  }

  private resolveErrorMessage(error: Error | Object | string): string {
    if (error instanceof Error) {
      return error.message
    }
    if (typeof error === 'string') {
      return error
    }
    return '未知错误'
  }


  /**
   * 执行钩子回调
   * 支持同步和异步钩子，等待 Promise 完成
   * @param callback 钩子回调函数
   * @param data 实体数据
   * @param entityName 实体名称
   * @param hookName 钩子名称
   */
  private async executeCallback(
    callback: HookCallback,
    data: EntityData,
    entityName: string,
    hookName: HookName
  ): Promise<void> {
    try {
      const result = callback(data)
      // 如果返回 Promise，等待其完成
      if (result instanceof Promise) {
        await result
      }
    } catch (error) {
      throw new HookExecutionError(entityName, hookName, this.resolveErrorMessage(error))
    }
  }

  private async executeGlobalCallback(
    callback: GlobalHookCallback,
    data: EntityData,
    entityName: string,
    hookName: HookName
  ): Promise<void> {
    try {
      const result = callback(entityName, data)
      if (result instanceof Promise) {
        await result
      }
    } catch (error) {
      throw new HookExecutionError(entityName, hookName, this.resolveErrorMessage(error))
    }
  }

  private async executeGlobalHooks(hookName: HookName, entityName: string, data: EntityData): Promise<void> {
    const callbacks = this.globalHooks.get(hookName)
    if (callbacks === undefined || callbacks.length === 0) {
      return
    }
    for (let i = 0; i < callbacks.length; i++) {
      await this.executeGlobalCallback(callbacks[i], data, entityName, hookName)
    }
  }

  private getEntityHookCallback(hooks: EntityHooks | null, hookName: HookName): HookCallback | null {
    if (hooks === null) {
      return null
    }
    switch (hookName) {
      case 'beforeSave':
        return hooks.beforeSave
      case 'afterLoad':
        return hooks.afterLoad
      case 'beforeDelete':
        return hooks.beforeDelete
      case 'beforeInsert':
        return hooks.beforeInsert
      case 'afterInsert':
        return hooks.afterInsert
      case 'beforeUpdate':
        return hooks.beforeUpdate
      case 'afterUpdate':
        return hooks.afterUpdate
      case 'afterDelete':
        return hooks.afterDelete
      case 'afterSave':
        return hooks.afterSave
      case 'beforeRestore':
        return hooks.beforeRestore
      case 'afterRestore':
        return hooks.afterRestore
      default:
        return null
    }
  }

  private async executeHook(entityName: string, data: EntityData, hookName: HookName): Promise<void> {
    const hooks = this.getHooks(entityName)
    const callback = this.getEntityHookCallback(hooks, hookName)
    const isBeforeHook = hookName.startsWith('before')
    if (isBeforeHook) {
      await this.executeGlobalHooks(hookName, entityName, data)
      if (callback !== null) {
        await this.executeCallback(callback, data, entityName, hookName)
      }
      return
    }
    if (callback !== null) {
      await this.executeCallback(callback, data, entityName, hookName)
    }
    await this.executeGlobalHooks(hookName, entityName, data)
  }

  /**
   * 执行 beforeSave 钩子
   * 在保存实体数据到数据库之前调用
   * @param entityName 实体名称
   * @param data 实体数据
   * @throws HookExecutionError 如果钩子执行失败
   */
  async executeBeforeSave(entityName: string, data: EntityData): Promise<void> {
    await this.executeHook(entityName, data, 'beforeSave')
  }

  /**
   * 执行 afterLoad 钩子
   * 在从数据库加载实体数据之后调用
   * @param entityName 实体名称
   * @param data 实体数据
   * @throws HookExecutionError 如果钩子执行失败
   */
  async executeAfterLoad(entityName: string, data: EntityData): Promise<void> {
    await this.executeHook(entityName, data, 'afterLoad')
  }

  /**
   * 执行 beforeDelete 钩子
   * 在删除实体数据之前调用
   * @param entityName 实体名称
   * @param data 实体数据
   * @throws HookExecutionError 如果钩子执行失败
   */
  async executeBeforeDelete(entityName: string, data: EntityData): Promise<void> {
    await this.executeHook(entityName, data, 'beforeDelete')
  }

  async executeBeforeInsert(entityName: string, data: EntityData): Promise<void> {
    await this.executeHook(entityName, data, 'beforeInsert')
  }

  async executeAfterInsert(entityName: string, data: EntityData): Promise<void> {
    await this.executeHook(entityName, data, 'afterInsert')
  }

  async executeBeforeUpdate(entityName: string, data: EntityData): Promise<void> {
    await this.executeHook(entityName, data, 'beforeUpdate')
  }

  async executeAfterUpdate(entityName: string, data: EntityData): Promise<void> {
    await this.executeHook(entityName, data, 'afterUpdate')
  }

  async executeAfterDelete(entityName: string, data: EntityData): Promise<void> {
    await this.executeHook(entityName, data, 'afterDelete')
  }

  async executeAfterSave(entityName: string, data: EntityData): Promise<void> {
    await this.executeHook(entityName, data, 'afterSave')
  }

  async executeBeforeRestore(entityName: string, data: EntityData): Promise<void> {
    await this.executeHook(entityName, data, 'beforeRestore')
  }

  async executeAfterRestore(entityName: string, data: EntityData): Promise<void> {
    await this.executeHook(entityName, data, 'afterRestore')
  }

  /**
   * 批量执行 afterLoad 钩子
   * 用于查询返回多条记录时
   * @param entityName 实体名称
   * @param dataList 实体数据数组
   * @throws HookExecutionError 如果钩子执行失败
   */
  async executeAfterLoadBatch(entityName: string, dataList: Array<EntityData>): Promise<void> {
    for (let i = 0; i < dataList.length; i++) {
      await this.executeAfterLoad(entityName, dataList[i])
    }
  }

  private hasHook(entityName: string, hookName: HookName): boolean {
    const hooks = this.getHooks(entityName)
    const callback = this.getEntityHookCallback(hooks, hookName)
    return callback !== null
  }

  /**
   * 检查实体是否有 beforeSave 钩子
   * @param entityName 实体名称
   * @returns 是否有 beforeSave 钩子
   */
  hasBeforeSaveHook(entityName: string): boolean {
    return this.hasHook(entityName, 'beforeSave')
  }

  /**
   * 检查实体是否有 afterLoad 钩子
   * @param entityName 实体名称
   * @returns 是否有 afterLoad 钩子
   */
  hasAfterLoadHook(entityName: string): boolean {
    return this.hasHook(entityName, 'afterLoad')
  }

  /**
   * 检查实体是否有 beforeDelete 钩子
   * @param entityName 实体名称
   * @returns 是否有 beforeDelete 钩子
   */
  hasBeforeDeleteHook(entityName: string): boolean {
    return this.hasHook(entityName, 'beforeDelete')
  }

  /**
   * 检查实体是否有任何钩子
   * @param entityName 实体名称
   * @returns 是否有任何钩子
   */
  hasAnyHook(entityName: string): boolean {
    return this.hasHook(entityName, 'beforeSave') ||
      this.hasHook(entityName, 'afterLoad') ||
      this.hasHook(entityName, 'beforeDelete') ||
      this.hasHook(entityName, 'beforeInsert') ||
      this.hasHook(entityName, 'afterInsert') ||
      this.hasHook(entityName, 'beforeUpdate') ||
      this.hasHook(entityName, 'afterUpdate') ||
      this.hasHook(entityName, 'afterDelete') ||
      this.hasHook(entityName, 'afterSave') ||
      this.hasHook(entityName, 'beforeRestore') ||
      this.hasHook(entityName, 'afterRestore')
  }
}
