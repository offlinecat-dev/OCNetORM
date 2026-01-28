/**
 * 用户实体示例
 * 演示如何使用 OCORM 定义实体类
 * 符合 ArkTS 严格类型规范
 */

import {
  MetadataStorage,
  ColumnMetadata,
  ColumnType
} from 'ocorm'

/**
 * 用户实体类
 */
export class UserEntity {
  id: number = 0
  username: string = ''
  email: string = ''
  age: number = 0
  isActive: boolean = true
  createdAt: number = 0
  updatedAt: number = 0
  deletedAt: number | null = null
}

/**
 * 注册用户实体
 * 使用 MetadataStorage API 符合 ArkTS 规范
 */
export function registerUserEntity(): void {
  const storage = MetadataStorage.getInstance()

  // 注册实体
  storage.registerEntity('UserEntity', 'users')

  // 注册主键列
  const idColumn = new ColumnMetadata('id', 'id')
  idColumn.setType(ColumnType.INTEGER)
  idColumn.setPrimaryKey(true)
  idColumn.setAutoIncrement(true)
  storage.registerColumn('UserEntity', idColumn)

  // 注册用户名列
  const usernameColumn = new ColumnMetadata('username', 'username')
  usernameColumn.setType(ColumnType.TEXT)
  usernameColumn.setNullable(false)
  storage.registerColumn('UserEntity', usernameColumn)

  // 注册邮箱列
  const emailColumn = new ColumnMetadata('email', 'email')
  emailColumn.setType(ColumnType.TEXT)
  emailColumn.setNullable(false)
  emailColumn.setUnique(true)
  storage.registerColumn('UserEntity', emailColumn)

  // 注册年龄列
  const ageColumn = new ColumnMetadata('age', 'age')
  ageColumn.setType(ColumnType.INTEGER)
  ageColumn.setNullable(true)
  storage.registerColumn('UserEntity', ageColumn)

  // 注册激活状态列
  const isActiveColumn = new ColumnMetadata('isActive', 'is_active')
  isActiveColumn.setType(ColumnType.INTEGER)
  isActiveColumn.setNullable(false)
  isActiveColumn.setDefaultValue(1)
  storage.registerColumn('UserEntity', isActiveColumn)

  // 注册创建时间列
  const createdAtColumn = new ColumnMetadata('createdAt', 'created_at')
  createdAtColumn.setType(ColumnType.INTEGER)
  createdAtColumn.setNullable(false)
  storage.registerColumn('UserEntity', createdAtColumn)

  // 注册更新时间列
  const updatedAtColumn = new ColumnMetadata('updatedAt', 'updated_at')
  updatedAtColumn.setType(ColumnType.INTEGER)
  updatedAtColumn.setNullable(false)
  storage.registerColumn('UserEntity', updatedAtColumn)

  // 注册软删除列
  const deletedAtColumn = new ColumnMetadata('deletedAt', 'deleted_at')
  deletedAtColumn.setType(ColumnType.INTEGER)
  deletedAtColumn.setNullable(true)
  storage.registerColumn('UserEntity', deletedAtColumn)

  // 启用软删除
  const metadata = storage.getEntityMetadata('UserEntity')
  if (metadata !== null) {
    metadata.setSoftDelete(true, 'deleted_at')
  }
}
