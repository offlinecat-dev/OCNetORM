import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { WhereCondition, LogicalOperator } from '../../main/ets/query/WhereCondition';
import { ConditionOperator } from '../../main/ets/types/ConditionOperator';

export default function whereConditionTest() {
  describe('whereConditionTest', () => {
    beforeAll(() => {
    });
    beforeEach(() => {
    });
    afterEach(() => {
    });
    afterAll(() => {
    });

    it('equal should create EQUAL condition', 0, () => {
      const condition = WhereCondition.equal('name', 'Alice');
      expect(condition.column).assertEqual('name');
      expect(condition.operator).assertEqual(ConditionOperator.EQUAL);
      expect(condition.value).assertEqual('Alice');
      expect(condition.logicalOperator).assertEqual(LogicalOperator.AND);
    });

    it('notEqual should create NOT_EQUAL condition', 0, () => {
      const condition = WhereCondition.notEqual('status', 'inactive');
      expect(condition.column).assertEqual('status');
      expect(condition.operator).assertEqual(ConditionOperator.NOT_EQUAL);
      expect(condition.value).assertEqual('inactive');
    });

    it('greaterThan should create GREATER condition', 0, () => {
      const condition = WhereCondition.greaterThan('age', 18);
      expect(condition.column).assertEqual('age');
      expect(condition.operator).assertEqual(ConditionOperator.GREATER);
      expect(condition.value).assertEqual(18);
    });

    it('lessThan should create LESS condition', 0, () => {
      const condition = WhereCondition.lessThan('price', 100);
      expect(condition.column).assertEqual('price');
      expect(condition.operator).assertEqual(ConditionOperator.LESS);
      expect(condition.value).assertEqual(100);
    });

    it('greaterOrEqual should create GREATER_EQUAL condition', 0, () => {
      const condition = WhereCondition.greaterOrEqual('score', 60);
      expect(condition.column).assertEqual('score');
      expect(condition.operator).assertEqual(ConditionOperator.GREATER_EQUAL);
      expect(condition.value).assertEqual(60);
    });

    it('lessOrEqual should create LESS_EQUAL condition', 0, () => {
      const condition = WhereCondition.lessOrEqual('quantity', 10);
      expect(condition.column).assertEqual('quantity');
      expect(condition.operator).assertEqual(ConditionOperator.LESS_EQUAL);
      expect(condition.value).assertEqual(10);
    });

    it('like should create LIKE condition', 0, () => {
      const condition = WhereCondition.like('name', '%test%');
      expect(condition.column).assertEqual('name');
      expect(condition.operator).assertEqual(ConditionOperator.LIKE);
      expect(condition.value).assertEqual('%test%');
    });

    it('inValues should create IN condition with array', 0, () => {
      const values: Array<number> = [1, 2, 3];
      const condition = WhereCondition.inValues('id', values);
      expect(condition.column).assertEqual('id');
      expect(condition.operator).assertEqual(ConditionOperator.IN);
      expect(Array.isArray(condition.value)).assertEqual(true);
      const arr = condition.value as Array<number>;
      expect(arr.length).assertEqual(3);
      expect(arr[0]).assertEqual(1);
    });

    it('notInValues should create NOT_IN condition with array', 0, () => {
      const values: Array<string> = ['a', 'b'];
      const condition = WhereCondition.notInValues('code', values);
      expect(condition.column).assertEqual('code');
      expect(condition.operator).assertEqual(ConditionOperator.NOT_IN);
      expect(Array.isArray(condition.value)).assertEqual(true);
    });

    it('between should create BETWEEN condition with secondValue', 0, () => {
      const condition = WhereCondition.between('age', 18, 65);
      expect(condition.column).assertEqual('age');
      expect(condition.operator).assertEqual(ConditionOperator.BETWEEN);
      expect(condition.value).assertEqual(18);
      expect(condition.secondValue).assertEqual(65);
    });

    it('isNull should create IS_NULL condition', 0, () => {
      const condition = WhereCondition.isNull('deleted_at');
      expect(condition.column).assertEqual('deleted_at');
      expect(condition.operator).assertEqual(ConditionOperator.IS_NULL);
      expect(condition.value === null).assertEqual(true);
    });

    it('isNotNull should create IS_NOT_NULL condition', 0, () => {
      const condition = WhereCondition.isNotNull('email');
      expect(condition.column).assertEqual('email');
      expect(condition.operator).assertEqual(ConditionOperator.IS_NOT_NULL);
      expect(condition.value === null).assertEqual(true);
    });

    it('and() should set logicalOperator to AND', 0, () => {
      const condition = new WhereCondition();
      condition.or();
      expect(condition.logicalOperator).assertEqual(LogicalOperator.OR);
      condition.and();
      expect(condition.logicalOperator).assertEqual(LogicalOperator.AND);
    });

    it('or() should set logicalOperator to OR', 0, () => {
      const condition = new WhereCondition();
      expect(condition.logicalOperator).assertEqual(LogicalOperator.AND);
      condition.or();
      expect(condition.logicalOperator).assertEqual(LogicalOperator.OR);
    });

    it('toString should format simple condition', 0, () => {
      const condition = WhereCondition.equal('name', 'test');
      const str = condition.toString();
      expect(str).assertEqual('name = test');
    });

    it('toString should format array value', 0, () => {
      const condition = WhereCondition.inValues('id', [1, 2, 3]);
      const str = condition.toString();
      expect(str).assertEqual('id IN [1, 2, 3]');
    });

    it('toString should format BETWEEN condition', 0, () => {
      const condition = WhereCondition.between('age', 18, 65);
      const str = condition.toString();
      expect(str).assertEqual('age BETWEEN 18 AND 65');
    });

    it('new WhereCondition should have default values', 0, () => {
      const condition = new WhereCondition();
      expect(condition.column).assertEqual('');
      expect(condition.operator).assertEqual(ConditionOperator.EQUAL);
      expect(condition.value === null).assertEqual(true);
      expect(condition.secondValue === null).assertEqual(true);
      expect(condition.logicalOperator).assertEqual(LogicalOperator.AND);
    });
  });
}
