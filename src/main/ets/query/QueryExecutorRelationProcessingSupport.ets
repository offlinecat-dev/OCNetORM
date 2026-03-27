import { QueryBuilder } from './QueryBuilder'
import { EntityData } from '../mapping/EntityData'

type LoadRelations = (entities: Array<EntityData>) => Promise<Array<EntityData>>
type AttachRelationCounts = (entities: Array<EntityData>) => Promise<void>
type AttachLazyRelations = (entities: Array<EntityData>) => void

export class QueryExecutorRelationProcessingSupport {
  private queryBuilder: QueryBuilder
  private loadRelations: LoadRelations
  private attachRelationCounts: AttachRelationCounts
  private attachLazyRelations: AttachLazyRelations

  constructor(
    queryBuilder: QueryBuilder,
    loadRelations: LoadRelations,
    attachRelationCounts: AttachRelationCounts,
    attachLazyRelations: AttachLazyRelations
  ) {
    this.queryBuilder = queryBuilder
    this.loadRelations = loadRelations
    this.attachRelationCounts = attachRelationCounts
    this.attachLazyRelations = attachLazyRelations
  }

  async process(results: Array<EntityData>): Promise<Array<EntityData>> {
    let processed = results
    if (this.queryBuilder.hasRelations() && processed.length > 0) {
      processed = await this.loadRelations(processed)
    }
    if (this.queryBuilder.hasRelationCounts() && processed.length > 0) {
      await this.attachRelationCounts(processed)
    }
    if (this.queryBuilder.hasLazyRelations() && processed.length > 0) {
      this.attachLazyRelations(processed)
    }
    return processed
  }
}
