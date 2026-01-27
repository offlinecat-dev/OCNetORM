/**
 * 核心模块统一导出
 */

// 列元数据
export { ColumnMetadata } from './ColumnMetadata'

// 实体元数据
export { EntityMetadata } from './EntityMetadata'

// 元数据存储
export { MetadataStorage } from './MetadataStorage'

// 关系元数据
export { RelationMetadata, CascadeOptions, CascadeSetting } from './RelationMetadata'

// 多对多关系元数据
export { ManyToManyMetadata } from './ManyToManyMetadata'

// 钩子处理器
export { HooksProcessor } from './HooksProcessor'

// ORM 上下文（依赖注入）
export { OrmContext, OrmContextConfig } from './OrmContext'

// 统一初始化入口
export { OCORMInit, OCORMInitOptions } from './OrmInit'

// 快速实体注册工具
export { defineEntity, EntitySchema, ColumnSchema, SoftDeleteSchema } from './EntitySchema'

// 验证模块
export { ValidationMetadataStorage, ValidationRuleType, ValidationRule, EntityValidator, ValidationResult } from '../validation/index'
