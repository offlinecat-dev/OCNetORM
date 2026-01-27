/**
 * 数据转换任务
 * 用于 TaskPool 异步执行数据转换操作
 * 
 * 注意：由于 ArkTS 的严格类型约束和 HarmonyOS TaskPool 的限制，
 * 数据库操作必须在主线程执行，DataMapper 依赖 MetadataStorage 单例，
 * 因此这里的类不使用 @Sendable 装饰器，而是作为普通数据传输类使用。
 * 
 * 未来如果需要真正的 TaskPool 并行处理，可以考虑：
 * 1. 将元数据序列化后传递给 Worker
 * 2. 使用 SharedArrayBuffer 共享数据
 * 
 * Requirements: 1.1, 1.2
 */

/**
 * 行数据类型
 * 用于存储单行的列名和值映射
 */
export class RowData {
  /** 列名数组 */
  columnNames: Array<string> = []
  /** 值数组（与列名一一对应） */
  values: Array<string | number | null> = []

  /**
   * 设置列值
   * @param columnName 列名
   * @param value 值
   */
  set(columnName: string, value: string | number | null): void {
    const index = this.columnNames.indexOf(columnName)
    if (index >= 0) {
      this.values[index] = value
    } else {
      this.columnNames.push(columnName)
      this.values.push(value)
    }
  }

  /**
   * 获取列值
   * @param columnName 列名
   * @returns 值，如果不存在返回 null
   */
  get(columnName: string): string | number | null {
    const index = this.columnNames.indexOf(columnName)
    if (index >= 0) {
      return this.values[index]
    }
    return null
  }
}

/**
 * 数据转换任务参数
 * 用于传递给 TaskPool 任务的参数
 * 
 * Requirements: 1.1, 1.2
 */
export class TransformTaskParams {
  /** 列名数组 */
  columnNames: Array<string> = []
  /** 行数据数组（二维数组，每行是值数组） */
  rowsData: Array<Array<string | number | null>> = []
  /** 实体名称 */
  entityName: string = ''
  /** 列类型映射（列名 -> 类型标识） */
  columnTypes: Array<string> = []
  /** 属性名映射（列名 -> 属性名） */
  propertyNames: Array<string> = []

  /**
   * 创建参数实例
   * @param entityName 实体名称
   * @param columnNames 列名数组
   * @param columnTypes 列类型数组
   * @param propertyNames 属性名数组
   * @returns TransformTaskParams 实例
   */
  static create(
    entityName: string,
    columnNames: Array<string>,
    columnTypes: Array<string>,
    propertyNames: Array<string>
  ): TransformTaskParams {
    const params = new TransformTaskParams()
    params.entityName = entityName
    params.columnNames = columnNames
    params.columnTypes = columnTypes
    params.propertyNames = propertyNames
    return params
  }

  /**
   * 添加行数据
   * @param rowValues 行值数组（与 columnNames 一一对应）
   */
  addRow(rowValues: Array<string | number | null>): void {
    this.rowsData.push(rowValues)
  }
}

/**
 * 转换后的实体数据项
 * 用于存储单个实体的属性数据
 */
export class TransformedEntityItem {
  /** 属性名数组 */
  propertyNames: Array<string> = []
  /** 属性值数组（与属性名一一对应） */
  propertyValues: Array<string | number | null> = []
  /** 属性类型数组（与属性名一一对应） */
  propertyTypes: Array<string> = []

  /**
   * 添加属性
   * @param name 属性名
   * @param value 属性值
   * @param type 属性类型
   */
  addProperty(name: string, value: string | number | null, type: string): void {
    this.propertyNames.push(name)
    this.propertyValues.push(value)
    this.propertyTypes.push(type)
  }
}

/**
 * 数据转换任务结果
 * 用于返回 TaskPool 任务的执行结果
 * 
 * Requirements: 1.1, 1.2
 */
export class TransformTaskResult {
  /** 实体名称 */
  entityName: string = ''
  /** 转换后的实体数据数组 */
  entities: Array<TransformedEntityItem> = []
  /** 是否成功 */
  success: boolean = false
  /** 错误信息 */
  errorMessage: string = ''

  /**
   * 创建成功结果
   * @param entityName 实体名称
   * @param entities 转换后的实体数据数组
   * @returns TransformTaskResult 实例
   */
  static createSuccess(entityName: string, entities: Array<TransformedEntityItem>): TransformTaskResult {
    const result = new TransformTaskResult()
    result.entityName = entityName
    result.entities = entities
    result.success = true
    return result
  }

  /**
   * 创建失败结果
   * @param errorMessage 错误信息
   * @returns TransformTaskResult 实例
   */
  static createFailure(errorMessage: string): TransformTaskResult {
    const result = new TransformTaskResult()
    result.success = false
    result.errorMessage = errorMessage
    return result
  }
}
