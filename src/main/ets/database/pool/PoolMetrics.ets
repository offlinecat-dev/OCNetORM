/**
 * 连接池运行指标
 */
export class PoolMetrics {
  minSize: number = 0
  maxSize: number = 0
  currentSize: number = 0
  activeLeases: number = 0
  idleStores: number = 0
  pendingRequests: number = 0
  timeoutCount: number = 0
  closed: boolean = false
}

