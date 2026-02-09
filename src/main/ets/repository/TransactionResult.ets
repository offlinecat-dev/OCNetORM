/**
 * 事务执行结果类
 */
export class TransactionResult {
  /** 是否成功 */
  success: boolean = false
  /** 错误信息 */
  errorMessage: string = ''

  static createSuccess(): TransactionResult {
    const result = new TransactionResult()
    result.success = true
    return result
  }

  static createFailure(errorMessage: string): TransactionResult {
    const result = new TransactionResult()
    result.success = false
    result.errorMessage = errorMessage
    return result
  }
}
