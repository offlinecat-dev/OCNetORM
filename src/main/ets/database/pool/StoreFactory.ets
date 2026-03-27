import { Context } from '@kit.AbilityKit'
import { relationalStore } from '@kit.ArkData'

/**
 * RdbStore 创建与关闭工厂
 */
export class StoreFactory {
  private context: Context
  private storeConfig: relationalStore.StoreConfig

  constructor(context: Context, storeConfig: relationalStore.StoreConfig) {
    this.context = context
    this.storeConfig = storeConfig
  }

  async create(): Promise<relationalStore.RdbStore> {
    try {
      return await relationalStore.getRdbStore(this.context, this.storeConfig)
    } catch (e) {
      if (e instanceof Error) {
        throw e
      }
      throw new Error(String(e))
    }
  }

  async close(store: relationalStore.RdbStore): Promise<void> {
    try {
      await store.close()
    } catch (e) {
      if (e instanceof Error) {
        throw e
      }
      throw new Error(String(e))
    }
  }
}
