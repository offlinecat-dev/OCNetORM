/**
 * 实体构造器相关类型定义
 * 由于 ArkTS 不支持接口中的构造签名，使用类来实现
 */

/**
 * 实体信息类
 * 用于存储实体类的元信息
 */
export class EntityInfo {
  /** 实体类名称 */
  name: string = ''
  /** 表名 */
  tableName: string = ''

  constructor(name: string, tableName: string) {
    this.name = name
    this.tableName = tableName
  }
}

/**
 * 实体注册表
 * 用于存储实体类名称与表名的映射关系
 * 由于 ArkTS 限制，不能使用泛型构造器接口
 */
export class EntityRegistry {
  private static entityMap: Map<string, EntityInfo> = new Map()

  /**
   * 注册实体
   * @param entityName 实体类名称
   * @param tableName 表名
   */
  static register(entityName: string, tableName: string): void {
    const info = new EntityInfo(entityName, tableName)
    EntityRegistry.entityMap.set(entityName, info)
  }

  /**
   * 获取实体信息
   * @param entityName 实体类名称
   * @returns 实体信息，如果不存在返回 null
   */
  static getInfo(entityName: string): EntityInfo | null {
    const info = EntityRegistry.entityMap.get(entityName)
    if (info) {
      return info
    }
    return null
  }

  /**
   * 检查实体是否已注册
   * @param entityName 实体类名称
   * @returns 是否已注册
   */
  static hasEntity(entityName: string): boolean {
    return EntityRegistry.entityMap.has(entityName)
  }
}
