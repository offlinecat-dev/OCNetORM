import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { PredicateBuilder, PredicateBuildResult } from '../../main/ets/query/PredicateBuilder';
import { ConditionOperator } from '../../main/ets/types/ConditionOperator';

export default function predicateBuilderTest() {
  describe('predicateBuilderTest', () => {
    beforeAll(() => {
    });
    beforeEach(() => {
    });
    afterEach(() => {
    });
    afterAll(() => {
    });

    it('PredicateBuildResult createSuccess should return success result', 0, () => {
      const result = PredicateBuildResult.createSuccess(null as never, 'test description');
      expect(result.success).assertEqual(true);
      expect(result.description).assertEqual('test description');
      expect(result.errorMessage).assertEqual('');
    });

    it('PredicateBuildResult createFailure should return failure result', 0, () => {
      const result = PredicateBuildResult.createFailure('error message');
      expect(result.success).assertEqual(false);
      expect(result.errorMessage).assertEqual('error message');
      expect(result.predicates === null).assertEqual(true);
    });

    it('PredicateBuildResult default constructor should have default values', 0, () => {
      const result = new PredicateBuildResult();
      expect(result.predicates === null).assertEqual(true);
      expect(result.success).assertEqual(false);
      expect(result.errorMessage).assertEqual('');
      expect(result.description).assertEqual('');
    });

    it('getOperatorDescription EQUAL should return equalTo()', 0, () => {
      expect(PredicateBuilder.getOperatorDescription(ConditionOperator.EQUAL)).assertEqual('equalTo()');
    });

    it('getOperatorDescription NOT_EQUAL should return notEqualTo()', 0, () => {
      expect(PredicateBuilder.getOperatorDescription(ConditionOperator.NOT_EQUAL)).assertEqual('notEqualTo()');
    });

    it('getOperatorDescription GREATER should return greaterThan()', 0, () => {
      expect(PredicateBuilder.getOperatorDescription(ConditionOperator.GREATER)).assertEqual('greaterThan()');
    });

    it('getOperatorDescription LESS should return lessThan()', 0, () => {
      expect(PredicateBuilder.getOperatorDescription(ConditionOperator.LESS)).assertEqual('lessThan()');
    });

    it('getOperatorDescription GREATER_EQUAL should return greaterThanOrEqualTo()', 0, () => {
      expect(PredicateBuilder.getOperatorDescription(ConditionOperator.GREATER_EQUAL)).assertEqual('greaterThanOrEqualTo()');
    });

    it('getOperatorDescription LESS_EQUAL should return lessThanOrEqualTo()', 0, () => {
      expect(PredicateBuilder.getOperatorDescription(ConditionOperator.LESS_EQUAL)).assertEqual('lessThanOrEqualTo()');
    });

    it('getOperatorDescription LIKE should return like()', 0, () => {
      expect(PredicateBuilder.getOperatorDescription(ConditionOperator.LIKE)).assertEqual('like()');
    });

    it('getOperatorDescription IN should return in()', 0, () => {
      expect(PredicateBuilder.getOperatorDescription(ConditionOperator.IN)).assertEqual('in()');
    });

    it('getOperatorDescription NOT_IN should return notIn()', 0, () => {
      expect(PredicateBuilder.getOperatorDescription(ConditionOperator.NOT_IN)).assertEqual('notIn()');
    });

    it('getOperatorDescription BETWEEN should return between()', 0, () => {
      expect(PredicateBuilder.getOperatorDescription(ConditionOperator.BETWEEN)).assertEqual('between()');
    });

    it('getOperatorDescription IS_NULL should return isNull()', 0, () => {
      expect(PredicateBuilder.getOperatorDescription(ConditionOperator.IS_NULL)).assertEqual('isNull()');
    });

    it('getOperatorDescription IS_NOT_NULL should return isNotNull()', 0, () => {
      expect(PredicateBuilder.getOperatorDescription(ConditionOperator.IS_NOT_NULL)).assertEqual('isNotNull()');
    });

    it('getOperatorDescription unknown operator should return 未知操作符', 0, () => {
      const result = PredicateBuilder.getOperatorDescription('UNKNOWN' as ConditionOperator);
      expect(result).assertEqual('未知操作符');
    });
  });
}
