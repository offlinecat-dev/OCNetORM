/**
 * 索引元数据
 * 描述实体在数据库中的索引定义
 */
export class IndexMetadata {
  /** 索引名称 */
  name: string = ''
  /** 索引列名列表（数据库列名） */
  columns: Array<string> = []
  /** 是否唯一索引 */
  unique: boolean = false

  constructor(name: string, columns: Array<string>, unique: boolean = false) {
    this.name = name
    this.columns = columns.slice()
    this.unique = unique
  }

  getSignature(): string {
    const uniqueFlag = this.unique ? '1' : '0'
    return `${uniqueFlag}:${this.columns.join(',')}`
  }
}
