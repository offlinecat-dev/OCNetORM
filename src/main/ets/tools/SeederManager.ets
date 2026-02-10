import { Repository } from '../repository/Repository'

export interface Seeder {
  entityName?: string
  run(repo: Repository): Promise<void>
}

export class SeederClass {
  static entityName: string = ''
  entityName?: string
  async run(_repo: Repository): Promise<void> {
    return
  }
}

export type SeederEntry = Seeder

export class SeederExecutionItem {
  seederName: string = ''
  entityName: string = ''
  success: boolean = false
  duration: number = 0
  errorMessage: string = ''

  static createSuccess(seederName: string, entityName: string, duration: number): SeederExecutionItem {
    const item = new SeederExecutionItem()
    item.seederName = seederName
    item.entityName = entityName
    item.success = true
    item.duration = duration
    return item
  }

  static createFailure(seederName: string, entityName: string, duration: number, errorMessage: string): SeederExecutionItem {
    const item = new SeederExecutionItem()
    item.seederName = seederName
    item.entityName = entityName
    item.success = false
    item.duration = duration
    item.errorMessage = errorMessage
    return item
  }
}

export class SeederExecutionResult {
  success: boolean = false
  successCount: number = 0
  failureCount: number = 0
  items: Array<SeederExecutionItem> = []

  static create(items: Array<SeederExecutionItem>): SeederExecutionResult {
    const result = new SeederExecutionResult()
    result.items = items
    for (let i = 0; i < items.length; i++) {
      if (items[i].success) {
        result.successCount++
      } else {
        result.failureCount++
      }
    }
    result.success = result.failureCount === 0
    return result
  }
}

export class SeederManager {
  static async run(seeders: Array<SeederEntry>): Promise<SeederExecutionResult> {
    const items: Array<SeederExecutionItem> = []
    for (let i = 0; i < seeders.length; i++) {
      const entry = seeders[i]
      const seeder = SeederManager.instantiateSeeder(entry)
      const seederName = SeederManager.resolveSeederName(seeder)
      const entityName = SeederManager.resolveEntityName(seeder, seederName)
      const startTime = Date.now()
      try {
        await seeder.run(new Repository(entityName))
        const duration = Date.now() - startTime
        items.push(SeederExecutionItem.createSuccess(seederName, entityName, duration))
      } catch (error) {
        const duration = Date.now() - startTime
        const errorMessage = error instanceof Error ? error.message : String(error)
        items.push(SeederExecutionItem.createFailure(seederName, entityName, duration, errorMessage))
      }
    }
    return SeederExecutionResult.create(items)
  }

  private static instantiateSeeder(entry: SeederEntry): Seeder {
    return entry
  }

  private static resolveSeederName(seeder: Seeder): string {
    const ctor = seeder.constructor as Function
    return ctor.name ? ctor.name : 'AnonymousSeeder'
  }

  private static resolveEntityName(seeder: Seeder, seederName: string): string {
    if (seeder.entityName !== undefined && seeder.entityName.trim().length > 0) {
      return seeder.entityName.trim()
    }
    const inferred = SeederManager.inferEntityName(seederName)
    if (inferred.length === 0) {
      throw new Error(`无法推断 Seeder 对应的实体名: ${seederName}`)
    }
    return inferred
  }

  private static inferEntityName(seederName: string): string {
    const trimmed = seederName.trim()
    if (trimmed.endsWith('Seeder') && trimmed.length > 6) {
      return trimmed.substring(0, trimmed.length - 6)
    }
    return trimmed
  }
}
