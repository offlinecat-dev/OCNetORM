/**
 * 错误国际化配置
 * 用于根据 locale 输出多语言错误信息
 */

export type ErrorLocale = string

export class ErrorTemplateContext {
  entityName: string = ''
  columnName: string = ''
  tableName: string = ''
  operation: string = ''
  details: string = ''
  min: number | null = null
  max: number | null = null

  getValue(key: string): string | number | null {
    switch (key) {
      case 'entityName':
        return this.entityName
      case 'columnName':
        return this.columnName
      case 'tableName':
        return this.tableName
      case 'operation':
        return this.operation
      case 'details':
        return this.details
      case 'min':
        return this.min
      case 'max':
        return this.max
      default:
        return null
    }
  }
}

export class ErrorLocaleMessageEntry {
  code: string = ''
  message: string = ''

  constructor(code: string, message: string) {
    this.code = code
    this.message = message
  }
}

export class ErrorLocaleMessages {
  private entries: Array<ErrorLocaleMessageEntry> = []

  add(code: string, message: string): void {
    this.entries.push(new ErrorLocaleMessageEntry(code, message))
  }

  getMessage(code: string): string | null {
    const entry = this.findEntry(code)
    return entry ? entry.message : null
  }

  setMessage(code: string, message: string): void {
    const entry = this.findEntry(code)
    if (entry) {
      entry.message = message
      return
    }
    this.entries.push(new ErrorLocaleMessageEntry(code, message))
  }

  mergeFrom(messages: ErrorLocaleMessages, override: boolean): void {
    for (let i = 0; i < messages.entries.length; i++) {
      const entry = messages.entries[i]
      if (override || !this.findEntry(entry.code)) {
        this.setMessage(entry.code, entry.message)
      }
    }
  }

  private findEntry(code: string): ErrorLocaleMessageEntry | null {
    for (let i = 0; i < this.entries.length; i++) {
      const entry = this.entries[i]
      if (entry.code === code) {
        return entry
      }
    }
    return null
  }
}

class ErrorLocaleGroup {
  locale: ErrorLocale = ''
  messages: ErrorLocaleMessages = new ErrorLocaleMessages()

  constructor(locale: ErrorLocale, messages: ErrorLocaleMessages) {
    this.locale = locale
    this.messages = messages
  }
}

export class ErrorLocaleRegistry {
  private groups: Array<ErrorLocaleGroup> = []

  get(locale: ErrorLocale): ErrorLocaleMessages | null {
    for (let i = 0; i < this.groups.length; i++) {
      const group = this.groups[i]
      if (group.locale === locale) {
        return group.messages
      }
    }
    return null
  }

  getOrCreate(locale: ErrorLocale): ErrorLocaleMessages {
    const existing = this.get(locale)
    if (existing) {
      return existing
    }
    const messages = new ErrorLocaleMessages()
    this.groups.push(new ErrorLocaleGroup(locale, messages))
    return messages
  }

  set(locale: ErrorLocale, messages: ErrorLocaleMessages): void {
    for (let i = 0; i < this.groups.length; i++) {
      const group = this.groups[i]
      if (group.locale === locale) {
        group.messages = messages
        return
      }
    }
    this.groups.push(new ErrorLocaleGroup(locale, messages))
  }
}

const LOCALE_REGISTRY: ErrorLocaleRegistry = createDefaultRegistry()

let currentLocale: ErrorLocale = 'zh'

export function setErrorLocale(locale: ErrorLocale): void {
  currentLocale = locale
}

export function registerErrorLocaleMessages(
  locale: ErrorLocale,
  messages: ErrorLocaleMessages,
  override: boolean = true
): void {
  const target = LOCALE_REGISTRY.getOrCreate(locale)
  target.mergeFrom(messages, override)
}

export function getErrorLocale(): ErrorLocale {
  return currentLocale
}

export function formatErrorMessage(
  code: string,
  fallback: string,
  context?: ErrorTemplateContext
): string {
  const localeMessages = LOCALE_REGISTRY.get(currentLocale)
  const template = localeMessages ? localeMessages.getMessage(code) : null
  const resolvedTemplate = template ? template : fallback
  if (!context) {
    return resolvedTemplate
  }
  return resolvedTemplate.replace(/\{(\w+)\}/g, (_, key: string) => {
    const value = context.getValue(key)
    if (value === undefined || value === null) {
      return ''
    }
    return String(value)
  })
}

function createDefaultRegistry(): ErrorLocaleRegistry {
  const registry = new ErrorLocaleRegistry()
  registry.set('zh', createZhMessages())
  registry.set('en', createEnMessages())
  return registry
}

