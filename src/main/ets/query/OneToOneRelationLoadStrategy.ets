import { EntityData } from '../mapping/EntityData'
import { RelationMetadata } from '../core/RelationMetadata'
import { RelationType } from '../types/RelationType'
import { RelationLoadStrategy } from './RelationLoadStrategy'

type OneToOneLoader = (
  entities: Array<EntityData>,
  relation: RelationMetadata
) => Promise<Array<EntityData>>

export class OneToOneRelationLoadStrategy implements RelationLoadStrategy {
  readonly type: RelationType = RelationType.ONE_TO_ONE
  private loader: OneToOneLoader

  constructor(loader: OneToOneLoader) {
    this.loader = loader
  }

  async load(entities: Array<EntityData>, relation: RelationMetadata): Promise<Array<EntityData>> {
    return await this.loader(entities, relation)
  }
}
