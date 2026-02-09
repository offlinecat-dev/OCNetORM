import { EntityData } from '../mapping/EntityData'
import { RelationMetadata } from '../core/RelationMetadata'
import { RelationType } from '../types/RelationType'

export interface RelationLoadStrategy {
  readonly type: RelationType

  load(
    entities: Array<EntityData>,
    relation: RelationMetadata
  ): Promise<Array<EntityData>>
}
