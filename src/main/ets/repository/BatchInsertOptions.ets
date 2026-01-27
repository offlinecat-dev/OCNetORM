/**
 * 批量插入选项类
 * 用于配置批量插入操作的行为
 */

/**
 * 批量插入选项类
 * 控制批量插入时是否使用事务、是否执行钩子以及是否执行数据验证
 */
export class BatchInsertOptions {
  /** 是否在事务中执行 */
  useTransaction: boolean = true
  /** 是否执行 beforeSave 钩子 */
  executeHooks: boolean = true
  /** 是否执行数据验证 */
  executeValidation: boolean = true

  /**
   * 构造函数
   * @param useTransaction 是否使用事务，默认为 true
   * @param executeHooks 是否执行钩子，默认为 true
   * @param executeValidation 是否执行数据验证，默认为 true
   */
  constructor(
    useTransaction: boolean = true,
    executeHooks: boolean = true,
    executeValidation: boolean = true
  ) {
    this.useTransaction = useTransaction
    this.executeHooks = executeHooks
    this.executeValidation = executeValidation
  }

  /**
   * 创建 BatchInsertOptions 实例的便捷方法
   * @param useTransaction 是否使用事务
   * @param executeHooks 是否执行钩子
   * @param executeValidation 是否执行数据验证
   * @returns BatchInsertOptions 实例
   */
  static create(
    useTransaction: boolean = true,
    executeHooks: boolean = true,
    executeValidation: boolean = true
  ): BatchInsertOptions {
    return new BatchInsertOptions(useTransaction, executeHooks, executeValidation)
  }

  /**
   * 创建默认选项（使用事务，执行钩子）
   * @returns 默认的 BatchInsertOptions 实例
   */
  static createDefault(): BatchInsertOptions {
    return new BatchInsertOptions()
  }

  /**
   * 创建快速插入选项（不使用事务，不执行钩子）
   * 适用于大量数据的快速导入场景
   * @returns 快速插入的 BatchInsertOptions 实例
   */
  static createFast(): BatchInsertOptions {
    return new BatchInsertOptions(false, false, false)
  }

  /**
   * 创建安全插入选项（使用事务，执行钩子）
   * 适用于需要数据完整性保证的场景
   * @returns 安全插入的 BatchInsertOptions 实例
   */
  static createSafe(): BatchInsertOptions {
    return new BatchInsertOptions(true, true, true)
  }
}
