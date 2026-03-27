import { ValueType } from '../types/ValueTypes'
import { WhereCondition, LogicalOperator } from './WhereCondition'
import { EntityData } from '../mapping/EntityData'

export function compareOrderValues(a: ValueType, b: ValueType, direction: string): number {
  const dir = String(direction).toUpperCase() === 'DESC' ? -1 : 1
  const aNull = a === null || a === undefined
  const bNull = b === null || b === undefined
  if (aNull || bNull) {
    if (aNull && bNull) {
      return 0
    }
    if (aNull) {
      return dir === 1 ? -1 : 1
    }
    return dir === 1 ? 1 : -1
  }
  const left = normalizeOrderValue(a)
  const right = normalizeOrderValue(b)
  let cmp = 0
  if (typeof left === 'number' && typeof right === 'number') {
    cmp = left - right
    if (Number.isNaN(cmp)) {
      cmp = String(left).localeCompare(String(right))
    }
  } else {
    cmp = String(left).localeCompare(String(right))
  }
  if (cmp === 0) {
    return 0
  }
  return cmp * dir
}

export function splitIntoBatches<T>(values: Array<T>, batchSize: number): Array<Array<T>> {
  const batches: Array<Array<T>> = []
  const effectiveSize = batchSize > 0 ? Math.floor(batchSize) : 1
  for (let i = 0; i < values.length; i += effectiveSize) {
    const batch: Array<T> = []
    for (let j = i; j < Math.min(i + effectiveSize, values.length); j++) {
      batch.push(values[j])
    }
    batches.push(batch)
  }
  return batches
}

export function toIdKey(value: ValueType): string {
  if (value === null) {
    return ''
  }
  if (typeof value === 'number') {
    return `n:${value}`
  }
  if (typeof value === 'boolean') {
    return `b:${value ? 1 : 0}`
  }
  return `s:${String(value)}`
}

export function buildIdSetFromValues(sourceIds: Array<ValueType>): Set<string> {
  const idSet: Set<string> = new Set()
  for (let i = 0; i < sourceIds.length; i++) {
    const id = sourceIds[i]
    if (id === null) {
      continue
    }
    idSet.add(toIdKey(id))
  }
  return idSet
}

export function normalizeSubQueryIds(sourceIds: Array<ValueType>): Array<ValueType> {
  const result: Array<ValueType> = []
  const seen: Set<string> = new Set()
  for (let i = 0; i < sourceIds.length; i++) {
    const id = sourceIds[i]
    if (id === null) {
      continue
    }
    const key = toIdKey(id)
    if (!seen.has(key)) {
      seen.add(key)
      result.push(id)
    }
  }
  return result
}

export function hasOrConditions(conditions: Array<WhereCondition>): boolean {
  for (let i = 1; i < conditions.length; i++) {
    if (conditions[i].logicalOperator === LogicalOperator.OR) {
      return true
    }
  }
  return false
}

export function restoreConditions(conditions: Array<WhereCondition>, originalCount: number): void {
  if (conditions.length > originalCount) {
    conditions.splice(originalCount, conditions.length - originalCount)
  }
}

export function filterEntitiesByIdSet(
  results: Array<EntityData>,
  idSet: Set<string>,
  resolvePrimaryKey: (entity: EntityData) => ValueType
): Array<EntityData> {
  if (idSet.size === 0) {
    return []
  }
  const filtered: Array<EntityData> = []
  for (let i = 0; i < results.length; i++) {
    const entity = results[i]
    const pkValue = resolvePrimaryKey(entity)
    if (pkValue !== null && idSet.has(toIdKey(pkValue))) {
      filtered.push(entity)
    }
  }
  return filtered
}

export function applyLimitOffset<T>(rows: Array<T>, limit: number, offset: number): Array<T> {
  const safeOffset = offset > 0 ? offset : 0
  if (limit > 0) {
    return rows.slice(safeOffset, safeOffset + limit)
  }
  if (safeOffset > 0) {
    return rows.slice(safeOffset)
  }
  return rows
}

function normalizeOrderValue(value: ValueType): string | number {
  if (typeof value === 'boolean') {
    return value ? 1 : 0
  }
  if (value instanceof Date) {
    return value.getTime()
  }
  if (value instanceof Uint8Array) {
    return toHexString(value)
  }
  if (typeof value === 'number' || typeof value === 'string') {
    return value
  }
  return String(value)
}

function toHexString(value: Uint8Array): string {
  const parts: Array<string> = []
  for (let i = 0; i < value.length; i++) {
    parts.push(value[i].toString(16).padStart(2, '0'))
  }
  return parts.join('')
}
