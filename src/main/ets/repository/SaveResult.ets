/**
 * 保存结果类
 */
export class SaveResult {
  /** 是否成功 */
  success: boolean = false
  /** 受影响的行数 */
  affectedRows: number = 0
  /** 插入的行 ID（仅 INSERT 操作） */
  insertId: number = 0
  /** 错误信息 */
  errorMessage: string = ''

  static createSuccess(affectedRows: number, insertId: number = 0): SaveResult {
    const result = new SaveResult()
    result.success = true
    result.affectedRows = affectedRows
    result.insertId = insertId
    return result
  }

  static createFailure(errorMessage: string): SaveResult {
    const result = new SaveResult()
    result.success = false
    result.errorMessage = errorMessage
    return result
  }
}
