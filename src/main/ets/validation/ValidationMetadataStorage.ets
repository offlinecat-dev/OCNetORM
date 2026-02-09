/**
 * 验证元数据存储
 * 管理实体的验证规则
 */

import { MetadataStorage } from '../core/MetadataStorage'
import { EntityNotRegisteredError } from '../errors/MetadataError'
import { EntityData } from '../mapping/EntityData'
import { ValueType } from '../types/ValueTypes'

export type ValidationRuleType =
  | 'required'
  | 'length'
  | 'email'
  | 'min'
  | 'max'
  | 'range'
  | 'pattern'
  | 'unique'
  | 'phone'
  | 'url'
  | 'date'
  | 'enum'
  | 'custom'
  | 'requiredIf'
  | 'requiredUnless'

export type CustomValidator = (
  value: ValueType | undefined,
  entityData: EntityData,
  entityName: string,
  propertyName: string
) => boolean | string

export interface ValidationRule {
  type: ValidationRuleType
  min?: number
  max?: number
  pattern?: RegExp
  enumValues?: Array<ValueType>
  customValidator?: CustomValidator
  dependentProperty?: string
  expectedValue?: ValueType
  groups?: Array<string>
}

export class ValidationMetadataStorage {
  private static instance: ValidationMetadataStorage = new ValidationMetadataStorage()
  private rules: Map<string, Map<string, Array<ValidationRule>>> = new Map()

  private constructor() {
  }

  static getInstance(): ValidationMetadataStorage {
    return ValidationMetadataStorage.instance
  }

  static resetInstance(): void {
    ValidationMetadataStorage.instance = new ValidationMetadataStorage()
  }

  registerRule(entityName: string, propertyName: string, rule: ValidationRule): void {
    this.ensureEntity(entityName)
    let entityRules = this.rules.get(entityName)
    if (!entityRules) {
      entityRules = new Map()
      this.rules.set(entityName, entityRules)
    }
    let propertyRules = entityRules.get(propertyName)
    if (!propertyRules) {
      propertyRules = []
      entityRules.set(propertyName, propertyRules)
    }
    propertyRules.push(rule)
  }

  getRules(entityName: string): Map<string, Array<ValidationRule>> {
    const entityRules = this.rules.get(entityName)
    if (!entityRules) {
      return new Map()
    }
    return entityRules
  }

  getRulesForProperty(entityName: string, propertyName: string): Array<ValidationRule> {
    const entityRules = this.rules.get(entityName)
    if (!entityRules) {
      return []
    }
    const propertyRules = entityRules.get(propertyName)
    return propertyRules ? propertyRules : []
  }

  hasRules(entityName: string): boolean {
    const entityRules = this.rules.get(entityName)
    return !!entityRules && entityRules.size > 0
  }

  clear(): void {
    this.rules.clear()
  }

  private ensureEntity(entityName: string): void {
    const storage = MetadataStorage.getInstance()
    if (!storage.hasEntity(entityName)) {
      throw new EntityNotRegisteredError(entityName)
    }
  }
}
