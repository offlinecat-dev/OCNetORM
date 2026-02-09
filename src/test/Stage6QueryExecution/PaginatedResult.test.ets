import { describe, it, expect } from '@ohos/hypium';
import { PaginatedResult } from '../../main/ets/query/PaginatedResult';
import { EntityData } from '../../main/ets/mapping/EntityData';

export default function paginatedResultTest() {
  describe('paginatedResultTest', () => {
    it('should create PaginatedResult with default values', 0, () => {
      const result = new PaginatedResult();
      expect(result.data.length).assertEqual(0);
      expect(result.total).assertEqual(0);
      expect(result.page).assertEqual(1);
      expect(result.pageSize).assertEqual(20);
      expect(result.totalPages).assertEqual(0);
    });

    it('should create PaginatedResult with custom values', 0, () => {
      const data: Array<EntityData> = [new EntityData('User'), new EntityData('User')];
      const result = new PaginatedResult(data, 50, 2, 10);

      expect(result.data.length).assertEqual(2);
      expect(result.total).assertEqual(50);
      expect(result.page).assertEqual(2);
      expect(result.pageSize).assertEqual(10);
      expect(result.totalPages).assertEqual(5);
    });

    it('calculateTotalPages should return correct value', 0, () => {
      expect(PaginatedResult.calculateTotalPages(100, 10)).assertEqual(10);
      expect(PaginatedResult.calculateTotalPages(101, 10)).assertEqual(11);
      expect(PaginatedResult.calculateTotalPages(99, 10)).assertEqual(10);
      expect(PaginatedResult.calculateTotalPages(10, 10)).assertEqual(1);
      expect(PaginatedResult.calculateTotalPages(1, 10)).assertEqual(1);
    });

    it('calculateTotalPages should return 0 for zero or negative pageSize', 0, () => {
      expect(PaginatedResult.calculateTotalPages(100, 0)).assertEqual(0);
      expect(PaginatedResult.calculateTotalPages(100, -5)).assertEqual(0);
    });

    it('calculateTotalPages should return 0 for zero or negative total', 0, () => {
      expect(PaginatedResult.calculateTotalPages(0, 10)).assertEqual(0);
      expect(PaginatedResult.calculateTotalPages(-5, 10)).assertEqual(0);
    });

    it('hasNextPage should return correct value', 0, () => {
      const result1 = new PaginatedResult([], 50, 1, 10);
      expect(result1.hasNextPage()).assertEqual(true);

      const result2 = new PaginatedResult([], 50, 5, 10);
      expect(result2.hasNextPage()).assertEqual(false);

      const result3 = new PaginatedResult([], 50, 3, 10);
      expect(result3.hasNextPage()).assertEqual(true);
    });

    it('hasPreviousPage should return correct value', 0, () => {
      const result1 = new PaginatedResult([], 50, 1, 10);
      expect(result1.hasPreviousPage()).assertEqual(false);

      const result2 = new PaginatedResult([], 50, 2, 10);
      expect(result2.hasPreviousPage()).assertEqual(true);

      const result3 = new PaginatedResult([], 50, 5, 10);
      expect(result3.hasPreviousPage()).assertEqual(true);
    });

    it('isFirstPage should return correct value', 0, () => {
      const result1 = new PaginatedResult([], 50, 1, 10);
      expect(result1.isFirstPage()).assertEqual(true);

      const result2 = new PaginatedResult([], 50, 2, 10);
      expect(result2.isFirstPage()).assertEqual(false);
    });

    it('isLastPage should return correct value', 0, () => {
      const result1 = new PaginatedResult([], 50, 5, 10);
      expect(result1.isLastPage()).assertEqual(true);

      const result2 = new PaginatedResult([], 50, 4, 10);
      expect(result2.isLastPage()).assertEqual(false);

      const result3 = new PaginatedResult([], 50, 6, 10);
      expect(result3.isLastPage()).assertEqual(true);
    });

    it('getCurrentPageSize should return data length', 0, () => {
      const data: Array<EntityData> = [
        new EntityData('User'),
        new EntityData('User'),
        new EntityData('User')
      ];
      const result = new PaginatedResult(data, 50, 1, 10);
      expect(result.getCurrentPageSize()).assertEqual(3);
    });

    it('isEmpty should return correct value', 0, () => {
      const result1 = new PaginatedResult([], 0, 1, 10);
      expect(result1.isEmpty()).assertEqual(true);

      const data: Array<EntityData> = [new EntityData('User')];
      const result2 = new PaginatedResult(data, 1, 1, 10);
      expect(result2.isEmpty()).assertEqual(false);
    });

    it('create should return PaginatedResult instance', 0, () => {
      const data: Array<EntityData> = [new EntityData('User')];
      const result = PaginatedResult.create(data, 100, 3, 20);

      expect(result.data.length).assertEqual(1);
      expect(result.total).assertEqual(100);
      expect(result.page).assertEqual(3);
      expect(result.pageSize).assertEqual(20);
      expect(result.totalPages).assertEqual(5);
    });

    it('createEmpty should return empty PaginatedResult', 0, () => {
      const result1 = PaginatedResult.createEmpty();
      expect(result1.data.length).assertEqual(0);
      expect(result1.total).assertEqual(0);
      expect(result1.page).assertEqual(1);
      expect(result1.pageSize).assertEqual(20);
      expect(result1.totalPages).assertEqual(0);

      const result2 = PaginatedResult.createEmpty(5, 15);
      expect(result2.page).assertEqual(5);
      expect(result2.pageSize).assertEqual(15);
    });

    it('should handle edge case: page exceeds totalPages', 0, () => {
      const result = new PaginatedResult([], 10, 10, 5);
      expect(result.totalPages).assertEqual(2);
      expect(result.page).assertEqual(10);
      expect(result.isLastPage()).assertEqual(true);
      expect(result.hasNextPage()).assertEqual(false);
    });

    it('should handle single page scenario', 0, () => {
      const data: Array<EntityData> = [new EntityData('User')];
      const result = new PaginatedResult(data, 1, 1, 10);

      expect(result.totalPages).assertEqual(1);
      expect(result.isFirstPage()).assertEqual(true);
      expect(result.isLastPage()).assertEqual(true);
      expect(result.hasNextPage()).assertEqual(false);
      expect(result.hasPreviousPage()).assertEqual(false);
    });

    it('should handle exact page boundary', 0, () => {
      const result = new PaginatedResult([], 20, 2, 10);
      expect(result.totalPages).assertEqual(2);
      expect(result.isLastPage()).assertEqual(true);
    });
  });
}