function createZhMessages(): ErrorLocaleMessages {
  const messages = new ErrorLocaleMessages()
  messages.add('ORM001', '实体 "{entityName}" 未注册')
  messages.add('ORM002', '实体 "{entityName}" 已存在，不能重复注册')
  messages.add('ORM003', '列 "{columnName}" 的类型不受支持: {details}')
  messages.add('ORM004', '在实体 "{entityName}" 中未找到列 "{columnName}"')
  messages.add('ORM005', '实体 "{entityName}" 未定义主键')
  messages.add('ORM101', '查询条件无效: {details}')
  messages.add('ORM102', '构建 RdbPredicates 失败: {details}')
  messages.add('ORM103', '不支持的查询操作符: {details}')
  messages.add('ORM104', '子查询构建失败: {details}')
  messages.add('ORM201', '类型转换失败: {details}')
  messages.add('ORM202', '列 "{columnName}" 不允许为空值')
  messages.add('ORM203', '实体 "{entityName}" 映射失败: {details}')
  messages.add('ORM204', '类型不匹配: {details}')
  messages.add('ORM301', '事务未启动')
  messages.add('ORM302', '事务已回滚: {details}')
  messages.add('ORM303', '事务提交失败: {details}')
  messages.add('ORM401', '数据库连接失败: {details}')
  messages.add('ORM402', 'SQL 执行失败: {details}')
  messages.add('ORM403', '数据库未初始化')
  messages.add('ORM501', '实体 "{entityName}" 的关联关系未找到: {details}')
  messages.add('ORM502', '无效的关系类型: {details}')
  messages.add('ORM503', '无效的外键位置: {details}')
  messages.add('ORM504', '多对多关联中间表未找到: {tableName}')
  messages.add('ORM601', '实体 "{entityName}" 的钩子 "{operation}" 执行失败: {details}')
  messages.add('ORM701', '实体 "{entityName}" 未启用软删除功能')
  messages.add('ORM801', '数据验证失败')
  messages.add('ORM802', '字段 {columnName} 为必填项')
  messages.add('ORM803', '字段 {columnName} 长度需在 {min} 到 {max} 之间')
  messages.add('ORM804', '字段 {columnName} 不是有效的邮箱地址')
  messages.add('ORM805', '字段 {columnName} 的值不能小于 {min}')
  messages.add('ORM806', '字段 {columnName} 的值不能大于 {max}')
  messages.add('ORM807', '字段 {columnName} 的值需在 {min} 到 {max} 之间')
  messages.add('ORM808', '字段 {columnName} 不符合预期格式')
  messages.add('ORM809', '字段 {columnName} 不是有效的 URL')
  messages.add('ORM810', '字段 {columnName} 不是有效的手机号')
  messages.add('ORM811', '字段 {columnName} 不是有效的日期')
  messages.add('ORM812', '字段 {columnName} 的值不在允许范围内')
  messages.add('ORM813', '字段 {columnName} 未通过自定义校验')
  messages.add('ORM814', '字段 {columnName} 的值必须唯一')
  return messages
}

function createEnMessages(): ErrorLocaleMessages {
  const messages = new ErrorLocaleMessages()
  messages.add('ORM001', 'Entity "{entityName}" is not registered')
  messages.add('ORM002', 'Entity "{entityName}" is already registered')
  messages.add('ORM003', 'Column "{columnName}" has unsupported type: {details}')
  messages.add('ORM004', 'Column "{columnName}" not found in entity "{entityName}"')
  messages.add('ORM005', 'Entity "{entityName}" does not define a primary key')
  messages.add('ORM101', 'Invalid query condition for column "{columnName}": {details}')
  messages.add('ORM102', 'Failed to build RdbPredicates for entity "{entityName}": {details}')
  messages.add('ORM103', 'Unsupported query operator: {details}')
  messages.add('ORM104', 'Subquery build failed: {details}')
  messages.add('ORM201', 'Type conversion failed: {details}')
  messages.add('ORM202', 'Column "{columnName}" does not allow null')
  messages.add('ORM203', 'Entity "{entityName}" mapping failed: {details}')
  messages.add('ORM204', 'Type mismatch: {details}')
  messages.add('ORM301', 'Transaction not started')
  messages.add('ORM302', 'Transaction rolled back: {details}')
  messages.add('ORM303', 'Transaction commit failed: {details}')
  messages.add('ORM401', 'Database connection failed: {details}')
  messages.add('ORM402', 'SQL execution failed: {details}')
  messages.add('ORM403', 'Database not initialized')
  messages.add('ORM501', 'Relation not found for entity "{entityName}": {details}')
  messages.add('ORM502', 'Invalid relation type: {details}')
  messages.add('ORM503', 'Invalid foreign key side: {details}')
  messages.add('ORM504', 'Join table not found: {tableName}')
  messages.add('ORM601', 'Hook "{operation}" failed for entity "{entityName}": {details}')
  messages.add('ORM701', 'Soft delete is not enabled for entity "{entityName}"')
  messages.add('ORM801', 'Validation failed')
  messages.add('ORM802', 'Field {columnName} is required')
  messages.add('ORM803', 'Field {columnName} length must be between {min} and {max}')
  messages.add('ORM804', 'Field {columnName} is not a valid email address')
  messages.add('ORM805', 'Field {columnName} must not be less than {min}')
  messages.add('ORM806', 'Field {columnName} must not be greater than {max}')
  messages.add('ORM807', 'Field {columnName} must be between {min} and {max}')
  messages.add('ORM808', 'Field {columnName} does not match the required pattern')
  messages.add('ORM809', 'Field {columnName} is not a valid URL')
  messages.add('ORM810', 'Field {columnName} is not a valid phone number')
  messages.add('ORM811', 'Field {columnName} is not a valid date')
  messages.add('ORM812', 'Field {columnName} is not in the allowed values')
  messages.add('ORM813', 'Field {columnName} failed custom validation')
  messages.add('ORM814', 'Field {columnName} must be unique')
  return messages
}
