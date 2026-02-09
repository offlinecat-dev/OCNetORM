/**
 * 实体验证器
 * 用于执行验证规则并返回验证结果
 */

import { EntityData } from '../mapping/EntityData'
import { MetadataStorage } from '../core/MetadataStorage'
import { ValueType } from '../types/ValueTypes'
import { ValidationMetadataStorage, ValidationRule } from './ValidationMetadataStorage'
import {
  ValidationError,
  RequiredValidationError,
  LengthValidationError,
  EmailValidationError,
  MinValidationError,
  MaxValidationError,
  RangeValidationError,
  PatternValidationError,
  UrlValidationError,
  PhoneValidationError,
  DateValidationError,
  EnumValidationError,
  CustomValidationError,
  UniqueValidationError,
  EntityValidationError
} from '../errors/ValidationError'

export class ValidationResult {
  errors: Array<ValidationError> = []

  addError(error: ValidationError): void {
    this.errors.push(error)
  }

  isValid(): boolean {
    return this.errors.length === 0
  }

  getFirstError(): ValidationError | null {
    if (this.errors.length === 0) {
      return null
    }
    return this.errors[0]
  }

  getSummary(): string {
    if (this.errors.length === 0) {
      return ''
    }
    return this.errors.map((error) => error.message).join('; ')
  }
}

export interface ValidationOptions {
  groups?: Array<string>
  uniqueChecker?: (
    entityName: string,
    propertyName: string,
    value: ValueType | undefined,
    entityData: EntityData
  ) => boolean
}

export class EntityValidator {
  static validate(
    entityName: string,
    entityData: EntityData,
    options: ValidationOptions = {}
  ): ValidationResult {
    const result = new ValidationResult()
    const rules = ValidationMetadataStorage.getInstance().getRules(entityName)
    if (rules.size === 0) {
      return result
    }
    const groups = normalizeGroups(options.groups)

    const metadata = MetadataStorage.getInstance().getEntityMetadata(entityName)
    if (metadata === null) {
      result.addError(new EntityValidationError(entityName, '实体未注册'))
      return result
    }

    rules.forEach((propertyRules: Array<ValidationRule>, propertyName: string) => {
      const columnName = metadata?.getColumnByProperty(propertyName)?.columnName ?? propertyName
      const hasProperty = entityData.hasProperty(propertyName)
      const value = entityData.getPropertyValue(propertyName)

      for (let i = 0; i < propertyRules.length; i++) {
        const rule = propertyRules[i]
        if (!shouldRunRule(rule, groups)) {
          continue
        }
        validateRule(entityName, propertyName, columnName, rule, hasProperty, value, entityData, options, result)
      }
    })

    return result
  }

  static validateOrThrow(
    entityName: string,
    entityData: EntityData,
    options: ValidationOptions = {}
  ): void {
    const result = EntityValidator.validate(entityName, entityData, options)
    if (result.isValid()) {
      return
    }
    if (result.errors.length === 1) {
      throw result.errors[0]
    }
    const summary = result.getSummary()
    throw new EntityValidationError(entityName, summary)
  }
}

function normalizeGroups(groups?: Array<string>): Array<string> {
  if (!groups || groups.length === 0) {
    return []
  }
  return groups
}

function shouldRunRule(rule: ValidationRule, targetGroups: Array<string>): boolean {
  if (targetGroups.length === 0) {
    return true
  }
  if (!rule.groups || rule.groups.length === 0) {
    return true
  }
  for (let i = 0; i < rule.groups.length; i++) {
    if (targetGroups.includes(rule.groups[i])) {
      return true
    }
  }
  return false
}

