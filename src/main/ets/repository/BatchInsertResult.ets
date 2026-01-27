/**
 * 批量插入结果类
 * 用于封装批量插入操作的返回结果
 */

/**
 * 批量插入结果类
 * 包含插入是否成功、成功数量、总数量、失败索引和错误信息
 */
export class BatchInsertResult {
  /** 是否成功 */
  success: boolean = false
  /** 成功插入的数量 */
  insertedCount: number = 0
  /** 总数量 */
  totalCount: number = 0
  /** 失败的索引列表 */
  failedIndexes: Array<number> = []
  /** 错误信息 */
  errorMessage: string = ''

  /**
   * 构造函数
   */
  constructor() {
    this.success = false
    this.insertedCount = 0
    this.totalCount = 0
    this.failedIndexes = []
    this.errorMessage = ''
  }

  /**
   * 创建成功的批量插入结果
   * @param insertedCount 成功插入的数量
   * @param totalCount 总数量
   * @returns BatchInsertResult 实例
   */
  static createSuccess(insertedCount: number, totalCount: number): BatchInsertResult {
    const result = new BatchInsertResult()
    result.success = true
    result.insertedCount = insertedCount
    result.totalCount = totalCount
    return result
  }

  /**
   * 创建失败的批量插入结果
   * @param errorMessage 错误信息
   * @param failedIndexes 失败的索引列表
   * @returns BatchInsertResult 实例
   */
  static createFailure(errorMessage: string, failedIndexes: Array<number> = []): BatchInsertResult {
    const result = new BatchInsertResult()
    result.success = false
    result.errorMessage = errorMessage
    result.failedIndexes = failedIndexes
    return result
  }

  /**
   * 创建部分成功的批量插入结果
   * @param insertedCount 成功插入的数量
   * @param totalCount 总数量
   * @param failedIndexes 失败的索引列表
   * @param errorMessage 错误信息
   * @returns BatchInsertResult 实例
   */
  static createPartialSuccess(
    insertedCount: number,
    totalCount: number,
    failedIndexes: Array<number>,
    errorMessage: string = ''
  ): BatchInsertResult {
    const result = new BatchInsertResult()
    result.success = false
    result.insertedCount = insertedCount
    result.totalCount = totalCount
    result.failedIndexes = failedIndexes
    result.errorMessage = errorMessage
    return result
  }

  /**
   * 检查是否全部成功
   * @returns 是否全部成功
   */
  isAllSuccess(): boolean {
    return this.success && this.insertedCount === this.totalCount
  }

  /**
   * 检查是否部分成功
   * @returns 是否部分成功
   */
  isPartialSuccess(): boolean {
    return this.insertedCount > 0 && this.insertedCount < this.totalCount
  }

  /**
   * 检查是否全部失败
   * @returns 是否全部失败
   */
  isAllFailed(): boolean {
    return this.insertedCount === 0 && this.totalCount > 0
  }

  /**
   * 获取失败数量
   * @returns 失败数量
   */
  getFailedCount(): number {
    return this.totalCount - this.insertedCount
  }

  /**
   * 获取成功率（百分比）
   * @returns 成功率，0-100
   */
  getSuccessRate(): number {
    if (this.totalCount === 0) {
      return 0
    }
    return (this.insertedCount / this.totalCount) * 100
  }
}
