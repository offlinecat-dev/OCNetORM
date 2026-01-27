/**
 * 实体装饰器
 * 用于标注实体类，将类映射到数据库表
 */

import { MetadataStorage } from '../core/MetadataStorage'

/**
 * 实体装饰器配置选项
 */
export class EntityOptions {
  /** 数据库表名，可选，默认使用类名 */
  tableName: string = ''

  constructor(tableName?: string) {
    this.tableName = tableName ? tableName : ''
  }
}

/**
 * 实体装饰器工厂函数
 * 由于 ArkTS 装饰器限制，需要手动调用注册
 * @param entityName 实体类名
 * @param options 装饰器配置选项
 */
export function registerEntity(entityName: string, options?: EntityOptions): void {
  const storage = MetadataStorage.getInstance()
  const tableName = options && options.tableName ? options.tableName : entityName
  
  // 如果实体已注册，跳过（避免重复注册错误）
  if (!storage.hasEntity(entityName)) {
    try {
      storage.registerEntity(entityName, tableName)
    } catch (e) {
      // 忽略重复注册错误（并发情况下可能发生）
    }
  } else if (tableName !== entityName) {
    const metadata = storage.getEntityMetadata(entityName)
    if (metadata !== null && metadata.tableName === entityName) {
      metadata.tableName = tableName
    }
  }
}

/**
 * 创建实体配置选项
 * @param tableName 表名
 * @returns EntityOptions 实例
 */
export function createEntityOptions(tableName?: string): EntityOptions {
  return new EntityOptions(tableName)
}

/**
 * 类装饰器：表映射
 * @param tableName 表名（可选）
 */
export function Table(tableName?: string): ClassDecorator {
  return (target: Function) => {
    registerEntity(target.name, tableName ? createEntityOptions(tableName) : undefined)
  }
}
