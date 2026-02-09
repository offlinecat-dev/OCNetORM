/**
 * 删除结果类
 */
export class DeleteResult {
  /** 是否成功 */
  success: boolean = false
  /** 受影响的行数 */
  affectedRows: number = 0
  /** 错误信息 */
  errorMessage: string = ''

  static createSuccess(affectedRows: number): DeleteResult {
    const result = new DeleteResult()
    result.success = true
    result.affectedRows = affectedRows
    return result
  }

  static createFailure(errorMessage: string): DeleteResult {
    const result = new DeleteResult()
    result.success = false
    result.errorMessage = errorMessage
    return result
  }
}
