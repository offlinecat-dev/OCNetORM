/**
 * 连接池配置
 */
export class PoolConfig {
  enabled: boolean = false
  minSize: number = 1
  maxSize: number = 1
  acquireTimeoutMs: number = 3000
  idleTimeoutMs: number = 60000
  healthCheckIntervalMs: number = 0

  normalize(): PoolConfig {
    if (!Number.isFinite(this.minSize) || this.minSize < 1) {
      this.minSize = 1
    }
    if (!Number.isFinite(this.maxSize) || this.maxSize < 1) {
      this.maxSize = 1
    }
    if (this.maxSize < this.minSize) {
      this.maxSize = this.minSize
    }
    if (!Number.isFinite(this.acquireTimeoutMs) || this.acquireTimeoutMs < 0) {
      this.acquireTimeoutMs = 0
    }
    if (!Number.isFinite(this.idleTimeoutMs) || this.idleTimeoutMs < 0) {
      this.idleTimeoutMs = 0
    }
    if (!Number.isFinite(this.healthCheckIntervalMs) || this.healthCheckIntervalMs < 0) {
      this.healthCheckIntervalMs = 0
    }
    this.minSize = Math.floor(this.minSize)
    this.maxSize = Math.floor(this.maxSize)
    this.acquireTimeoutMs = Math.floor(this.acquireTimeoutMs)
    this.idleTimeoutMs = Math.floor(this.idleTimeoutMs)
    this.healthCheckIntervalMs = Math.floor(this.healthCheckIntervalMs)
    return this
  }

  clone(): PoolConfig {
    const copy = new PoolConfig()
    copy.enabled = this.enabled
    copy.minSize = this.minSize
    copy.maxSize = this.maxSize
    copy.acquireTimeoutMs = this.acquireTimeoutMs
    copy.idleTimeoutMs = this.idleTimeoutMs
    copy.healthCheckIntervalMs = this.healthCheckIntervalMs
    return copy
  }
}
