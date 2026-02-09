/**
 * 级联操作处理器
 * 负责在保存/删除时处理关联实体的级联行为
 */

import { EntityData } from '../mapping/EntityData'
import { MetadataStorage } from '../core/MetadataStorage'
import { CascadeSetting } from '../core/RelationMetadata'
import { RelationType } from '../types/RelationType'
import { ValueType } from '../types/ValueTypes'
import { ExecutionError } from '../errors/DatabaseError'

export type CascadeOperation = 'insert' | 'update' | 'remove'

export interface CascadeResultLike {
  success: boolean
  errorMessage?: string
}

export interface CascadeRepository {
  save(entityData: EntityData): Promise<CascadeResultLike>
  remove(entityData: EntityData): Promise<CascadeResultLike>
  sync(sourceId: ValueType, targetIds: Array<ValueType>, relationName: string): Promise<CascadeResultLike>
}

export type CascadeRepositoryFactory = (entityName: string) => CascadeRepository

/**
 * 级联处理器
 */
export class CascadeHandler {
  private static instance: CascadeHandler = new CascadeHandler()

  private constructor() {
  }

  static getInstance(): CascadeHandler {
    return CascadeHandler.instance
  }

  static resetInstance(): void {
    CascadeHandler.instance = new CascadeHandler()
  }

  async handleBeforeSave(
    entityName: string,
    entityData: EntityData,
    operation: CascadeOperation,
    repositoryFactory: CascadeRepositoryFactory
  ): Promise<void> {
    if (operation !== 'insert' && operation !== 'update') {
      return
    }

    const relations = MetadataStorage.getInstance().getRelations(entityName)

    for (let i = 0; i < relations.length; i++) {
      const relation = relations[i]
      if (!this.isCascadeEnabled(relation.cascade, operation)) {
        continue
      }

      const isSourceSideOneToOne = relation.type === RelationType.ONE_TO_ONE && relation.foreignKeySide === 'source'
      if (relation.type !== RelationType.MANY_TO_ONE && !isSourceSideOneToOne) {
        continue
      }

      if (!entityData.hasRelated(relation.propertyName)) {
        continue
      }

      const related = entityData.getRelatedSingle(relation.propertyName)
      if (related === null) {
        continue
      }

      const targetRepo = repositoryFactory(relation.targetEntity)
      const result = await targetRepo.save(related)
      if (!result.success) {
        throw new ExecutionError('CASCADE', result.errorMessage ? result.errorMessage : '级联保存失败')
      }

      const targetPk = this.getPrimaryKeyValue(relation.targetEntity, related)
      if (targetPk !== null) {
        const sourceFkProperty = this.resolvePropertyName(entityName, relation.inverseKey)
        entityData.setPropertyValue(sourceFkProperty, targetPk)
      }
    }
  }

  async handleAfterSave(
    entityName: string,
    entityData: EntityData,
    operation: CascadeOperation,
    sourceRepository: CascadeRepository,
    repositoryFactory: CascadeRepositoryFactory
  ): Promise<void> {
    if (operation !== 'insert' && operation !== 'update') {
      return
    }

    const sourcePk = this.getPrimaryKeyValue(entityName, entityData)
    if (sourcePk === null) {
      return
    }

    const relations = MetadataStorage.getInstance().getRelations(entityName)

    for (let i = 0; i < relations.length; i++) {
      const relation = relations[i]
      if (!this.isCascadeEnabled(relation.cascade, operation)) {
        continue
      }

      const isTargetSideOneToOne = relation.type === RelationType.ONE_TO_ONE && relation.foreignKeySide === 'target'

      if (relation.type === RelationType.ONE_TO_MANY || isTargetSideOneToOne) {
        if (!entityData.hasRelated(relation.propertyName)) {
          continue
        }
        const targets = isTargetSideOneToOne
          ? this.toArray(entityData.getRelatedSingle(relation.propertyName))
          : entityData.getRelatedArray(relation.propertyName)

        if (targets.length === 0) {
          continue
        }

        const targetRepo = repositoryFactory(relation.targetEntity)
        const targetFkProperty = this.resolvePropertyName(relation.targetEntity, relation.inverseKey)
        for (let j = 0; j < targets.length; j++) {
          targets[j].setPropertyValue(targetFkProperty, sourcePk)
          const result = await targetRepo.save(targets[j])
          if (!result.success) {
            throw new ExecutionError('CASCADE', result.errorMessage ? result.errorMessage : '级联保存失败')
          }
        }
        continue
      }

      if (relation.type === RelationType.MANY_TO_MANY) {
        if (!entityData.hasRelated(relation.propertyName)) {
          continue
        }
        const targets = entityData.getRelatedArray(relation.propertyName)
        const targetRepo = repositoryFactory(relation.targetEntity)
        const targetIds: Array<ValueType> = []

        for (let j = 0; j < targets.length; j++) {
          const result = await targetRepo.save(targets[j])
          if (!result.success) {
            throw new ExecutionError('CASCADE', result.errorMessage ? result.errorMessage : '级联保存失败')
          }
          const targetPk = this.getPrimaryKeyValue(relation.targetEntity, targets[j])
          if (targetPk !== null) {
            targetIds.push(targetPk)
          }
        }

        if (sourcePk !== null) {
          const syncResult = await sourceRepository.sync(sourcePk, targetIds, relation.propertyName)
          if (!syncResult.success) {
            throw new ExecutionError('CASCADE', syncResult.errorMessage ? syncResult.errorMessage : '级联同步失败')
          }
        }
      }
    }
  }

