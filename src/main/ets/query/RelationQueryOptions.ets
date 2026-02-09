/**
 * 关联查询选项
 * 用于 withWhere 在关联加载阶段追加过滤、排序、分页控制
 */

import { WhereCondition } from './WhereCondition'
import { OrderByClause } from '../types/ValueTypes'

export class RelationQueryOptions {
  conditions: Array<WhereCondition> = []
  orderByColumns: Array<OrderByClause> = []
  limitValue: number = 0
  offsetValue: number = 0
  includeDeleted: boolean = false
  onlyDeleted: boolean = false

  clone(): RelationQueryOptions {
    const cloned = new RelationQueryOptions()
    for (let i = 0; i < this.conditions.length; i++) {
      const source = this.conditions[i]
      const target = new WhereCondition()
      target.column = source.column
      target.operator = source.operator
      target.value = source.value
      target.secondValue = source.secondValue
      target.logicalOperator = source.logicalOperator
      cloned.conditions.push(target)
    }
    for (let i = 0; i < this.orderByColumns.length; i++) {
      const source = this.orderByColumns[i]
      cloned.orderByColumns.push(new OrderByClause(source.column, source.direction))
    }
    cloned.limitValue = this.limitValue
    cloned.offsetValue = this.offsetValue
    cloned.includeDeleted = this.includeDeleted
    cloned.onlyDeleted = this.onlyDeleted
    return cloned
  }
}

export class RelationCountOption {
  relationPath: string = ''
  alias: string = ''

  constructor(relationPath: string, alias: string) {
    this.relationPath = relationPath
    this.alias = alias
  }
}
