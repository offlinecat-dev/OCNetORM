/**
 * 查询作用域注册表
 * 管理实体的预定义查询作用域
 */

import { QueryBuilder } from '../query/QueryBuilder'

/**
 * 作用域函数类型
 * 接收 QueryBuilder 并返回修改后的 QueryBuilder
 */
export type ScopeFunction = (qb: QueryBuilder) => QueryBuilder

/**
 * 作用域定义映射
 * 键为作用域名称，值为作用域函数
 */
export type ScopeDefinitions = Map<string, ScopeFunction>

/**
 * 查询作用域注册表
 * 单例模式，管理所有实体的查询作用域
 */
export class ScopeRegistry {
  /** 单例实例 */
  private static instance: ScopeRegistry | null = null

  /** 实体作用域存储：entityName -> scopeName -> ScopeFunction */
  private scopes: Map<string, ScopeDefinitions> = new Map()

  /**
   * 私有构造函数（单例模式）
   */
  private constructor() {}

  /**
   * 获取单例实例
   * @returns ScopeRegistry 实例
   */
  static getInstance(): ScopeRegistry {
    if (ScopeRegistry.instance === null) {
      ScopeRegistry.instance = new ScopeRegistry()
    }
    return ScopeRegistry.instance
  }

  /**
   * 重置单例（仅用于测试）
   */
  static resetInstance(): void {
    ScopeRegistry.instance = null
  }

  /**
   * 注册实体的作用域
   * @param entityName 实体名称
   * @param scopeName 作用域名称
   * @param scopeFunction 作用域函数
   */
  registerScope(entityName: string, scopeName: string, scopeFunction: ScopeFunction): void {
    let entityScopes = this.scopes.get(entityName)
    if (entityScopes === undefined) {
      entityScopes = new Map<string, ScopeFunction>()
      this.scopes.set(entityName, entityScopes)
    }
    entityScopes.set(scopeName, scopeFunction)
  }

  /**
   * 批量注册实体的作用域
   * @param entityName 实体名称
   * @param scopes 作用域定义对象
   */
  registerScopes(entityName: string, scopes: Record<string, ScopeFunction>): void {
    const keys = Object.keys(scopes)
    for (let i = 0; i < keys.length; i++) {
      const scopeName = keys[i]
      this.registerScope(entityName, scopeName, scopes[scopeName])
    }
  }

  /**
   * 获取实体的作用域函数
   * @param entityName 实体名称
   * @param scopeName 作用域名称
   * @returns 作用域函数，不存在返回 null
   */
  getScope(entityName: string, scopeName: string): ScopeFunction | null {
    const entityScopes = this.scopes.get(entityName)
    if (entityScopes === undefined) {
      return null
    }
    const scopeFunction = entityScopes.get(scopeName)
    return scopeFunction !== undefined ? scopeFunction : null
  }

  /**
   * 检查实体是否有指定作用域
   * @param entityName 实体名称
   * @param scopeName 作用域名称
   * @returns 是否存在
   */
  hasScope(entityName: string, scopeName: string): boolean {
    return this.getScope(entityName, scopeName) !== null
  }

  /**
   * 获取实体的所有作用域名称
   * @param entityName 实体名称
   * @returns 作用域名称数组
   */
  getScopeNames(entityName: string): Array<string> {
    const entityScopes = this.scopes.get(entityName)
    if (entityScopes === undefined) {
      return []
    }
    const names: Array<string> = []
    entityScopes.forEach((_, name) => {
      names.push(name)
    })
    return names
  }

  /**
   * 移除实体的作用域
   * @param entityName 实体名称
   * @param scopeName 作用域名称
   * @returns 是否成功移除
   */
  removeScope(entityName: string, scopeName: string): boolean {
    const entityScopes = this.scopes.get(entityName)
    if (entityScopes === undefined) {
      return false
    }
    return entityScopes.delete(scopeName)
  }

  /**
   * 移除实体的所有作用域
   * @param entityName 实体名称
   */
  removeAllScopes(entityName: string): void {
    this.scopes.delete(entityName)
  }

  /**
   * 清空所有作用域
   */
  clear(): void {
    this.scopes.clear()
  }

  /**
   * 应用作用域到查询构建器
   * @param entityName 实体名称
   * @param scopeName 作用域名称
   * @param queryBuilder 查询构建器
   * @returns 修改后的查询构建器，作用域不存在返回原查询构建器
   */
  applyScope(entityName: string, scopeName: string, queryBuilder: QueryBuilder): QueryBuilder {
    const scopeFunction = this.getScope(entityName, scopeName)
    if (scopeFunction === null) {
      return queryBuilder
    }
    return scopeFunction(queryBuilder)
  }
}

/**
 * 注册单个实体作用域（便捷 API）
 * @param entityName 实体名称
 * @param scopeName 作用域名称
 * @param scopeFunction 作用域函数
 */
export function registerEntityScope(
  entityName: string,
  scopeName: string,
  scopeFunction: ScopeFunction
): void {
  ScopeRegistry.getInstance().registerScope(entityName, scopeName, scopeFunction)
}

/**
 * 批量注册实体作用域（便捷 API）
 * @param entityName 实体名称
 * @param scopes 作用域映射
 */
export function registerEntityScopes(entityName: string, scopes: Record<string, ScopeFunction>): void {
  ScopeRegistry.getInstance().registerScopes(entityName, scopes)
}

/**
 * 注册单个实体作用域（别名 API）
 * @param entityName 实体名称
 * @param scopeName 作用域名称
 * @param scopeFunction 作用域函数
 */
export function registerScope(entityName: string, scopeName: string, scopeFunction: ScopeFunction): void {
  registerEntityScope(entityName, scopeName, scopeFunction)
}

/**
 * 批量注册实体作用域（别名 API）
 * @param entityName 实体名称
 * @param scopes 作用域映射
 */
export function registerScopes(entityName: string, scopes: Record<string, ScopeFunction>): void {
  registerEntityScopes(entityName, scopes)
}