function validateRule(
  entityName: string,
  propertyName: string,
  columnName: string,
  rule: ValidationRule,
  hasProperty: boolean,
  value: ValueType | undefined,
  entityData: EntityData,
  options: ValidationOptions,
  result: ValidationResult
): void {
  switch (rule.type) {
    case 'required':
      if (!hasProperty || isEmptyValue(value)) {
        result.addError(new RequiredValidationError(entityName, columnName))
      }
      return
    case 'requiredIf':
      if (shouldRequireForRule(rule, entityData) && (!hasProperty || isEmptyValue(value))) {
        result.addError(new RequiredValidationError(entityName, columnName))
      }
      return
    case 'requiredUnless':
      if (!shouldRequireForRule(rule, entityData) && (!hasProperty || isEmptyValue(value))) {
        result.addError(new RequiredValidationError(entityName, columnName))
      }
      return
    case 'length':
      validateLength(entityName, columnName, rule, value, hasProperty, result)
      return
    case 'email':
      validateEmail(entityName, columnName, value, hasProperty, result)
      return
    case 'min':
      validateMin(entityName, columnName, rule, value, hasProperty, result)
      return
    case 'max':
      validateMax(entityName, columnName, rule, value, hasProperty, result)
      return
    case 'range':
      validateRange(entityName, columnName, rule, value, hasProperty, result)
      return
    case 'pattern':
      validatePattern(entityName, columnName, rule, value, hasProperty, result)
      return
    case 'url':
      validateUrl(entityName, columnName, value, hasProperty, result)
      return
    case 'phone':
      validatePhone(entityName, columnName, value, hasProperty, result)
      return
    case 'date':
      validateDate(entityName, columnName, value, hasProperty, result)
      return
    case 'enum':
      validateEnum(entityName, columnName, rule, value, hasProperty, result)
      return
    case 'custom':
      validateCustom(entityName, propertyName, columnName, rule, value, hasProperty, entityData, result)
      return
    case 'unique':
      validateUnique(entityName, propertyName, columnName, value, hasProperty, entityData, options, result)
      return
    default:
      return
  }
}

function validateRange(
  entityName: string,
  columnName: string,
  rule: ValidationRule,
  value: ValueType | undefined,
  hasProperty: boolean,
  result: ValidationResult
): void {
  if (!hasProperty || value === null || value === undefined) {
    return
  }
  const min = rule.min
  const max = rule.max
  if (min === undefined || max === undefined) {
    return
  }
  const numValue = toNumber(value)
  if (numValue !== null && (numValue < min || numValue > max)) {
    result.addError(new RangeValidationError(entityName, columnName, min, max))
  }
}

function isEmptyValue(value: ValueType | undefined): boolean {
  if (value === null || value === undefined) {
    return true
  }
  if (typeof value === 'string') {
    return value.trim().length === 0
  }
  return false
}

function validateLength(
  entityName: string,
  columnName: string,
  rule: ValidationRule,
  value: ValueType | undefined,
  hasProperty: boolean,
  result: ValidationResult
): void {
  if (!hasProperty || value === null || value === undefined) {
    return
  }
  if (typeof value !== 'string') {
    return
  }
  const min = rule.min !== undefined ? rule.min : 0
  const max = rule.max !== undefined ? rule.max : Number.MAX_SAFE_INTEGER
  if (value.length < min || value.length > max) {
    result.addError(new LengthValidationError(entityName, columnName, min, max))
  }
}

function validateEmail(
  entityName: string,
  columnName: string,
  value: ValueType | undefined,
  hasProperty: boolean,
  result: ValidationResult
): void {
  if (!hasProperty || value === null || value === undefined) {
    return
  }
  if (typeof value !== 'string') {
    return
  }
  const trimmed = value.trim()
  if (trimmed.length === 0) {
    return
  }
  const emailPattern = /^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$/
  const atIndex = trimmed.lastIndexOf('@')
  const domainPart = atIndex >= 0 ? trimmed.slice(atIndex + 1) : ''
  const lastDot = domainPart.lastIndexOf('.')
  const topLevelDomain = lastDot >= 0 ? domainPart.slice(lastDot + 1) : ''

  if (!emailPattern.test(trimmed) || topLevelDomain.length < 2) {
    result.addError(new EmailValidationError(entityName, columnName, trimmed))
  }
}

function toNumber(value: ValueType | undefined): number | null {
  if (typeof value === 'number') {
    return value
  }
  if (typeof value === 'string') {
    const trimmed = value.trim()
    if (trimmed.length === 0) {
      return null
    }
    const parsed = Number(trimmed)
    return Number.isNaN(parsed) ? null : parsed
  }
  return null
}

function validateMin(
  entityName: string,
  columnName: string,
  rule: ValidationRule,
  value: ValueType | undefined,
  hasProperty: boolean,
  result: ValidationResult
): void {
  if (!hasProperty || value === null || value === undefined || rule.min === undefined) {
    return
  }
  const numValue = toNumber(value)
  if (numValue !== null && numValue < rule.min) {
    result.addError(new MinValidationError(entityName, columnName, rule.min))
  }
}

function validateMax(
  entityName: string,
  columnName: string,
  rule: ValidationRule,
  value: ValueType | undefined,
  hasProperty: boolean,
  result: ValidationResult
): void {
  if (!hasProperty || value === null || value === undefined || rule.max === undefined) {
    return
  }
  const numValue = toNumber(value)
  if (numValue !== null && numValue > rule.max) {
    result.addError(new MaxValidationError(entityName, columnName, rule.max))
  }
}

