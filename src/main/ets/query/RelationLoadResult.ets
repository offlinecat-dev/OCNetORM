/**
 * 关联加载结果类
 * 用于封装单个关联加载操作的结果
 */

/**
 * 关联加载结果类
 * 包含关联名称、是否成功和错误信息
 */
export class RelationLoadResult {
  /** 关联名称 */
  relationName: string = ''
  /** 是否成功 */
  success: boolean = false
  /** 错误信息 */
  errorMessage: string = ''
  /** 加载的数据数量 */
  loadedCount: number = 0
  /** 加载耗时（毫秒） */
  duration: number = 0

  /**
   * 构造函数
   * @param relationName 关联名称
   */
  constructor(relationName: string = '') {
    this.relationName = relationName
    this.success = false
    this.errorMessage = ''
    this.loadedCount = 0
    this.duration = 0
  }

  /**
   * 创建成功的关联加载结果
   * @param relationName 关联名称
   * @param loadedCount 加载的数据数量
   * @param duration 加载耗时（毫秒）
   * @returns RelationLoadResult 实例
   */
  static createSuccess(relationName: string, loadedCount: number = 0, duration: number = 0): RelationLoadResult {
    const result = new RelationLoadResult(relationName)
    result.success = true
    result.loadedCount = loadedCount
    result.duration = duration
    return result
  }

  /**
   * 创建失败的关联加载结果
   * @param relationName 关联名称
   * @param errorMessage 错误信息
   * @param duration 加载耗时（毫秒）
   * @returns RelationLoadResult 实例
   */
  static createFailure(relationName: string, errorMessage: string, duration: number = 0): RelationLoadResult {
    const result = new RelationLoadResult(relationName)
    result.success = false
    result.errorMessage = errorMessage
    result.duration = duration
    return result
  }

  /**
   * 检查是否加载成功
   * @returns 是否成功
   */
  isSuccess(): boolean {
    return this.success
  }

  /**
   * 检查是否加载失败
   * @returns 是否失败
   */
  isFailed(): boolean {
    return !this.success
  }

  /**
   * 获取格式化的错误信息
   * @returns 格式化的错误信息
   */
  getFormattedError(): string {
    if (this.success) {
      return ''
    }
    return `关联 '${this.relationName}' 加载失败: ${this.errorMessage}`
  }
}

/**
 * 并行关联加载结果类
 * 用于封装多个关联并行加载的整体结果
 */
export class ParallelRelationLoadResult {
  /** 各个关联的加载结果 */
  results: Array<RelationLoadResult> = []
  /** 总耗时（毫秒） */
  totalDuration: number = 0

  /**
   * 构造函数
   */
  constructor() {
    this.results = []
    this.totalDuration = 0
  }

  /**
   * 添加单个关联加载结果
   * @param result 关联加载结果
   */
  addResult(result: RelationLoadResult): void {
    this.results.push(result)
  }

  /**
   * 检查是否全部成功
   * @returns 是否全部成功
   */
  isAllSuccess(): boolean {
    for (let i = 0; i < this.results.length; i++) {
      if (!this.results[i].success) {
        return false
      }
    }
    return true
  }

  /**
   * 检查是否有任何失败
   * @returns 是否有失败
   */
  hasAnyFailure(): boolean {
    for (let i = 0; i < this.results.length; i++) {
      if (!this.results[i].success) {
        return true
      }
    }
    return false
  }

  /**
   * 获取成功的关联数量
   * @returns 成功数量
   */
  getSuccessCount(): number {
    let count = 0
    for (let i = 0; i < this.results.length; i++) {
      if (this.results[i].success) {
        count++
      }
    }
    return count
  }

  /**
   * 获取失败的关联数量
   * @returns 失败数量
   */
  getFailureCount(): number {
    let count = 0
    for (let i = 0; i < this.results.length; i++) {
      if (!this.results[i].success) {
        count++
      }
    }
    return count
  }

  /**
   * 获取失败的关联名称列表
   * @returns 失败的关联名称数组
   */
  getFailedRelationNames(): Array<string> {
    const names: Array<string> = []
    for (let i = 0; i < this.results.length; i++) {
      if (!this.results[i].success) {
        names.push(this.results[i].relationName)
      }
    }
    return names
  }

  /**
   * 获取所有错误信息
   * @returns 错误信息数组
   */
  getErrorMessages(): Array<string> {
    const messages: Array<string> = []
    for (let i = 0; i < this.results.length; i++) {
      if (!this.results[i].success && this.results[i].errorMessage !== '') {
        messages.push(this.results[i].getFormattedError())
      }
    }
    return messages
  }

  /**
   * 获取加载的总数据数量
   * @returns 总数据数量
   */
  getTotalLoadedCount(): number {
    let count = 0
    for (let i = 0; i < this.results.length; i++) {
      count += this.results[i].loadedCount
    }
    return count
  }

  /**
   * 创建并行加载结果
   * @param results 各个关联的加载结果
   * @param totalDuration 总耗时
   * @returns ParallelRelationLoadResult 实例
   */
  static create(results: Array<RelationLoadResult>, totalDuration: number): ParallelRelationLoadResult {
    const parallelResult = new ParallelRelationLoadResult()
    parallelResult.results = results
    parallelResult.totalDuration = totalDuration
    return parallelResult
  }
}
