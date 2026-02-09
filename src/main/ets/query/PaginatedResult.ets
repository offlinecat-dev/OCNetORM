/**
 * 分页查询结果类
 * 用于封装分页查询的返回结果
 */

import { EntityData } from '../mapping/EntityData'

/**
 * 分页查询结果类
 * 包含当前页数据、总数、页码、每页数量和总页数
 */
export class PaginatedResult {
  /** 当前页数据 */
  data: Array<EntityData> = []
  /** 总记录数 */
  total: number = 0
  /** 当前页码（从 1 开始） */
  page: number = 1
  /** 每页数量 */
  pageSize: number = 20
  /** 总页数 */
  totalPages: number = 0

  /**
   * 构造函数
   * @param data 当前页数据
   * @param total 总记录数
   * @param page 当前页码
   * @param pageSize 每页数量
   */
  constructor(data: Array<EntityData> = [], total: number = 0, page: number = 1, pageSize: number = 20) {
    this.data = data
    this.total = total
    this.page = page
    this.pageSize = pageSize
    this.totalPages = PaginatedResult.calculateTotalPages(total, pageSize)
  }

  /**
   * 计算总页数
   * @param total 总记录数
   * @param pageSize 每页数量
   * @returns 总页数
   */
  static calculateTotalPages(total: number, pageSize: number): number {
    if (pageSize <= 0) {
      return 0
    }
    if (total <= 0) {
      return 0
    }
    return Math.ceil(total / pageSize)
  }

  /**
   * 检查是否有下一页
   * @returns 是否有下一页
   */
  hasNextPage(): boolean {
    return this.page < this.totalPages
  }

  /**
   * 检查是否有上一页
   * @returns 是否有上一页
   */
  hasPreviousPage(): boolean {
    return this.page > 1
  }

  /**
   * 检查当前页是否为第一页
   * @returns 是否为第一页
   */
  isFirstPage(): boolean {
    return this.page === 1
  }

  /**
   * 检查当前页是否为最后一页
   * @returns 是否为最后一页
   */
  isLastPage(): boolean {
    return this.page >= this.totalPages
  }

  /**
   * 获取当前页的数据数量
   * @returns 当前页数据数量
   */
  getCurrentPageSize(): number {
    return this.data.length
  }

  /**
   * 检查结果是否为空
   * @returns 是否为空
   */
  isEmpty(): boolean {
    return this.data.length === 0
  }

  /**
   * 创建成功的分页结果
   * @param data 当前页数据
   * @param total 总记录数
   * @param page 当前页码
   * @param pageSize 每页数量
   * @returns PaginatedResult 实例
   */
  static create(data: Array<EntityData>, total: number, page: number, pageSize: number): PaginatedResult {
    return new PaginatedResult(data, total, page, pageSize)
  }

  /**
   * 创建空的分页结果
   * @param page 当前页码
   * @param pageSize 每页数量
   * @returns 空的 PaginatedResult 实例
   */
  static createEmpty(page: number = 1, pageSize: number = 20): PaginatedResult {
    return new PaginatedResult([], 0, page, pageSize)
  }
}
