import { relationalStore } from '@kit.ArkData'

/**
 * 连接租约
 * release() 必须幂等，避免重复释放污染池状态
 */
export class StoreLease {
  readonly id: string
  readonly store: relationalStore.RdbStore
  readonly acquiredAt: number
  private releaseCallback: ((lease: StoreLease) => void) | null
  private released: boolean = false

  constructor(
    id: string,
    store: relationalStore.RdbStore,
    releaseCallback: ((lease: StoreLease) => void) | null = null
  ) {
    this.id = id
    this.store = store
    this.acquiredAt = Date.now()
    this.releaseCallback = releaseCallback
  }

  isReleased(): boolean {
    return this.released
  }

  release(): void {
    if (this.released) {
      return
    }
    this.released = true
    if (this.releaseCallback !== null) {
      this.releaseCallback(this)
    }
  }
}

