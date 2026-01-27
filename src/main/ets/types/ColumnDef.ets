/**
 * 列定义基类
 * 用于定义类型安全的列名常量，消除魔法字符串
 *
 * 使用示例:
 * ```
 * export class UserDef extends ColumnDef {
 *   static readonly TABLE_NAME: string = 'users'
 *   static readonly ID: string = 'id'
 *   static readonly NAME: string = 'name'
 *   static readonly AGE: string = 'age'
 * }
 *
 * // 在 QueryBuilder 中使用
 * queryBuilder.where(UserDef.NAME, ConditionOperator.EQ, '张三')
 * ```
 */
export class ColumnDef {
  /** 表名，子类必须重写此常量 */
  static readonly TABLE_NAME: string = ''
}
