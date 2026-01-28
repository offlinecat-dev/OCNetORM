/**
 * 用户仓库示例
 * 演示如何使用 OCORM Repository 进行数据操作
 */

import {
  Repository,
  QueryExecutor,
  EntityData,
  SaveResult,
  DeleteResult,
  PaginatedResult,
  ConditionOperator,
  TransactionOptions,
  TransactionOptionsConfig,
  TransactionResult
} from 'ocorm'

/**
 * 用户创建参数类
 */
class UserCreateParams {
  username: string = ''
  email: string = ''

  constructor(username: string, email: string) {
    this.username = username
    this.email = email
  }
}

/**
 * TransactionOptionsConfig 实现类
 */
class TxConfig implements TransactionOptionsConfig {
  timeout?: number
  retries?: number
  retryDelay?: number
}

/**
 * 用户仓库类
 * 封装用户实体的数据访问操作
 */
export class UserRepository {
  private repository: Repository

  constructor() {
    this.repository = new Repository('UserEntity')
  }

  /**
   * 创建用户
   * @param username 用户名
   * @param email 邮箱
   * @param age 年龄
   * @returns 保存结果
   */
  async createUser(username: string, email: string, age?: number): Promise<SaveResult> {
    const userData = new EntityData('UserEntity')
    userData.addProperty('username', username, 'string')
    userData.addProperty('email', email, 'string')
    userData.addProperty('age', age ?? 0, 'number')
    userData.addProperty('isActive', true, 'boolean')
    userData.addProperty('createdAt', Date.now(), 'number')
    userData.addProperty('updatedAt', Date.now(), 'number')
    return await this.repository.save(userData)
  }

  /**
   * 根据ID查询用户
   * @param id 用户ID
   * @returns 用户数据或 null
   */
  async findById(id: number): Promise<EntityData | null> {
    return await this.repository.findById(id)
  }

  /**
   * 查询所有用户
   * @returns 用户列表
   */
  async findAll(): Promise<Array<EntityData>> {
    return await this.repository.findAll()
  }

  /**
   * 根据用户名查询
   * @param username 用户名
   * @returns 用户列表
   */
  async findByUsername(username: string): Promise<Array<EntityData>> {
    const queryBuilder = this.repository.createQueryBuilder()
    queryBuilder.where('username', ConditionOperator.EQUAL, username)
    const executor = new QueryExecutor(queryBuilder)
    return await executor.get()
  }

  /**
   * 根据邮箱查询
   * @param email 邮箱
   * @returns 用户数据或 null
   */
  async findByEmail(email: string): Promise<EntityData | null> {
    const queryBuilder = this.repository.createQueryBuilder()
    queryBuilder.where('email', ConditionOperator.EQUAL, email)
    const executor = new QueryExecutor(queryBuilder)
    return await executor.getOne()
  }

  /**
   * 查询激活用户
   * @returns 激活用户列表
   */
  async findActiveUsers(): Promise<Array<EntityData>> {
    const queryBuilder = this.repository.createQueryBuilder()
    queryBuilder.where('isActive', ConditionOperator.EQUAL, true)
    const executor = new QueryExecutor(queryBuilder)
    return await executor.get()
  }

  /**
   * 模糊查询用户名
   * @param keyword 关键字
   * @returns 匹配的用户列表
   */
  async searchByUsername(keyword: string): Promise<Array<EntityData>> {
    const queryBuilder = this.repository.createQueryBuilder()
    queryBuilder.whereLike('username', `%${keyword}%`)
    const executor = new QueryExecutor(queryBuilder)
    return await executor.get()
  }

  /**
   * 分页查询用户
   * @param page 页码（从 1 开始）
   * @param pageSize 每页数量
   * @returns 分页结果
   */
  async findPaginated(page: number, pageSize: number): Promise<PaginatedResult> {
    return await this.repository.findPaginated(page, pageSize)
  }

  /**
   * 查询指定年龄范围的用户
   * @param minAge 最小年龄
   * @param maxAge 最大年龄
   * @returns 用户列表
   */
  async findByAgeRange(minAge: number, maxAge: number): Promise<Array<EntityData>> {
    const queryBuilder = this.repository.createQueryBuilder()
    queryBuilder.whereBetween('age', minAge, maxAge)
    queryBuilder.orderBy('age', 'ASC')
    const executor = new QueryExecutor(queryBuilder)
    return await executor.get()
  }

  /**
   * 更新用户信息
   * @param id 用户ID
   * @param username 新用户名
   * @param email 新邮箱
   * @returns 保存结果
   */
  async updateUser(id: number, username?: string, email?: string): Promise<SaveResult> {
    const existingUser = await this.findById(id)
    if (existingUser === null) {
      return SaveResult.createFailure('用户不存在')
    }

    // 更新属性
    if (username !== undefined) {
      existingUser.setPropertyValue('username', username)
    }
    if (email !== undefined) {
      existingUser.setPropertyValue('email', email)
    }
    existingUser.setPropertyValue('updatedAt', Date.now())

    return await this.repository.save(existingUser)
  }

  /**
   * 删除用户（软删除）
   * @param id 用户ID
   * @returns 删除结果
   */
  async deleteUser(id: number): Promise<DeleteResult> {
    return await this.repository.removeById(id)
  }

  /**
   * 恢复被删除的用户
   * @param id 用户ID
   * @returns 恢复结果
   */
  async restoreUser(id: number): Promise<SaveResult> {
    return await this.repository.restore(id)
  }

  /**
   * 统计用户数量
   * @returns 用户数量
   */
  async count(): Promise<number> {
    return await this.repository.count()
  }

  /**
   * 复杂查询示例：多条件组合
   * @param isActive 是否激活
   * @param minAge 最小年龄
   * @returns 用户列表
   */
  async findByConditions(isActive: boolean, minAge: number): Promise<Array<EntityData>> {
    const queryBuilder = this.repository.createQueryBuilder()
    queryBuilder
      .where('isActive', ConditionOperator.EQUAL, isActive)
      .andWhere('age', ConditionOperator.GREATER_EQUAL, minAge)
      .orderBy('createdAt', 'DESC')
      .limit(10)

    const executor = new QueryExecutor(queryBuilder)
    return await executor.get()
  }

  /**
   * 事务操作示例
   * @param users 用户数据数组
   * @returns 事务结果
   */
  async createUsersInTransaction(users: Array<UserCreateParams>): Promise<TransactionResult> {
    return await this.repository.transaction(async () => {
      for (const user of users) {
        const result = await this.createUser(user.username, user.email)
        if (!result.success) {
          throw new Error(`创建用户 ${user.username} 失败: ${result.errorMessage}`)
        }
      }
    })
  }

  /**
   * 带配置的事务操作示例
   * @returns 事务结果
   */
  async executeWithTransaction(): Promise<TransactionResult> {
    const txConfig = new TxConfig()
    txConfig.timeout = 10000
    txConfig.retries = 2
    txConfig.retryDelay = 100
    const options = TransactionOptions.fromConfig(txConfig)
    return await this.repository.transactionWithOptions(async () => {
      console.info('执行事务操作')
    }, options)
  }
}
