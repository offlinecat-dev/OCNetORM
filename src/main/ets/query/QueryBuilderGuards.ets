import { InvalidConditionError } from '../errors/QueryError'
import { ValueType, SortDirection } from '../types/ValueTypes'

export function normalizeSortDirectionOrThrow(direction: string): SortDirection {
  const normalized = direction.trim().toUpperCase()
  if (normalized === 'ASC') {
    return 'ASC'
  }
  if (normalized === 'DESC') {
    return 'DESC'
  }
  throw new InvalidConditionError('ORDER BY', `非法排序方向: ${direction}`)
}

export function validateAndNormalizeHavingClause(clause: string, args: Array<ValueType>): string {
  const normalized = clause.trim()
  if (normalized.length === 0) {
    throw new InvalidConditionError('HAVING', 'HAVING 条件不能为空')
  }
  ensureNoDangerousSqlTokens(normalized, 'HAVING')
  ensureNoDangerousSqlKeywords(normalized, 'HAVING')
  if (!/^[A-Za-z0-9_(),.*+\-/%<>=!\s?]+$/.test(normalized)) {
    throw new InvalidConditionError('HAVING', 'HAVING 子句包含非法字符')
  }
  if (args.length === 0) {
    throw new InvalidConditionError('HAVING', 'HAVING 必须使用参数占位符')
  }
  if (countPlaceholders(normalized) !== args.length) {
    throw new InvalidConditionError('HAVING', 'HAVING 占位符数量与参数数量不一致')
  }
  return normalized
}

export function validateAndNormalizeSelectRawExpressions(expressions: Array<string>): Array<string> {
  if (expressions.length === 0) {
    throw new InvalidConditionError('selectRaw', 'selectRaw 表达式不能为空')
  }
  const normalized: Array<string> = []
  for (let i = 0; i < expressions.length; i++) {
    const expression = expressions[i].trim()
    if (expression.length === 0) {
      throw new InvalidConditionError('selectRaw', 'selectRaw 表达式不能为空字符串')
    }
    ensureNoDangerousSqlTokens(expression, 'selectRaw')
    if (!isSafeSelectRawExpression(expression)) {
      throw new InvalidConditionError('selectRaw', `不支持的 selectRaw 表达式: ${expression}`)
    }
    normalized.push(expression)
  }
  return normalized
}

function countPlaceholders(clause: string): number {
  return clause.split('?').length - 1
}

function ensureNoDangerousSqlTokens(value: string, fieldName: string): void {
  const hasDangerousToken = value.includes(';') ||
    value.includes('--') ||
    value.includes('/*') ||
    value.includes('*/') ||
    value.includes("'") ||
    value.includes('"') ||
    value.includes('`')
  if (hasDangerousToken) {
    throw new InvalidConditionError(fieldName, `${fieldName} 包含危险 SQL 片段`)
  }
}

function ensureNoDangerousSqlKeywords(value: string, fieldName: string): void {
  const forbiddenKeywordPattern =
    /\b(UNION|SELECT|FROM|JOIN|INSERT|UPDATE|DELETE|DROP|ALTER|CREATE|ATTACH|DETACH|PRAGMA|VACUUM|REINDEX)\b/i
  if (forbiddenKeywordPattern.test(value)) {
    throw new InvalidConditionError(fieldName, `${fieldName} 包含危险 SQL 关键字`)
  }
}

function isSafeSelectRawExpression(expression: string): boolean {
  const identifierPattern = /^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)?$/
  if (identifierPattern.test(expression)) {
    return true
  }
  const aggregatePattern =
    /^(COUNT|SUM|AVG|MIN|MAX)\(\s*(\*|[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)?)\s*\)(\s+AS\s+[A-Za-z_][A-Za-z0-9_]*)?$/i
  return aggregatePattern.test(expression)
}

