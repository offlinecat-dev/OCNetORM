/**
 * 值类型定义
 * 定义 ORM 框架中使用的各种值类型
 */

/**
 * ArkTS 值类型
 * 表示可以存储在实体属性中的值类型
 */
export type ValueType = string | number | boolean | null | Date | object

/**
 * 数据库值类型
 * 表示可以存储在数据库中的值类型
 */
export type DbValueType = string | number | Uint8Array | null

/**
 * 排序方向
 */
export type SortDirection = 'ASC' | 'DESC'

/**
 * 排序子句类
 */
export class OrderByClause {
  /** 列名 */
  column: string = ''
  /** 排序方向 */
  direction: SortDirection = 'ASC'

  constructor(column: string, direction: SortDirection) {
    this.column = column
    this.direction = direction
  }
}
