/**
 * 验证元数据存储
 * 管理实体的验证规则
 */

import { MetadataStorage } from '../core/MetadataStorage'
import { EntityNotRegisteredError } from '../errors/MetadataError'

export type ValidationRuleType = 'required' | 'length' | 'email'

export interface ValidationRule {
  type: ValidationRuleType
  min?: number
  max?: number
}

export class ValidationMetadataStorage {
  private static instance: ValidationMetadataStorage | null = null
  private rules: Map<string, Map<string, Array<ValidationRule>>> = new Map()

  private constructor() {
  }

  static getInstance(): ValidationMetadataStorage {
    if (ValidationMetadataStorage.instance === null) {
      ValidationMetadataStorage.instance = new ValidationMetadataStorage()
    }
    return ValidationMetadataStorage.instance
  }

  static resetInstance(): void {
    ValidationMetadataStorage.instance = null
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
