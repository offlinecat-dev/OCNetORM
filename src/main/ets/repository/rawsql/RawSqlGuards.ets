import { ExecutionError } from '../../errors/DatabaseError'

export function countSqlPlaceholders(sql: string): number {
  const matches = sql.match(/\?/g)
  return matches ? matches.length : 0
}

export function isExpectedRawQueryGuardError(errorMessage: string): boolean {
  const normalized = errorMessage.toLowerCase()
  return normalized.includes('raw_query 仅允许') ||
    normalized.includes('raw_query 仅允许参数化 sql') ||
    normalized.includes('raw_query 参数数量') ||
    normalized.includes('raw_query 禁止写操作') ||
    normalized.includes('raw_query 不允许执行多条 sql') ||
    normalized.includes('sql 语句不能为空') ||
    normalized.includes('raw_query only allows') ||
    normalized.includes('raw_query write is not allowed')
}

export function isExpectedRawExecuteGuardError(errorMessage: string): boolean {
  const normalized = errorMessage.toLowerCase()
  return normalized.includes('raw_execute 仅允许') ||
    normalized.includes('raw_execute 不允许执行多条 sql') ||
    normalized.includes('raw_execute 禁止') ||
    normalized.includes('raw_execute 参数数量') ||
    normalized.includes('sql 语句不能为空') ||
    normalized.includes('raw_execute only allows')
}

export function validateRawExecuteSql(sql: string, argsLength: number): string {
  const trimmedSql = sql.trim()
  if (trimmedSql.length === 0) {
    throw new ExecutionError('RAW_EXECUTE', 'SQL 语句不能为空')
  }
  const normalized = trimmedSql.endsWith(';') ? trimmedSql.slice(0, trimmedSql.length - 1).trim() : trimmedSql
  if (normalized.includes(';')) {
    throw new ExecutionError('RAW_EXECUTE', 'RAW_EXECUTE 不允许执行多条 SQL')
  }
  if (normalized.includes('--') || normalized.includes('/*') || normalized.includes('*/')) {
    throw new ExecutionError('RAW_EXECUTE', 'RAW_EXECUTE 禁止 SQL 注释片段')
  }

  const upperSql = normalized.toUpperCase()
  const allowedWrite = upperSql.startsWith('INSERT ') || upperSql.startsWith('UPDATE ') ||
    upperSql.startsWith('DELETE ') || upperSql.startsWith('REPLACE ')
  if (!allowedWrite) {
    throw new ExecutionError('RAW_EXECUTE', 'RAW_EXECUTE 仅允许 INSERT/UPDATE/DELETE/REPLACE')
  }

  const forbiddenKeywords = /\b(DROP|ALTER|CREATE|TRUNCATE|ATTACH|DETACH|VACUUM|REINDEX|PRAGMA)\b/
  if (forbiddenKeywords.test(upperSql)) {
    throw new ExecutionError('RAW_EXECUTE', 'RAW_EXECUTE 禁止危险 SQL 关键字')
  }

  const placeholderCount = countSqlPlaceholders(normalized)
  if (placeholderCount <= 0) {
    throw new ExecutionError('RAW_EXECUTE', 'RAW_EXECUTE 仅允许参数化 SQL（必须使用 ? 占位符）')
  }
  if (placeholderCount !== argsLength) {
    throw new ExecutionError('RAW_EXECUTE', 'RAW_EXECUTE 参数数量与占位符数量不一致')
  }
  return normalized
}

export function validateRawQuerySql(sql: string): string {
  const trimmedSql = sql.trim()
  if (trimmedSql.length === 0) {
    throw new ExecutionError('RAW_QUERY', 'SQL 语句不能为空')
  }
  const normalized = trimmedSql.endsWith(';') ? trimmedSql.slice(0, trimmedSql.length - 1).trim() : trimmedSql
  if (normalized.includes(';')) {
    throw new ExecutionError('RAW_QUERY', 'RAW_QUERY 不允许执行多条 SQL')
  }
  const upperSql = stripSqlForValidation(normalized).trim().toUpperCase()
  if (!upperSql.startsWith('SELECT ') && !upperSql.startsWith('WITH ') &&
    !upperSql.startsWith('EXPLAIN ')) {
    throw new ExecutionError('RAW_QUERY', 'RAW_QUERY 仅允许 SELECT/WITH/EXPLAIN 只读 SQL')
  }
  const hasWriteKeyword = /\b(INSERT|UPDATE|DELETE|REPLACE|DROP|ALTER|CREATE|TRUNCATE|ATTACH|DETACH|VACUUM|REINDEX)\b/.test(upperSql)
  if (hasWriteKeyword) {
    throw new ExecutionError('RAW_QUERY', 'RAW_QUERY 禁止写操作 SQL')
  }
  return normalized
}

function stripSqlForValidation(sql: string): string {
  let result = ''
  let inSingle = false
  let inDouble = false
  let inLineComment = false
  let inBlockComment = false

  for (let i = 0; i < sql.length; i++) {
    const ch = sql[i]
    const next = i + 1 < sql.length ? sql[i + 1] : ''

    if (inLineComment) {
      if (ch === '\n') {
        inLineComment = false
        result += ' '
      }
      continue
    }

    if (inBlockComment) {
      if (ch === '*' && next === '/') {
        inBlockComment = false
        i++
        result += ' '
      }
      continue
    }

    if (inSingle) {
      if (ch === '\'') {
        if (next === '\'') {
          i++
          continue
        }
        inSingle = false
        result += ' '
      }
      continue
    }

    if (inDouble) {
      if (ch === '"') {
        if (next === '"') {
          i++
          continue
        }
        inDouble = false
        result += ' '
      }
      continue
    }

    if (ch === '-' && next === '-') {
      inLineComment = true
      i++
      continue
    }

    if (ch === '/' && next === '*') {
      inBlockComment = true
      i++
      continue
    }

    if (ch === '\'') {
      inSingle = true
      result += ' '
      continue
    }

    if (ch === '"') {
      inDouble = true
      result += ' '
      continue
    }

    result += ch
  }

  return result
}