  async handleBeforeRemove(
    entityName: string,
    entityData: EntityData,
    sourceRepository: CascadeRepository,
    repositoryFactory: CascadeRepositoryFactory
  ): Promise<void> {
    const relations = MetadataStorage.getInstance().getRelations(entityName)
    const sourcePk = this.getPrimaryKeyValue(entityName, entityData)

    for (let i = 0; i < relations.length; i++) {
      const relation = relations[i]
      if (!this.isCascadeEnabled(relation.cascade, 'remove')) {
        continue
      }

      if (relation.type === RelationType.MANY_TO_MANY && sourcePk !== null) {
        const syncResult = await sourceRepository.sync(sourcePk, [], relation.propertyName)
        if (!syncResult.success) {
          throw new ExecutionError('CASCADE', syncResult.errorMessage ? syncResult.errorMessage : '级联解除失败')
        }
        continue
      }

      if (!entityData.hasRelated(relation.propertyName)) {
        continue
      }

      const targetRepo = repositoryFactory(relation.targetEntity)

      if (relation.type === RelationType.ONE_TO_MANY || relation.type === RelationType.MANY_TO_MANY) {
        const targets = entityData.getRelatedArray(relation.propertyName)
        for (let j = 0; j < targets.length; j++) {
          const result = await targetRepo.remove(targets[j])
          if (!result.success) {
            throw new ExecutionError('CASCADE', result.errorMessage ? result.errorMessage : '级联删除失败')
          }
        }
        continue
      }

      const related = entityData.getRelatedSingle(relation.propertyName)
      if (related !== null) {
        const result = await targetRepo.remove(related)
        if (!result.success) {
          throw new ExecutionError('CASCADE', result.errorMessage ? result.errorMessage : '级联删除失败')
        }
      }
    }
  }

  private isCascadeEnabled(cascade: CascadeSetting | null, operation: CascadeOperation): boolean {
    if (cascade === null || cascade === undefined) {
      return false
    }
    if (cascade === true) {
      return true
    }
    if (typeof cascade === 'object') {
      if (operation === 'insert') {
        return cascade.insert === true
      }
      if (operation === 'update') {
        return cascade.update === true
      }
      if (operation === 'remove') {
        return cascade.remove === true
      }
    }
    return false
  }

  private resolvePropertyName(entityName: string, key: string): string {
    const metadata = MetadataStorage.getInstance().getEntityMetadata(entityName)
    if (metadata === null) {
      return key
    }
    const column = metadata.getColumnByName(key)
    if (column !== null) {
      return column.propertyName
    }
    const columnByProperty = metadata.getColumnByProperty(key)
    if (columnByProperty !== null) {
      return columnByProperty.propertyName
    }
    return key
  }

  private getPrimaryKeyValue(entityName: string, entityData: EntityData): ValueType {
    const metadata = MetadataStorage.getInstance().getEntityMetadata(entityName)
    if (metadata === null) {
      return null
    }
    const pkColumn = metadata.getPrimaryKeyColumn()
    if (pkColumn === null) {
      return null
    }
    const prop = entityData.getProperty(pkColumn.propertyName)
    if (prop !== null) {
      return prop.value
    }
    return entityData.getPropertyValue(pkColumn.propertyName)
  }

  private toArray(entity: EntityData | null): Array<EntityData> {
    if (entity === null) {
      return []
    }
    return [entity]
  }
}