function validatePattern(
  entityName: string,
  columnName: string,
  rule: ValidationRule,
  value: ValueType | undefined,
  hasProperty: boolean,
  result: ValidationResult
): void {
  if (!hasProperty || value === null || value === undefined || rule.pattern === undefined) {
    return
  }
  if (typeof value !== 'string') {
    return
  }
  rule.pattern.lastIndex = 0
  const matched = rule.pattern.test(value)
  rule.pattern.lastIndex = 0
  if (!matched) {
    result.addError(new PatternValidationError(entityName, columnName))
  }
}

function validateUrl(
  entityName: string,
  columnName: string,
  value: ValueType | undefined,
  hasProperty: boolean,
  result: ValidationResult
): void {
  if (!hasProperty || value === null || value === undefined || typeof value !== 'string') {
    return
  }
  const trimmed = value.trim()
  if (trimmed.length === 0) {
    return
  }
  const urlPattern = /^https?:\/\/[^\s/$.?#].[^\s]*$/i
  if (!urlPattern.test(trimmed)) {
    result.addError(new UrlValidationError(entityName, columnName))
  }
}

function validatePhone(
  entityName: string,
  columnName: string,
  value: ValueType | undefined,
  hasProperty: boolean,
  result: ValidationResult
): void {
  if (!hasProperty || value === null || value === undefined || typeof value !== 'string') {
    return
  }
  const trimmed = value.trim()
  if (trimmed.length === 0) {
    return
  }
  const phonePattern = /^\+?[0-9][0-9\-()\s]{6,19}$/
  if (!phonePattern.test(trimmed)) {
    result.addError(new PhoneValidationError(entityName, columnName))
  }
}

function validateDate(
  entityName: string,
  columnName: string,
  value: ValueType | undefined,
  hasProperty: boolean,
  result: ValidationResult
): void {
  if (!hasProperty || value === null || value === undefined) {
    return
  }
  if (value instanceof Date) {
    if (!Number.isNaN(value.getTime())) {
      return
    }
    result.addError(new DateValidationError(entityName, columnName))
    return
  }
  if (typeof value === 'string' || typeof value === 'number') {
    const parsedDate = new Date(value)
    if (!Number.isNaN(parsedDate.getTime())) {
      return
    }
  }
  result.addError(new DateValidationError(entityName, columnName))
}

function validateEnum(
  entityName: string,
  columnName: string,
  rule: ValidationRule,
  value: ValueType | undefined,
  hasProperty: boolean,
  result: ValidationResult
): void {
  if (!hasProperty || value === null || value === undefined || !rule.enumValues) {
    return
  }
  for (let i = 0; i < rule.enumValues.length; i++) {
    if (rule.enumValues[i] === value) {
      return
    }
  }
  result.addError(new EnumValidationError(entityName, columnName))
}

function validateCustom(
  entityName: string,
  propertyName: string,
  columnName: string,
  rule: ValidationRule,
  value: ValueType | undefined,
  hasProperty: boolean,
  entityData: EntityData,
  result: ValidationResult
): void {
  if (!hasProperty || !rule.customValidator) {
    return
  }
  const customResult = rule.customValidator(value, entityData, entityName, propertyName)
  if (customResult === true) {
    return
  }
  const message = typeof customResult === 'string' && customResult.length > 0
    ? customResult
    : `字段 ${columnName} 未通过自定义校验`
  result.addError(new CustomValidationError(entityName, columnName, message))
}

function validateUnique(
  entityName: string,
  propertyName: string,
  columnName: string,
  value: ValueType | undefined,
  hasProperty: boolean,
  entityData: EntityData,
  options: ValidationOptions,
  result: ValidationResult
): void {
  if (!hasProperty || value === null || value === undefined) {
    return
  }
  if (!options.uniqueChecker) {
    return
  }
  const isUnique = options.uniqueChecker(entityName, propertyName, value, entityData)
  if (!isUnique) {
    result.addError(new UniqueValidationError(entityName, columnName))
  }
}

function shouldRequireForRule(rule: ValidationRule, entityData: EntityData): boolean {
  if (!rule.dependentProperty) {
    return false
  }
  const dependencyValue = entityData.getPropertyValue(rule.dependentProperty)
  return isSameValue(dependencyValue, rule.expectedValue)
}

function isSameValue(left: ValueType | undefined, right: ValueType | undefined): boolean {
  if (left === right) {
    return true
  }
  if (left instanceof Date && right instanceof Date) {
    return left.getTime() === right.getTime()
  }
  return false
}
