/**
 * 错误信息脱敏工具
 * 统一过滤错误消息中的敏感信息，避免泄露 SQL 字面值、路径和长数字标识
 */

const MAX_ERROR_MESSAGE_LENGTH: number = 256

export function sanitizeErrorMessage(rawMessage: string): string {
  let message = rawMessage.replace(/[\x00-\x1F\x7F]/g, ' ')
  message = message.replace(/'[^']*'/g, "'[***]'")
  message = message.replace(/\"[^\"]*\"/g, '"[***]"')
  message = message.replace(/\b\d{7,}\b/g, '[***]')
  message = message.replace(/[A-Za-z]:\\[^\s]+/g, '[path]')
  message = message.replace(/\/[^\s]{3,}/g, '[path]')
  message = message.replace(/\s+/g, ' ').trim()
  if (message.length > MAX_ERROR_MESSAGE_LENGTH) {
    return `${message.slice(0, MAX_ERROR_MESSAGE_LENGTH)}...`
  }
  return message
}

export function sanitizeSqlPreview(rawSql: string): string {
  const sql = sanitizeErrorMessage(rawSql)
  if (sql.length > 120) {
    return `${sql.slice(0, 120)}...`
  }
  return sql
}
