import { MetadataStorage } from '../core/MetadataStorage'
import { RelationCountOption } from './RelationQueryOptions'
import { RelationNotFoundError } from '../errors/RelationError'
import { InvalidConditionError } from '../errors/QueryError'

export class QueryBuilderRelationStrategySupport {
  private entityName: string
  private relationNames: Array<string>
  private lazyRelationNames: Array<string>
  private relationCountOptions: Array<RelationCountOption>

  constructor(
    entityName: string,
    relationNames: Array<string>,
    lazyRelationNames: Array<string>,
    relationCountOptions: Array<RelationCountOption>
  ) {
    this.entityName = entityName
    this.relationNames = relationNames
    this.lazyRelationNames = lazyRelationNames
    this.relationCountOptions = relationCountOptions
  }

  normalizeRelationPath(relationPath: string): string {
    return relationPath.trim()
  }

  splitRelationPathOrThrow(relationPath: string): Array<string> {
    const normalizedPath = this.normalizeRelationPath(relationPath)
    if (normalizedPath.length === 0) {
      throw new RelationNotFoundError(this.entityName, relationPath)
    }
    const segments = normalizedPath.split('.')
    for (let i = 0; i < segments.length; i++) {
      if (segments[i].trim().length === 0) {
        throw new RelationNotFoundError(this.entityName, relationPath)
      }
      segments[i] = segments[i].trim()
    }
    return segments
  }

  resolveRelationPathTargetEntity(relationPath: string): string {
    const segments = this.splitRelationPathOrThrow(relationPath)
    let currentEntityName = this.entityName
    const metadataStorage = MetadataStorage.getInstance()
    for (let i = 0; i < segments.length; i++) {
      const relation = metadataStorage.getRelation(currentEntityName, segments[i])
      if (relation === null) {
        throw new RelationNotFoundError(currentEntityName, segments[i])
      }
      if (relation.targetEntity.length === 0) {
        return ''
      }
      currentEntityName = relation.targetEntity
    }
    return currentEntityName
  }

  registerWith(relationName: string): string {
    const normalizedRelationPath = this.normalizeRelationPath(relationName)
    this.resolveRelationPathTargetEntity(normalizedRelationPath)
    if (!this.relationNames.includes(normalizedRelationPath)) {
      this.relationNames.push(normalizedRelationPath)
    }
    const lazyIndex = this.lazyRelationNames.indexOf(normalizedRelationPath)
    if (lazyIndex >= 0) {
      this.lazyRelationNames.splice(lazyIndex, 1)
    }
    return normalizedRelationPath
  }

  registerWithLazy(relationName: string): string {
    const normalizedRelationPath = this.normalizeRelationPath(relationName)
    const relation = MetadataStorage.getInstance().getRelation(this.entityName, normalizedRelationPath)
    if (relation === null) {
      throw new RelationNotFoundError(this.entityName, normalizedRelationPath)
    }
    if (!this.lazyRelationNames.includes(normalizedRelationPath) && !this.relationNames.includes(normalizedRelationPath)) {
      this.lazyRelationNames.push(normalizedRelationPath)
    }
    return normalizedRelationPath
  }

  registerWithCount(relationPath: string, alias: string = ''): string {
    const normalizedRelationPath = this.normalizeRelationPath(relationPath)
    this.resolveRelationPathTargetEntity(normalizedRelationPath)
    const resolvedAlias = alias.trim().length > 0 ? alias.trim() : `${normalizedRelationPath.replace(/\./g, '_')}_count`
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(resolvedAlias)) {
      throw new InvalidConditionError('withCount', `非法别名: ${resolvedAlias}`)
    }
    for (let i = 0; i < this.relationCountOptions.length; i++) {
      if (this.relationCountOptions[i].relationPath === normalizedRelationPath) {
        this.relationCountOptions[i].alias = resolvedAlias
        return normalizedRelationPath
      }
    }
    this.relationCountOptions.push(new RelationCountOption(normalizedRelationPath, resolvedAlias))
    return normalizedRelationPath
  }
}
