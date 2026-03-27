import { DatabaseConfig } from '../DatabaseConfig'

/**
 * 查询并发槽位控制器
 * 负责并发上限和等待队列调度
 */
export class QuerySlotGate {
  private queryTimeoutMs: number = 0
  private maxConcurrentQueries: number = 0
  private activeQuerySlots: number = 0
  private pendingResolvers: Array<PendingResolver> = []

  getQueryTimeoutMs(): number {
    return this.queryTimeoutMs
  }

  getMaxConcurrentQueries(): number {
    return this.maxConcurrentQueries
  }

  getActiveQuerySlots(): number {
    return this.activeQuerySlots
  }

  configure(config: DatabaseConfig): void {
    const timeoutMs = Number.isFinite(config.queryTimeoutMs) ? config.queryTimeoutMs : 0
    const maxQueries = Number.isFinite(config.maxConcurrentQueries) ? config.maxConcurrentQueries : 0
    this.queryTimeoutMs = timeoutMs > 0 ? Math.floor(timeoutMs) : 0
    this.maxConcurrentQueries = maxQueries > 0 ? Math.floor(maxQueries) : 0
    if (this.maxConcurrentQueries === 0) {
      this.releaseAllWaiting()
      return
    }
    this.resolveAvailableWaiting()
  }

  async acquire(): Promise<void> {
    if (this.maxConcurrentQueries <= 0) {
      return
    }
    while (this.maxConcurrentQueries > 0 && this.activeQuerySlots >= this.maxConcurrentQueries) {
      await new Promise<void>((resolve, reject) => {
        const resolver = new PendingResolver(resolve, reject, this.queryTimeoutMs, () => {
          const index = this.pendingResolvers.indexOf(resolver)
          if (index >= 0) {
            this.pendingResolvers.splice(index, 1)
          }
        })
        this.pendingResolvers.push(resolver)
      })
      if (this.maxConcurrentQueries <= 0) {
        return
      }
      // Waiters are resumed only after a slot is reserved.
      return
    }
    if (this.maxConcurrentQueries <= 0) {
      return
    }
    this.activeQuerySlots++
  }

  release(): void {
    if (this.activeQuerySlots > 0) {
      this.activeQuerySlots--
    }
    if (this.maxConcurrentQueries <= 0) {
      this.releaseAllWaiting()
      return
    }
    this.resolveWaiting(true)
  }

  reset(): void {
    this.queryTimeoutMs = 0
    this.maxConcurrentQueries = 0
    this.activeQuerySlots = 0
    this.releaseAllWaiting()
  }

  private resolveAvailableWaiting(): void {
    while (this.pendingResolvers.length > 0 &&
      this.maxConcurrentQueries > 0 &&
      this.activeQuerySlots < this.maxConcurrentQueries) {
      this.resolveWaiting(true)
    }
  }

  private resolveWaiting(reserveSlot: boolean): void {
    if (this.pendingResolvers.length === 0) {
      return
    }
    if (reserveSlot && this.maxConcurrentQueries > 0 && this.activeQuerySlots >= this.maxConcurrentQueries) {
      return
    }
    const pending = this.pendingResolvers.shift()
    if (pending !== undefined) {
      if (reserveSlot && this.maxConcurrentQueries > 0) {
        pending.markReserved()
        this.activeQuerySlots++
      }
      pending.resolveSafely()
    }
  }

  private releaseAllWaiting(): void {
    while (this.pendingResolvers.length > 0) {
      this.resolveWaiting(false)
    }
  }
}

class PendingResolver {
  private resolve: () => void
  private reject: (error: Error) => void
  private timeoutId: number = 0
  private settled: boolean = false
  private onTimeout: (() => void) | null
  private reserved: boolean = false

  constructor(
    resolve: () => void,
    reject: (error: Error) => void,
    timeoutMs: number,
    onTimeout?: () => void
  ) {
    this.resolve = resolve
    this.reject = reject
    this.onTimeout = onTimeout ? onTimeout : null
    if (timeoutMs > 0) {
      this.timeoutId = setTimeout(() => {
        if (this.onTimeout !== null) {
          this.onTimeout()
        }
        this.rejectSafely(new Error(`等待查询槽位超时 (${timeoutMs}ms)`))
      }, timeoutMs)
    }
  }

  resolveSafely(): void {
    if (this.settled) {
      return
    }
    this.settled = true
    if (this.timeoutId !== 0) {
      clearTimeout(this.timeoutId)
      this.timeoutId = 0
    }
    this.resolve()
  }

  markReserved(): void {
    this.reserved = true
  }

  isReserved(): boolean {
    return this.reserved
  }

  rejectSafely(error: Error): void {
    if (this.settled) {
      return
    }
    this.settled = true
    if (this.timeoutId !== 0) {
      clearTimeout(this.timeoutId)
      this.timeoutId = 0
    }
    this.reject(error)
  }
}
