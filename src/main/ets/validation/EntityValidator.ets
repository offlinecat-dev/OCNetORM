/**
 * 实体验证器
 * 用于执行验证规则并返回验证结果
 */

import { EntityData } from '../mapping/DataMapper'
import { MetadataStorage } from '../core/MetadataStorage'
import { ValueType } from '../types/ValueTypes'
import { ValidationMetadataStorage, ValidationRule } from './ValidationMetadataStorage'
import {
  ValidationError,
  RequiredValidationError,
  LengthValidationError,
  EmailValidationError,
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

export class EntityValidator {
  static validate(entityName: string, entityData: EntityData): ValidationResult {
    const result = new ValidationResult()
    const rules = ValidationMetadataStorage.getInstance().getRules(entityName)
    if (rules.size === 0) {
      return result
    }

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
        switch (rule.type) {
          case 'required':
            if (!hasProperty || isEmptyValue(value)) {
              result.addError(new RequiredValidationError(entityName, columnName))
            }
            break
          case 'length':
            if (!hasProperty || value === null) {
              break
            }
            validateLength(entityName, columnName, rule, value, result)
            break
          case 'email':
            if (!hasProperty || value === null) {
              break
            }
            validateEmail(entityName, columnName, value, result)
            break
          default:
            break
        }
      }
    })

    return result
  }

  static validateOrThrow(entityName: string, entityData: EntityData): void {
    const result = EntityValidator.validate(entityName, entityData)
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

function isEmptyValue(value: ValueType): boolean {
  if (value === null) {
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
  value: ValueType,
  result: ValidationResult
): void {
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
  value: ValueType,
  result: ValidationResult
): void {
  if (typeof value !== 'string') {
    return
  }
  const trimmed = value.trim()
  if (trimmed.length === 0) {
    return
  }
  const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
  if (!emailPattern.test(trimmed)) {
    result.addError(new EmailValidationError(entityName, columnName, trimmed))
  }
}
