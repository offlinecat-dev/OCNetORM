import { describe, it, expect } from '@ohos/hypium';
import { RelationLoadResult, ParallelRelationLoadResult } from '../../main/ets/query/RelationLoadResult';

export default function relationLoadResultTest() {
  describe('relationLoadResultTest', () => {
    it('should create RelationLoadResult with default values', 0, () => {
      const result = new RelationLoadResult();
      expect(result.relationName).assertEqual('');
      expect(result.success).assertEqual(false);
      expect(result.errorMessage).assertEqual('');
      expect(result.loadedCount).assertEqual(0);
      expect(result.duration).assertEqual(0);
    });

    it('should create RelationLoadResult with relation name', 0, () => {
      const result = new RelationLoadResult('posts');
      expect(result.relationName).assertEqual('posts');
      expect(result.success).assertEqual(false);
    });

    it('createSuccess should create successful result', 0, () => {
      const result = RelationLoadResult.createSuccess('posts', 10, 50);
      expect(result.relationName).assertEqual('posts');
      expect(result.success).assertEqual(true);
      expect(result.loadedCount).assertEqual(10);
      expect(result.duration).assertEqual(50);
      expect(result.errorMessage).assertEqual('');
    });

    it('createSuccess should use default values', 0, () => {
      const result = RelationLoadResult.createSuccess('posts');
      expect(result.loadedCount).assertEqual(0);
      expect(result.duration).assertEqual(0);
    });

    it('createFailure should create failed result', 0, () => {
      const result = RelationLoadResult.createFailure('posts', 'Connection failed', 100);
      expect(result.relationName).assertEqual('posts');
      expect(result.success).assertEqual(false);
      expect(result.errorMessage).assertEqual('Connection failed');
      expect(result.duration).assertEqual(100);
    });

    it('createFailure should use default duration', 0, () => {
      const result = RelationLoadResult.createFailure('posts', 'Error');
      expect(result.duration).assertEqual(0);
    });

    it('isSuccess should return correct value', 0, () => {
      const success = RelationLoadResult.createSuccess('posts');
      const failure = RelationLoadResult.createFailure('posts', 'Error');

      expect(success.isSuccess()).assertEqual(true);
      expect(failure.isSuccess()).assertEqual(false);
    });

    it('isFailed should return correct value', 0, () => {
      const success = RelationLoadResult.createSuccess('posts');
      const failure = RelationLoadResult.createFailure('posts', 'Error');

      expect(success.isFailed()).assertEqual(false);
      expect(failure.isFailed()).assertEqual(true);
    });

    it('getFormattedError should return empty for success', 0, () => {
      const result = RelationLoadResult.createSuccess('posts');
      expect(result.getFormattedError()).assertEqual('');
    });

    it('getFormattedError should return formatted message for failure', 0, () => {
      const result = RelationLoadResult.createFailure('posts', 'Connection timeout');
      const formatted = result.getFormattedError();
      expect(formatted.includes('posts')).assertEqual(true);
      expect(formatted.includes('Connection timeout')).assertEqual(true);
    });
  });

  describe('parallelRelationLoadResultTest', () => {
    it('should create ParallelRelationLoadResult with default values', 0, () => {
      const result = new ParallelRelationLoadResult();
      expect(result.results.length).assertEqual(0);
      expect(result.totalDuration).assertEqual(0);
    });

    it('addResult should add result to array', 0, () => {
      const parallel = new ParallelRelationLoadResult();
      const result1 = RelationLoadResult.createSuccess('posts');
      const result2 = RelationLoadResult.createSuccess('comments');

      parallel.addResult(result1);
      parallel.addResult(result2);

      expect(parallel.results.length).assertEqual(2);
    });

    it('isAllSuccess should return true when all succeed', 0, () => {
      const parallel = new ParallelRelationLoadResult();
      parallel.addResult(RelationLoadResult.createSuccess('posts'));
      parallel.addResult(RelationLoadResult.createSuccess('comments'));

      expect(parallel.isAllSuccess()).assertEqual(true);
    });

    it('isAllSuccess should return false when any fails', 0, () => {
      const parallel = new ParallelRelationLoadResult();
      parallel.addResult(RelationLoadResult.createSuccess('posts'));
      parallel.addResult(RelationLoadResult.createFailure('comments', 'Error'));

      expect(parallel.isAllSuccess()).assertEqual(false);
    });

    it('isAllSuccess should return true for empty results', 0, () => {
      const parallel = new ParallelRelationLoadResult();
      expect(parallel.isAllSuccess()).assertEqual(true);
    });

    it('hasAnyFailure should return false when all succeed', 0, () => {
      const parallel = new ParallelRelationLoadResult();
      parallel.addResult(RelationLoadResult.createSuccess('posts'));
      parallel.addResult(RelationLoadResult.createSuccess('comments'));

      expect(parallel.hasAnyFailure()).assertEqual(false);
    });

    it('hasAnyFailure should return true when any fails', 0, () => {
      const parallel = new ParallelRelationLoadResult();
      parallel.addResult(RelationLoadResult.createSuccess('posts'));
      parallel.addResult(RelationLoadResult.createFailure('comments', 'Error'));

      expect(parallel.hasAnyFailure()).assertEqual(true);
    });

    it('hasAnyFailure should return false for empty results', 0, () => {
      const parallel = new ParallelRelationLoadResult();
      expect(parallel.hasAnyFailure()).assertEqual(false);
    });

    it('getSuccessCount should return correct count', 0, () => {
      const parallel = new ParallelRelationLoadResult();
      parallel.addResult(RelationLoadResult.createSuccess('posts'));
      parallel.addResult(RelationLoadResult.createFailure('comments', 'Error'));
      parallel.addResult(RelationLoadResult.createSuccess('tags'));

      expect(parallel.getSuccessCount()).assertEqual(2);
    });

    it('getFailureCount should return correct count', 0, () => {
      const parallel = new ParallelRelationLoadResult();
      parallel.addResult(RelationLoadResult.createSuccess('posts'));
      parallel.addResult(RelationLoadResult.createFailure('comments', 'Error'));
      parallel.addResult(RelationLoadResult.createFailure('tags', 'Timeout'));

      expect(parallel.getFailureCount()).assertEqual(2);
    });

    it('getFailedRelationNames should return failed names', 0, () => {
      const parallel = new ParallelRelationLoadResult();
      parallel.addResult(RelationLoadResult.createSuccess('posts'));
      parallel.addResult(RelationLoadResult.createFailure('comments', 'Error'));
      parallel.addResult(RelationLoadResult.createFailure('tags', 'Timeout'));

      const names = parallel.getFailedRelationNames();
      expect(names.length).assertEqual(2);
      expect(names[0]).assertEqual('comments');
      expect(names[1]).assertEqual('tags');
    });

    it('getFailedRelationNames should return empty array when all succeed', 0, () => {
      const parallel = new ParallelRelationLoadResult();
      parallel.addResult(RelationLoadResult.createSuccess('posts'));

      const names = parallel.getFailedRelationNames();
      expect(names.length).assertEqual(0);
    });

    it('getErrorMessages should return error messages', 0, () => {
      const parallel = new ParallelRelationLoadResult();
      parallel.addResult(RelationLoadResult.createSuccess('posts'));
      parallel.addResult(RelationLoadResult.createFailure('comments', 'Connection failed'));

      const messages = parallel.getErrorMessages();
      expect(messages.length).assertEqual(1);
      expect(messages[0].includes('comments')).assertEqual(true);
      expect(messages[0].includes('Connection failed')).assertEqual(true);
    });

    it('getErrorMessages should skip empty error messages', 0, () => {
      const parallel = new ParallelRelationLoadResult();
      const failResult = new RelationLoadResult('posts');
      failResult.success = false;
      failResult.errorMessage = '';
      parallel.addResult(failResult);

      const messages = parallel.getErrorMessages();
      expect(messages.length).assertEqual(0);
    });

    it('getTotalLoadedCount should sum all loaded counts', 0, () => {
      const parallel = new ParallelRelationLoadResult();
      parallel.addResult(RelationLoadResult.createSuccess('posts', 10));
      parallel.addResult(RelationLoadResult.createSuccess('comments', 25));
      parallel.addResult(RelationLoadResult.createFailure('tags', 'Error'));

      expect(parallel.getTotalLoadedCount()).assertEqual(35);
    });

    it('create should return ParallelRelationLoadResult instance', 0, () => {
      const results: Array<RelationLoadResult> = [
        RelationLoadResult.createSuccess('posts', 5),
        RelationLoadResult.createSuccess('comments', 10)
      ];

      const parallel = ParallelRelationLoadResult.create(results, 150);
      expect(parallel.results.length).assertEqual(2);
      expect(parallel.totalDuration).assertEqual(150);
      expect(parallel.getTotalLoadedCount()).assertEqual(15);
    });

    it('should handle all failures scenario', 0, () => {
      const parallel = new ParallelRelationLoadResult();
      parallel.addResult(RelationLoadResult.createFailure('posts', 'Error 1'));
      parallel.addResult(RelationLoadResult.createFailure('comments', 'Error 2'));

      expect(parallel.isAllSuccess()).assertEqual(false);
      expect(parallel.hasAnyFailure()).assertEqual(true);
      expect(parallel.getSuccessCount()).assertEqual(0);
      expect(parallel.getFailureCount()).assertEqual(2);
    });
  });
}
