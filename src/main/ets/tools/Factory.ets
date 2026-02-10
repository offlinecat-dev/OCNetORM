import { EntityMetadata } from '../core/EntityMetadata'
import { MetadataStorage } from '../core/MetadataStorage'
import { EntityDataInput } from '../mapping/EntityDataInput'
import { EntityData } from '../mapping/EntityData'
import { Repository } from '../repository/Repository'
import { ValueType } from '../types/ValueTypes'

export interface FactoryNumberOptions {
  min?: number
  max?: number
}

export type FactoryRecord = Record<string, ValueType>
export type FactoryBuilder = (faker: FactoryFaker, index: number) => EntityDataInput | FactoryRecord
export type FactoryOverridesBuilder = (index: number) => FactoryRecord

export class FactoryFaker {
  private static readonly FIRST_NAMES: Array<string> = ['Alex', 'Chris', 'Jordan', 'Taylor', 'Morgan']
  private static readonly LAST_NAMES: Array<string> = ['Li', 'Wang', 'Chen', 'Smith', 'Johnson']

  name(): string {
    const first = this.pick(FactoryFaker.FIRST_NAMES)
    const last = this.pick(FactoryFaker.LAST_NAMES)
    return `${first} ${last}`
  }

  email(domain: string = 'example.com'): string {
    const local = `user_${Date.now()}_${Math.floor(Math.random() * 100000)}`
    return `${local}@${domain}`
  }

  number(options?: FactoryNumberOptions): number {
    const min = options?.min !== undefined ? Math.floor(options.min) : 0
    const max = options?.max !== undefined ? Math.floor(options.max) : 100
    const low = min <= max ? min : max
    const high = min <= max ? max : min
    return low + Math.floor(Math.random() * (high - low + 1))
  }

  boolean(trueProbability: number = 0.5): boolean {
    const probability = trueProbability < 0 ? 0 : (trueProbability > 1 ? 1 : trueProbability)
    return Math.random() < probability
  }

  private pick(values: Array<string>): string {
    if (values.length === 0) {
      return ''
    }
    return values[Math.floor(Math.random() * values.length)]
  }
}

export class EntityFactory {
  private entityName: string
  private metadata: EntityMetadata
  private builder: FactoryBuilder
  private faker: FactoryFaker = new FactoryFaker()

  constructor(entityName: string, builder: FactoryBuilder) {
    this.entityName = entityName
    const metadata = MetadataStorage.getInstance().getEntityMetadata(entityName)
    if (metadata === null) {
      throw new Error(`实体未注册: ${entityName}`)
    }
    this.metadata = metadata
    this.builder = builder
  }

  async make(overrides?: FactoryRecord): Promise<EntityData> {
    return this.buildEntity(0, overrides)
  }

  async makeMany(count: number, overridesBuilder?: FactoryOverridesBuilder): Promise<Array<EntityData>> {
    const result: Array<EntityData> = []
    const total = count > 0 ? Math.floor(count) : 0
    for (let i = 0; i < total; i++) {
      const overrides = overridesBuilder ? overridesBuilder(i) : undefined
      result.push(this.buildEntity(i, overrides))
    }
    return result
  }

  async create(overrides?: FactoryRecord): Promise<EntityData> {
    const entity = this.buildEntity(0, overrides)
    const repo = new Repository(this.entityName)
    const result = await repo.save(entity)
    if (!result.success) {
      throw new Error(result.errorMessage.length > 0 ? result.errorMessage : 'Factory create 保存失败')
    }
    return entity
  }

  async createMany(count: number, overridesBuilder?: FactoryOverridesBuilder): Promise<Array<EntityData>> {
    const entities = await this.makeMany(count, overridesBuilder)
    const repo = new Repository(this.entityName)
    const saved: Array<EntityData> = []
    for (let i = 0; i < entities.length; i++) {
      const result = await repo.save(entities[i])
      if (!result.success) {
        throw new Error(result.errorMessage.length > 0 ? result.errorMessage : 'Factory createMany 保存失败')
      }
      saved.push(entities[i])
    }
    return saved
  }

  private buildEntity(index: number, overrides?: FactoryRecord): EntityData {
    const built = this.builder(this.faker, index)
    const input = this.toInput(built)
    if (overrides !== undefined) {
      const overrideKeys = Object.keys(overrides)
      for (let i = 0; i < overrideKeys.length; i++) {
        const key = overrideKeys[i]
        input.set(key, overrides[key])
      }
    }
    return EntityData.from(this.entityName, input)
  }

  private toInput(source: EntityDataInput | FactoryRecord): EntityDataInput {
    if (source instanceof EntityDataInput) {
      return source
    }
    const input = EntityDataInput.create()
    const keys = Object.keys(source)
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i]
      if (this.hasMetadataProperty(key)) {
        input.set(key, source[key])
      }
    }
    return input
  }

  private hasMetadataProperty(propertyName: string): boolean {
    for (let i = 0; i < this.metadata.columns.length; i++) {
      if (this.metadata.columns[i].propertyName === propertyName) {
        return true
      }
    }
    return false
  }
}

export function defineFactory(entityName: string, builder: FactoryBuilder): EntityFactory {
  return new EntityFactory(entityName, builder)
}
