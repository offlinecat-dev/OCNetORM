/**
 * 钩子处理器
 * 管理和执行实体生命周期钩子
 */

import { EntityData } from '../mapping/DataMapper'
import { MetadataStorage } from './MetadataStorage'
import { EntityHooks, HookCallback } from '../types/EntityHooks'
import { HookExecutionError } from '../errors/HookError'

/**
 * 钩子处理器类
 * 负责执行实体的生命周期钩子函数
 */
export class HooksProcessor {
  /** 单例实例 */
  private static instance: HooksProcessor | null = null

  /**
   * 私有构造函数，防止外部实例化
   */
  private constructor() {
  }

  /**
   * 获取单例实例
   * @returns HooksProcessor 实例
   */
  static getInstance(): HooksProcessor {
    if (HooksProcessor.instance === null) {
      HooksProcessor.instance = new HooksProcessor()
    }
    return HooksProcessor.instance
  }

  /**
   * 重置单例实例（主要用于测试）
   */
  static resetInstance(): void {
    HooksProcessor.instance = null
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
    hookName: string
  ): Promise<void> {
    try {
      const result = callback(data)
      // 如果返回 Promise，等待其完成
      if (result instanceof Promise) {
        await result
      }
    } catch (error) {
      // 将错误转换为字符串
      let errorMessage = '未知错误'
      if (error instanceof Error) {
        errorMessage = error.message
      } else if (typeof error === 'string') {
        errorMessage = error
      }
      throw new HookExecutionError(entityName, hookName, errorMessage)
    }
  }

  /**
   * 执行 beforeSave 钩子
   * 在保存实体数据到数据库之前调用
   * @param entityName 实体名称
   * @param data 实体数据
   * @throws HookExecutionError 如果钩子执行失败
   */
  async executeBeforeSave(entityName: string, data: EntityData): Promise<void> {
    const hooks = this.getHooks(entityName)
    if (hooks === null || hooks.beforeSave === null) {
      return
    }
    await this.executeCallback(hooks.beforeSave, data, entityName, 'beforeSave')
  }

  /**
   * 执行 afterLoad 钩子
   * 在从数据库加载实体数据之后调用
   * @param entityName 实体名称
   * @param data 实体数据
   * @throws HookExecutionError 如果钩子执行失败
   */
  async executeAfterLoad(entityName: string, data: EntityData): Promise<void> {
    const hooks = this.getHooks(entityName)
    if (hooks === null || hooks.afterLoad === null) {
      return
    }
    await this.executeCallback(hooks.afterLoad, data, entityName, 'afterLoad')
  }

  /**
   * 执行 beforeDelete 钩子
   * 在删除实体数据之前调用
   * @param entityName 实体名称
   * @param data 实体数据
   * @throws HookExecutionError 如果钩子执行失败
   */
  async executeBeforeDelete(entityName: string, data: EntityData): Promise<void> {
    const hooks = this.getHooks(entityName)
    if (hooks === null || hooks.beforeDelete === null) {
      return
    }
    await this.executeCallback(hooks.beforeDelete, data, entityName, 'beforeDelete')
  }

  /**
   * 批量执行 afterLoad 钩子
   * 用于查询返回多条记录时
   * @param entityName 实体名称
   * @param dataList 实体数据数组
   * @throws HookExecutionError 如果钩子执行失败
   */
  async executeAfterLoadBatch(entityName: string, dataList: Array<EntityData>): Promise<void> {
    const hooks = this.getHooks(entityName)
    if (hooks === null || hooks.afterLoad === null) {
      return
    }
    for (let i = 0; i < dataList.length; i++) {
      await this.executeCallback(hooks.afterLoad, dataList[i], entityName, 'afterLoad')
    }
  }

  /**
   * 检查实体是否有 beforeSave 钩子
   * @param entityName 实体名称
   * @returns 是否有 beforeSave 钩子
   */
  hasBeforeSaveHook(entityName: string): boolean {
    const hooks = this.getHooks(entityName)
    return hooks !== null && hooks.beforeSave !== null
  }

  /**
   * 检查实体是否有 afterLoad 钩子
   * @param entityName 实体名称
   * @returns 是否有 afterLoad 钩子
   */
  hasAfterLoadHook(entityName: string): boolean {
    const hooks = this.getHooks(entityName)
    return hooks !== null && hooks.afterLoad !== null
  }

  /**
   * 检查实体是否有 beforeDelete 钩子
   * @param entityName 实体名称
   * @returns 是否有 beforeDelete 钩子
   */
  hasBeforeDeleteHook(entityName: string): boolean {
    const hooks = this.getHooks(entityName)
    return hooks !== null && hooks.beforeDelete !== null
  }

  /**
   * 检查实体是否有任何钩子
   * @param entityName 实体名称
   * @returns 是否有任何钩子
   */
  hasAnyHook(entityName: string): boolean {
    const hooks = this.getHooks(entityName)
    if (hooks === null) {
      return false
    }
    return hooks.beforeSave !== null ||
           hooks.afterLoad !== null ||
           hooks.beforeDelete !== null
  }
}
