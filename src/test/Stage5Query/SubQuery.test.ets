import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { SubQuery } from '../../main/ets/query/SubQuery';
import { ConditionOperator } from '../../main/ets/types/ConditionOperator';
import { LogicalOperator } from '../../main/ets/query/WhereCondition';

export default function subQueryTest() {
  describe('subQueryTest', () => {
    beforeAll(() => {
    });
    beforeEach(() => {
    });
    afterEach(() => {
    });
    afterAll(() => {
    });

    it('should set relation name', 0, () => {
      const subQuery = new SubQuery('posts');
      expect(subQuery.getRelationName()).assertEqual('posts');
    });

    it('should start with empty conditions', 0, () => {
      const subQuery = new SubQuery('posts');
      expect(subQuery.getConditions().length).assertEqual(0);
      expect(subQuery.hasConditions()).assertEqual(false);
    });

    it('where should add condition', 0, () => {
      const subQuery = new SubQuery('posts');
      subQuery.where('title', ConditionOperator.EQUAL, 'Test');
      const conditions = subQuery.getConditions();
      expect(conditions.length).assertEqual(1);
      expect(conditions[0].column).assertEqual('title');
      expect(conditions[0].operator).assertEqual(ConditionOperator.EQUAL);
      expect(conditions[0].value).assertEqual('Test');
      expect(conditions[0].logicalOperator).assertEqual(LogicalOperator.AND);
    });

    it('andWhere should add AND condition', 0, () => {
      const subQuery = new SubQuery('posts');
      subQuery.where('title', ConditionOperator.EQUAL, 'Test')
        .andWhere('status', ConditionOperator.EQUAL, 'published');
      const conditions = subQuery.getConditions();
      expect(conditions.length).assertEqual(2);
      expect(conditions[1].logicalOperator).assertEqual(LogicalOperator.AND);
    });

    it('orWhere should add OR condition', 0, () => {
      const subQuery = new SubQuery('posts');
      subQuery.where('title', ConditionOperator.EQUAL, 'Test1')
        .orWhere('title', ConditionOperator.EQUAL, 'Test2');
      const conditions = subQuery.getConditions();
      expect(conditions.length).assertEqual(2);
      expect(conditions[1].logicalOperator).assertEqual(LogicalOperator.OR);
    });

    it('whereIn should add IN condition', 0, () => {
      const subQuery = new SubQuery('posts');
      subQuery.whereIn('category_id', [1, 2, 3]);
      const conditions = subQuery.getConditions();
      expect(conditions.length).assertEqual(1);
      expect(conditions[0].operator).assertEqual(ConditionOperator.IN);
      expect(Array.isArray(conditions[0].value)).assertEqual(true);
    });

    it('whereNull should add IS_NULL condition', 0, () => {
      const subQuery = new SubQuery('posts');
      subQuery.whereNull('deleted_at');
      const conditions = subQuery.getConditions();
      expect(conditions.length).assertEqual(1);
      expect(conditions[0].operator).assertEqual(ConditionOperator.IS_NULL);
    });

    it('whereNotNull should add IS_NOT_NULL condition', 0, () => {
      const subQuery = new SubQuery('posts');
      subQuery.whereNotNull('published_at');
      const conditions = subQuery.getConditions();
      expect(conditions.length).assertEqual(1);
      expect(conditions[0].operator).assertEqual(ConditionOperator.IS_NOT_NULL);
    });

    it('whereBetween should add BETWEEN condition', 0, () => {
      const subQuery = new SubQuery('posts');
      subQuery.whereBetween('views', 100, 1000);
      const conditions = subQuery.getConditions();
      expect(conditions.length).assertEqual(1);
      expect(conditions[0].operator).assertEqual(ConditionOperator.BETWEEN);
      expect(conditions[0].value).assertEqual(100);
      expect(conditions[0].secondValue).assertEqual(1000);
    });

    it('whereLike should add LIKE condition', 0, () => {
      const subQuery = new SubQuery('posts');
      subQuery.whereLike('title', '%tutorial%');
      const conditions = subQuery.getConditions();
      expect(conditions.length).assertEqual(1);
      expect(conditions[0].operator).assertEqual(ConditionOperator.LIKE);
      expect(conditions[0].value).assertEqual('%tutorial%');
    });

    it('hasConditions should return true after adding conditions', 0, () => {
      const subQuery = new SubQuery('posts');
      subQuery.where('title', ConditionOperator.EQUAL, 'Test');
      expect(subQuery.hasConditions()).assertEqual(true);
    });

    it('getDescription should show no conditions for empty subquery', 0, () => {
      const subQuery = new SubQuery('posts');
      const desc = subQuery.getDescription();
      expect(desc).assertEqual('SubQuery(posts): 无条件');
    });

    it('getDescription should format conditions', 0, () => {
      const subQuery = new SubQuery('posts');
      subQuery.where('title', ConditionOperator.EQUAL, 'Test');
      const desc = subQuery.getDescription();
      expect(desc.includes('SubQuery(posts):')).assertEqual(true);
      expect(desc.includes('title')).assertEqual(true);
    });

    it('methods should return SubQuery for chaining', 0, () => {
      const subQuery = new SubQuery('posts');
      const result = subQuery.where('a', ConditionOperator.EQUAL, 1);
      expect(result === subQuery).assertEqual(true);
    });

    it('should handle complex query with multiple conditions', 0, () => {
      const subQuery = new SubQuery('posts');
      subQuery
        .where('status', ConditionOperator.EQUAL, 'published')
        .andWhere('views', ConditionOperator.GREATER, 100)
        .whereBetween('created_at', '2024-01-01', '2024-12-31')
        .whereLike('title', '%important%')
        .whereNotNull('author_id')
        .whereIn('category_id', [1, 2, 3]);
      expect(subQuery.getConditions().length).assertEqual(6);
      expect(subQuery.hasConditions()).assertEqual(true);
    });
  });
}
