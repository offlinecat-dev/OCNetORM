import { relationalStore } from '@kit.ArkData'
import { EntityMetadata } from '../core/EntityMetadata'
import { ConditionOperator } from '../types/ConditionOperator'
import { RelationQueryOptions } from './RelationQueryOptions'
import { LogicalOperator, WhereCondition } from './WhereCondition'
import { ValueType } from '../types/ValueTypes'

type ToRdbValue = (value: ValueType | Array<ValueType> | null) => relationalStore.ValueType

export function applyRelationQueryToPredicates(
  predicates: relationalStore.RdbPredicates,
  metadata: EntityMetadata,
  options: RelationQueryOptions | null,
  toRdbValue: ToRdbValue
): void {
  const conditions = buildEffectiveRelationConditions(metadata, options)
  if (conditions.length > 0) {
    applyWhereConditionsToPredicates(predicates, conditions, toRdbValue)
  }
  if (options !== null) {
    applyOrderByToPredicates(predicates, options)
  }
}

function buildEffectiveRelationConditions(
  metadata: EntityMetadata,
  options: RelationQueryOptions | null
): Array<WhereCondition> {
  const relationConditions = options !== null
    ? cloneWhereConditions(options.conditions)
    : []
  if (!metadata.isSoftDeleteEnabled()) {
    return relationConditions
  }
  if (options !== null && options.includeDeleted) {
    return relationConditions
  }
  const softDeleteCondition = createSoftDeleteCondition(metadata, options)
  if (relationConditions.length === 0) {
    return [softDeleteCondition]
  }
  if (!hasOrLogicalCondition(relationConditions)) {
    const merged: Array<WhereCondition> = [softDeleteCondition]
    for (let i = 0; i < relationConditions.length; i++) {
      merged.push(relationConditions[i])
    }
    return merged
  }
  return mergeSoftDeleteWithOrConditions(relationConditions, softDeleteCondition)
}

function hasOrLogicalCondition(conditions: Array<WhereCondition>): boolean {
  for (let i = 1; i < conditions.length; i++) {
    if (conditions[i].logicalOperator === LogicalOperator.OR) {
      return true
    }
  }
  return false
}

function createSoftDeleteCondition(
  metadata: EntityMetadata,
  options: RelationQueryOptions | null
): WhereCondition {
  const condition = new WhereCondition()
  condition.column = metadata.getDeletedAtColumn()
  condition.operator = options !== null && options.onlyDeleted
    ? ConditionOperator.IS_NOT_NULL
    : ConditionOperator.IS_NULL
  condition.value = null
  condition.logicalOperator = LogicalOperator.AND
  return condition
}

function cloneWhereConditions(conditions: Array<WhereCondition>): Array<WhereCondition> {
  const cloned: Array<WhereCondition> = []
  for (let i = 0; i < conditions.length; i++) {
    cloned.push(cloneWhereCondition(conditions[i]))
  }
  return cloned
}

function cloneWhereCondition(condition: WhereCondition): WhereCondition {
  const cloned = new WhereCondition()
  cloned.column = condition.column
  cloned.operator = condition.operator
  cloned.value = condition.value
  cloned.secondValue = condition.secondValue
  cloned.logicalOperator = condition.logicalOperator
  return cloned
}

function mergeSoftDeleteWithOrConditions(
  conditions: Array<WhereCondition>,
  softDeleteCondition: WhereCondition
): Array<WhereCondition> {
  const merged: Array<WhereCondition> = []
  let segmentStart = 0
  for (let i = 1; i <= conditions.length; i++) {
    const isSegmentEnd = i === conditions.length || conditions[i].logicalOperator === LogicalOperator.OR
    if (!isSegmentEnd) {
      continue
    }
    const clonedSoftDelete = cloneWhereCondition(softDeleteCondition)
    clonedSoftDelete.logicalOperator = segmentStart === 0 ? LogicalOperator.AND : LogicalOperator.OR
    merged.push(clonedSoftDelete)
    for (let j = segmentStart; j < i; j++) {
      const clonedCondition = cloneWhereCondition(conditions[j])
      if (j === segmentStart) {
        clonedCondition.logicalOperator = LogicalOperator.AND
      }
      merged.push(clonedCondition)
    }
    segmentStart = i
  }
  return merged
}

function applyOrderByToPredicates(
  predicates: relationalStore.RdbPredicates,
  options: RelationQueryOptions
): void {
  for (let i = 0; i < options.orderByColumns.length; i++) {
    const orderBy = options.orderByColumns[i]
    if (orderBy.direction === 'ASC') {
      predicates.orderByAsc(orderBy.column)
    } else {
      predicates.orderByDesc(orderBy.column)
    }
  }
}

function applyWhereConditionsToPredicates(
  predicates: relationalStore.RdbPredicates,
  conditions: Array<WhereCondition>,
  toRdbValue: ToRdbValue
): void {
  for (let i = 0; i < conditions.length; i++) {
    const condition = conditions[i]
    if (i > 0) {
      if (condition.logicalOperator === LogicalOperator.OR) {
        predicates.or()
      } else {
        predicates.and()
      }
    }
    applyOneWhereCondition(predicates, condition, toRdbValue)
  }
}

function applyOneWhereCondition(
  predicates: relationalStore.RdbPredicates,
  condition: WhereCondition,
  toRdbValue: ToRdbValue
): void {
  if (applySimpleValueCondition(predicates, condition, toRdbValue)) {
    return
  }
  if (condition.operator === ConditionOperator.IN || condition.operator === ConditionOperator.NOT_IN) {
    const values: Array<ValueType> = condition.value instanceof Array ? condition.value : []
    const rdbValues: Array<relationalStore.ValueType> = []
    for (let i = 0; i < values.length; i++) {
      rdbValues.push(toRdbValue(values[i]))
    }
    if (condition.operator === ConditionOperator.IN) {
      predicates.in(condition.column, rdbValues)
    } else {
      predicates.notIn(condition.column, rdbValues)
    }
    return
  }
  if (condition.operator === ConditionOperator.BETWEEN) {
    predicates.between(condition.column, toRdbValue(condition.value), toRdbValue(condition.secondValue))
    return
  }
  if (condition.operator === ConditionOperator.IS_NULL) {
    predicates.isNull(condition.column)
    return
  }
  if (condition.operator === ConditionOperator.IS_NOT_NULL) {
    predicates.isNotNull(condition.column)
  }
}

function applySimpleValueCondition(
  predicates: relationalStore.RdbPredicates,
  condition: WhereCondition,
  toRdbValue: ToRdbValue
): boolean {
  const value = toRdbValue(condition.value)
  if (condition.operator === ConditionOperator.EQUAL) {
    predicates.equalTo(condition.column, value)
    return true
  }
  if (condition.operator === ConditionOperator.NOT_EQUAL) {
    predicates.notEqualTo(condition.column, value)
    return true
  }
  if (condition.operator === ConditionOperator.GREATER) {
    predicates.greaterThan(condition.column, value)
    return true
  }
  if (condition.operator === ConditionOperator.LESS) {
    predicates.lessThan(condition.column, value)
    return true
  }
  if (condition.operator === ConditionOperator.GREATER_EQUAL) {
    predicates.greaterThanOrEqualTo(condition.column, value)
    return true
  }
  if (condition.operator === ConditionOperator.LESS_EQUAL) {
    predicates.lessThanOrEqualTo(condition.column, value)
    return true
  }
  if (condition.operator === ConditionOperator.LIKE) {
    predicates.like(condition.column, condition.value !== null ? String(condition.value) : '')
    return true
  }
  return false
}
