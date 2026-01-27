/**
 * 验证装饰器
 * 用于声明实体属性的验证规则
 */

import { MetadataStorage } from '../core/MetadataStorage'
import { EntityNotRegisteredError } from '../errors/MetadataError'
import { ValidationMetadataStorage, ValidationRule } from './ValidationMetadataStorage'

export type StringPropertyDecorator = (target: Object, propertyKey: string) => void

export interface LengthOptions {
  min?: number
  max?: number
}

function ensureEntityRegistered(target: Object): string {
  const entityName = target.constructor.name
  const storage = MetadataStorage.getInstance()
  if (!storage.hasEntity(entityName)) {
    throw new EntityNotRegisteredError(entityName)
  }
  return entityName
}

function registerRule(entityName: string, propertyName: string, rule: ValidationRule): void {
  ValidationMetadataStorage.getInstance().registerRule(entityName, propertyName, rule)
}

export function Required(): StringPropertyDecorator {
  return (target: Object, propertyKey: string) => {
    const entityName = ensureEntityRegistered(target)
    registerRule(entityName, propertyKey, { type: 'required' })
  }
}

export function Length(options: LengthOptions = {}): StringPropertyDecorator {
  return (target: Object, propertyKey: string) => {
    const entityName = ensureEntityRegistered(target)
    registerRule(entityName, propertyKey, {
      type: 'length',
      min: options.min,
      max: options.max
    })
  }
}

export function Email(): StringPropertyDecorator {
  return (target: Object, propertyKey: string) => {
    const entityName = ensureEntityRegistered(target)
    registerRule(entityName, propertyKey, { type: 'email' })
  }
}
