import { EntityData } from '../mapping/EntityData'
import { RelationMetadata } from '../core/RelationMetadata'
import { RelationType } from '../types/RelationType'
import { RelationLoadStrategy } from './RelationLoadStrategy'

type ManyToOneLoader = (
  entities: Array<EntityData>,
  relation: RelationMetadata
) => Promise<Array<EntityData>>

export class ManyToOneRelationLoadStrategy implements RelationLoadStrategy {
  readonly type: RelationType = RelationType.MANY_TO_ONE
  private loader: ManyToOneLoader

  constructor(loader: ManyToOneLoader) {
    this.loader = loader
  }

  async load(entities: Array<EntityData>, relation: RelationMetadata): Promise<Array<EntityData>> {
    return await this.loader(entities, relation)
  }
}
