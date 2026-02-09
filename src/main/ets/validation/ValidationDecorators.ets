/**
 * 验证装饰器
 * 用于声明实体属性的验证规则
 */

import { MetadataStorage } from '../core/MetadataStorage'
import { EntityNotRegisteredError } from '../errors/MetadataError'
import { ValueType } from '../types/ValueTypes'
import {
  ValidationMetadataStorage,
  ValidationRule,
  CustomValidator
} from './ValidationMetadataStorage'

export type StringPropertyDecorator = (target: Object, propertyKey: string) => void

export interface ValidationGroupsOptions {
  groups?: Array<string>
}

export interface LengthOptions {
  min?: number
  max?: number
  groups?: Array<string>
}

export interface MinMaxOptions {
  groups?: Array<string>
}

export interface EnumOptions {
  groups?: Array<string>
}

export interface PatternOptions {
  groups?: Array<string>
}

export interface ConditionalRequiredOptions {
  groups?: Array<string>
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

function normalizeGroups(groups?: Array<string>): Array<string> | undefined {
  if (!groups || groups.length === 0) {
    return undefined
  }
  return groups
}

export function Required(options: ValidationGroupsOptions = {}): StringPropertyDecorator {
  return (target: Object, propertyKey: string) => {
    const entityName = ensureEntityRegistered(target)
    registerRule(entityName, propertyKey, {
      type: 'required',
      groups: normalizeGroups(options.groups)
    })
  }
}

export function Length(options: LengthOptions = {}): StringPropertyDecorator {
  return (target: Object, propertyKey: string) => {
    const entityName = ensureEntityRegistered(target)
    registerRule(entityName, propertyKey, {
      type: 'length',
      min: options.min,
      max: options.max,
      groups: normalizeGroups(options.groups)
    })
  }
}

export function Email(options: ValidationGroupsOptions = {}): StringPropertyDecorator {
  return (target: Object, propertyKey: string) => {
    const entityName = ensureEntityRegistered(target)
    registerRule(entityName, propertyKey, {
      type: 'email',
      groups: normalizeGroups(options.groups)
    })
  }
}

export function Min(min: number, options: MinMaxOptions = {}): StringPropertyDecorator {
  return (target: Object, propertyKey: string) => {
    const entityName = ensureEntityRegistered(target)
    registerRule(entityName, propertyKey, {
      type: 'min',
      min: min,
      groups: normalizeGroups(options.groups)
    })
  }
}

export function Max(max: number, options: MinMaxOptions = {}): StringPropertyDecorator {
  return (target: Object, propertyKey: string) => {
    const entityName = ensureEntityRegistered(target)
    registerRule(entityName, propertyKey, {
      type: 'max',
      max: max,
      groups: normalizeGroups(options.groups)
    })
  }
}

export function Range(min: number, max: number, options: MinMaxOptions = {}): StringPropertyDecorator {
  return (target: Object, propertyKey: string) => {
    const entityName = ensureEntityRegistered(target)
    registerRule(entityName, propertyKey, {
      type: 'range',
      min: min,
      max: max,
      groups: normalizeGroups(options.groups)
    })
  }
}

export function Pattern(pattern: RegExp, options: PatternOptions = {}): StringPropertyDecorator {
  return (target: Object, propertyKey: string) => {
    const entityName = ensureEntityRegistered(target)
    registerRule(entityName, propertyKey, {
      type: 'pattern',
      pattern: pattern,
      groups: normalizeGroups(options.groups)
    })
  }
}

export function Enum(values: Array<ValueType>, options: EnumOptions = {}): StringPropertyDecorator {
  return (target: Object, propertyKey: string) => {
    const entityName = ensureEntityRegistered(target)
    registerRule(entityName, propertyKey, {
      type: 'enum',
      enumValues: values,
      groups: normalizeGroups(options.groups)
    })
  }
}

export function URL(options: ValidationGroupsOptions = {}): StringPropertyDecorator {
  return (target: Object, propertyKey: string) => {
    const entityName = ensureEntityRegistered(target)
    registerRule(entityName, propertyKey, { type: 'url', groups: normalizeGroups(options.groups) })
  }
}

export function Phone(options: ValidationGroupsOptions = {}): StringPropertyDecorator {
  return (target: Object, propertyKey: string) => {
    const entityName = ensureEntityRegistered(target)
    registerRule(entityName, propertyKey, { type: 'phone', groups: normalizeGroups(options.groups) })
  }
}

export function DateRule(options: ValidationGroupsOptions = {}): StringPropertyDecorator {
  return (target: Object, propertyKey: string) => {
    const entityName = ensureEntityRegistered(target)
    registerRule(entityName, propertyKey, { type: 'date', groups: normalizeGroups(options.groups) })
  }
}

export function Custom(
  customValidator: CustomValidator,
  options: ValidationGroupsOptions = {}
): StringPropertyDecorator {
  return (target: Object, propertyKey: string) => {
    const entityName = ensureEntityRegistered(target)
    registerRule(entityName, propertyKey, {
      type: 'custom',
      customValidator: customValidator,
      groups: normalizeGroups(options.groups)
    })
  }
}

export function Unique(options: ValidationGroupsOptions = {}): StringPropertyDecorator {
  return (target: Object, propertyKey: string) => {
    const entityName = ensureEntityRegistered(target)
    registerRule(entityName, propertyKey, { type: 'unique', groups: normalizeGroups(options.groups) })
  }
}

export function RequiredIf(
  dependentProperty: string,
  expectedValue: ValueType,
  options: ConditionalRequiredOptions = {}
): StringPropertyDecorator {
  return (target: Object, propertyKey: string) => {
    const entityName = ensureEntityRegistered(target)
    registerRule(entityName, propertyKey, {
      type: 'requiredIf',
      dependentProperty: dependentProperty,
      expectedValue: expectedValue,
      groups: normalizeGroups(options.groups)
    })
  }
}

export function RequiredUnless(
  dependentProperty: string,
  expectedValue: ValueType,
  options: ConditionalRequiredOptions = {}
): StringPropertyDecorator {
  return (target: Object, propertyKey: string) => {
    const entityName = ensureEntityRegistered(target)
    registerRule(entityName, propertyKey, {
      type: 'requiredUnless',
      dependentProperty: dependentProperty,
      expectedValue: expectedValue,
      groups: normalizeGroups(options.groups)
    })
  }
}

export { DateRule as Date }
