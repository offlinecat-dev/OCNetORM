import { EntityData } from '../mapping/EntityData'
import { RelationMetadata } from '../core/RelationMetadata'
import { RelationType } from '../types/RelationType'
import { RelationLoadStrategy } from './RelationLoadStrategy'

type OneToManyLoader = (
  entities: Array<EntityData>,
  relation: RelationMetadata
) => Promise<Array<EntityData>>

export class OneToManyRelationLoadStrategy implements RelationLoadStrategy {
  readonly type: RelationType = RelationType.ONE_TO_MANY
  private loader: OneToManyLoader

  constructor(loader: OneToManyLoader) {
    this.loader = loader
  }

  async load(entities: Array<EntityData>, relation: RelationMetadata): Promise<Array<EntityData>> {
    return await this.loader(entities, relation)
  }
}
