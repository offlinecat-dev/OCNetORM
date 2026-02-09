import { EntityData } from '../mapping/EntityData'
import { RelationMetadata } from '../core/RelationMetadata'
import { ManyToManyMetadata } from '../core/ManyToManyMetadata'
import { RelationType } from '../types/RelationType'
import { RelationLoadStrategy } from './RelationLoadStrategy'

type ManyToManyLoader = (
  entities: Array<EntityData>,
  relation: ManyToManyMetadata
) => Promise<Array<EntityData>>

export class ManyToManyRelationLoadStrategy implements RelationLoadStrategy {
  readonly type: RelationType = RelationType.MANY_TO_MANY
  private loader: ManyToManyLoader

  constructor(loader: ManyToManyLoader) {
    this.loader = loader
  }

  async load(entities: Array<EntityData>, relation: RelationMetadata): Promise<Array<EntityData>> {
    return await this.loader(entities, relation as ManyToManyMetadata)
  }
}
