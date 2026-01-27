/**
 * 分页参数类
 * 用于封装分页查询的参数
 */

/**
 * 分页参数类
 * 存储页码和每页数量，提供 offset 计算
 */
export class PaginationParams {
  /** 页码（从 1 开始） */
  page: number = 1
  /** 每页数量 */
  pageSize: number = 20

  /**
   * 构造函数
   * @param page 页码（从 1 开始），默认为 1
   * @param pageSize 每页数量，默认为 20
   */
  constructor(page: number = 1, pageSize: number = 20) {
    // 确保页码至少为 1
    this.page = page >= 1 ? page : 1
    // 确保每页数量至少为 1
    this.pageSize = pageSize >= 1 ? pageSize : 20
  }

  /**
   * 计算 offset 值
   * offset = (page - 1) * pageSize
   * @returns offset 值
   */
  getOffset(): number {
    return (this.page - 1) * this.pageSize
  }

  /**
   * 获取 limit 值（即每页数量）
   * @returns limit 值
   */
  getLimit(): number {
    return this.pageSize
  }

  /**
   * 创建 PaginationParams 实例的便捷方法
   * @param page 页码
   * @param pageSize 每页数量
   * @returns PaginationParams 实例
   */
  static create(page: number, pageSize: number): PaginationParams {
    return new PaginationParams(page, pageSize)
  }

  /**
   * 创建默认分页参数
   * @returns 默认的 PaginationParams 实例（page=1, pageSize=20）
   */
  static createDefault(): PaginationParams {
    return new PaginationParams()
  }
}
