import { relationalStore } from '@kit.ArkData'
import { PoolConfig } from './PoolConfig'
import { PoolMetrics } from './PoolMetrics'
import { StoreLease } from './StoreLease'
import { StorePool } from './StorePool'

class PendingAcquire {
  resolve: ((lease: StoreLease) => void) | null = null
  reject: ((error: Error) => void) | null = null
  timeoutId: number = 0
}

/**
 * 固定容量连接池
 */
export class FixedStorePool implements StorePool {
  private config: PoolConfig
  private createStore: () => Promise<relationalStore.RdbStore>
  private closeStore: (store: relationalStore.RdbStore) => Promise<void>
  private idleStores: Array<relationalStore.RdbStore> = []
  private activeStores: Map<string, relationalStore.RdbStore> = new Map()
  private pendingAcquires: Array<PendingAcquire> = []
  private timeoutCount: number = 0
  private closed: boolean = false
  private leaseSequence: number = 0
  private creatingStores: number = 0

  constructor(
    config: PoolConfig,
    createStore: () => Promise<relationalStore.RdbStore>,
    closeStore: (store: relationalStore.RdbStore) => Promise<void>,
    initialStores: Array<relationalStore.RdbStore> = []
  ) {
    this.config = config.clone().normalize()
    this.createStore = createStore
    this.closeStore = closeStore
    this.idleStores = initialStores.slice()
  }

  private ensureOpen(): void {
    if (this.closed) {
      throw new Error('连接池已关闭')
    }
  }

  private currentSize(): number {
    return this.idleStores.length + this.activeStores.size + this.creatingStores
  }

  private createLease(store: relationalStore.RdbStore): StoreLease {
    this.leaseSequence += 1
    const leaseId = `lease-${this.leaseSequence}`
    this.activeStores.set(leaseId, store)
    return new StoreLease(leaseId, store, (lease: StoreLease) => {
      this.release(lease)
    })
  }

  private async createStoreAndLease(): Promise<StoreLease> {
    this.creatingStores += 1
    try {
      const store = await this.createStore()
      return this.createLease(store)
    } finally {
      this.creatingStores -= 1
    }
  }

  private async handoffOrCache(store: relationalStore.RdbStore): Promise<void> {
    if (this.pendingAcquires.length > 0) {
      const pending = this.pendingAcquires.shift()
      if (pending !== undefined && pending.resolve !== null) {
        if (pending.timeoutId !== 0) {
          clearTimeout(pending.timeoutId)
        }
        const lease = this.createLease(store)
        pending.resolve(lease)
        return
      }
    }
    this.idleStores.push(store)
  }

  async warmUp(): Promise<void> {
    this.ensureOpen()
    while (this.currentSize() < this.config.minSize) {
      const store = await this.createStore()
      this.idleStores.push(store)
    }
  }

  async acquire(timeoutMs?: number): Promise<StoreLease> {
    this.ensureOpen()

    const idle = this.idleStores.pop()
    if (idle !== undefined) {
      return this.createLease(idle)
    }

    if (this.currentSize() < this.config.maxSize) {
      return await this.createStoreAndLease()
    }

    const effectiveTimeout = timeoutMs !== undefined ? timeoutMs : this.config.acquireTimeoutMs
    if (effectiveTimeout === 0) {
      throw new Error('连接池无可用连接')
    }

    return await new Promise<StoreLease>((resolve, reject) => {
      const pending = new PendingAcquire()
      pending.resolve = resolve
      pending.reject = reject
      pending.timeoutId = setTimeout(() => {
        this.timeoutCount += 1
        const index = this.pendingAcquires.indexOf(pending)
        if (index >= 0) {
          this.pendingAcquires.splice(index, 1)
        }
        if (pending.reject !== null) {
          pending.reject(new Error('获取连接超时'))
        }
      }, effectiveTimeout)
      this.pendingAcquires.push(pending)
    })
  }

  release(lease: StoreLease): void {
    const store = this.activeStores.get(lease.id)
    if (store === undefined) {
      return
    }
    this.activeStores.delete(lease.id)

    if (this.closed) {
      this.closeStore(store).catch(() => {
      })
      return
    }

    this.handoffOrCache(store).catch(() => {
    })
  }

  async withLease<T>(fn: (lease: StoreLease) => Promise<T>, timeoutMs?: number): Promise<T> {
    const lease = await this.acquire(timeoutMs)
    try {
      return await fn(lease)
    } finally {
      lease.release()
    }
  }

  metrics(): PoolMetrics {
    const metrics = new PoolMetrics()
    metrics.minSize = this.config.minSize
    metrics.maxSize = this.config.maxSize
    metrics.currentSize = this.currentSize()
    metrics.activeLeases = this.activeStores.size
    metrics.idleStores = this.idleStores.length
    metrics.pendingRequests = this.pendingAcquires.length
    metrics.timeoutCount = this.timeoutCount
    metrics.closed = this.closed
    return metrics
  }

  async close(): Promise<void> {
    if (this.closed) {
      return
    }
    this.closed = true

    while (this.pendingAcquires.length > 0) {
      const pending = this.pendingAcquires.shift()
      if (pending === undefined) {
        continue
      }
      if (pending.timeoutId !== 0) {
        clearTimeout(pending.timeoutId)
      }
      if (pending.reject !== null) {
        pending.reject(new Error('连接池已关闭'))
      }
    }

    const stores: Array<relationalStore.RdbStore> = []
    for (let i = 0; i < this.idleStores.length; i++) {
      stores.push(this.idleStores[i])
    }
    this.idleStores = []
    this.activeStores.forEach((store: relationalStore.RdbStore) => {
      stores.push(store)
    })
    this.activeStores.clear()

    for (let i = 0; i < stores.length; i++) {
      try {
        await this.closeStore(stores[i])
      } catch (e) {
      }
    }
  }
}

