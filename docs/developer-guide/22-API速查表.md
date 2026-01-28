# API 速查表

本文档提供 OCORM 核心 API 的快速参考。

---

## Repository API

### 构造函数

| 方法 | 参数 | 返回值 | 说明 |
|------|------|--------|------|
| `new Repository(entityName)` | `entityName: string` | `Repository` | 创建指定实体的仓库实例 |

### CRUD 操作

| 方法 | 参数 | 返回值 | 说明 |
|------|------|--------|------|
| `save(entityData)` | `entityData: EntityData` | `Promise<SaveResult>` | 保存实体（自动判断插入或更新） |
| `findById(id, includeDeleted?, useCache?)` | `id: ValueType, includeDeleted?: boolean, useCache?: boolean` | `Promise<EntityData \| null>` | 根据主键查询 |
| `findAll(includeDeleted?)` | `includeDeleted?: boolean` | `Promise<Array<EntityData>>` | 查询所有实体 |
| `findAllAsync(includeDeleted?)` | `includeDeleted?: boolean` | `Promise<Array<EntityData>>` | 异步查询所有（TaskPool 优化） |
| `remove(entityData)` | `entityData: EntityData` | `Promise<DeleteResult>` | 删除实体 |
| `removeById(id)` | `id: ValueType` | `Promise<DeleteResult>` | 根据主键删除 |
| `forceRemove(entityData)` | `entityData: EntityData` | `Promise<DeleteResult>` | 强制物理删除 |
| `forceRemoveById(id)` | `id: ValueType` | `Promise<DeleteResult>` | 根据主键强制物理删除 |
| `restore(id)` | `id: ValueType` | `Promise<SaveResult>` | 恢复软删除的实体 |
| `count(includeDeleted?)` | `includeDeleted?: boolean` | `Promise<number>` | 统计实体数量 |

### 批量操作

| 方法 | 参数 | 返回值 | 说明 |
|------|------|--------|------|
| `saveAll(entities)` | `entities: Array<EntityData>` | `Promise<Array<SaveResult>>` | 批量保存 |
| `batchInsert(entities, options?)` | `entities: Array<EntityData>, options?: BatchInsertOptions` | `Promise<BatchInsertResult>` | 高性能批量插入 |

### 分页查询

| 方法 | 参数 | 返回值 | 说明 |
|------|------|--------|------|
| `findPaginated(page, pageSize, includeDeleted?)` | `page: number, pageSize: number, includeDeleted?: boolean` | `Promise<PaginatedResult>` | 分页查询 |

### 多对多关系

| 方法 | 参数 | 返回值 | 说明 |
|------|------|--------|------|
| `attach(sourceId, targetId, relationName)` | `sourceId: number, targetId: number, relationName: string` | `Promise<SaveResult>` | 建立多对多关联 |
| `detach(sourceId, targetId, relationName)` | `sourceId: number, targetId: number, relationName: string` | `Promise<DeleteResult>` | 解除多对多关联 |
| `sync(sourceId, targetIds, relationName)` | `sourceId: ValueType, targetIds: Array<ValueType>, relationName: string` | `Promise<SaveResult>` | 同步多对多关联 |

### 事务

| 方法 | 参数 | 返回值 | 说明 |
|------|------|--------|------|
| `transaction(callback)` | `callback: TransactionCallback` | `Promise<TransactionResult>` | 在事务中执行操作 |
| `transactionWithOptions(callback, options)` | `callback: TransactionCallback, options: TransactionOptions` | `Promise<TransactionResult>` | 带选项的事务执行 |

### 辅助方法

| 方法 | 参数 | 返回值 | 说明 |
|------|------|--------|------|
| `createQueryBuilder()` | 无 | `QueryBuilder` | 创建查询构建器 |
| `getMetadata()` | 无 | `EntityMetadata` | 获取实体元数据 |
| `getDataMapper()` | 无 | `DataMapper` | 获取数据映射器 |

---

## QueryBuilder API

### 构造函数

| 方法 | 参数 | 返回值 | 说明 |
|------|------|--------|------|
| `new QueryBuilder(entityName)` | `entityName: string` | `QueryBuilder` | 创建查询构建器 |

### WHERE 条件

| 方法 | 参数 | 返回值 | 说明 |
|------|------|--------|------|
| `where(column, operator, value)` | `column: string, operator: ConditionOperator, value: ValueType` | `QueryBuilder` | 添加 WHERE 条件 |
| `andWhere(column, operator, value)` | `column: string, operator: ConditionOperator, value: ValueType` | `QueryBuilder` | 添加 AND 条件 |
| `orWhere(column, operator, value)` | `column: string, operator: ConditionOperator, value: ValueType` | `QueryBuilder` | 添加 OR 条件 |
| `whereIn(column, values)` | `column: string, values: Array<ValueType>` | `QueryBuilder` | 添加 IN 条件 |
| `whereNull(column)` | `column: string` | `QueryBuilder` | 添加 IS NULL 条件 |
| `whereNotNull(column)` | `column: string` | `QueryBuilder` | 添加 IS NOT NULL 条件 |
| `whereBetween(column, min, max)` | `column: string, min: ValueType, max: ValueType` | `QueryBuilder` | 添加 BETWEEN 条件 |
| `whereLike(column, pattern)` | `column: string, pattern: string` | `QueryBuilder` | 添加 LIKE 条件 |
| `whereExists(relationName, callback)` | `relationName: string, callback: SubQueryCallback` | `QueryBuilder` | 基于关联存在性过滤 |

### 排序与分页

| 方法 | 参数 | 返回值 | 说明 |
|------|------|--------|------|
| `orderBy(column, direction)` | `column: string, direction: SortDirection` | `QueryBuilder` | 添加排序 |
| `limit(count)` | `count: number` | `QueryBuilder` | 设置 LIMIT |
| `offset(count)` | `count: number` | `QueryBuilder` | 设置 OFFSET |
| `paginate(page, size)` | `page: number, size: number` | `QueryBuilder` | 设置分页参数 |
| `forPage(page, size)` | `page: number, size: number` | `QueryBuilder` | paginate 别名 |

### 选择与关联

| 方法 | 参数 | 返回值 | 说明 |
|------|------|--------|------|
| `select(columns)` | `columns: Array<string>` | `QueryBuilder` | 选择指定列 |
| `with(relationName)` | `relationName: string` | `QueryBuilder` | 预加载关联 |
| `withLazy(relationName)` | `relationName: string` | `QueryBuilder` | 延迟加载关联 |

### 软删除

| 方法 | 参数 | 返回值 | 说明 |
|------|------|--------|------|
| `withDeleted()` | 无 | `QueryBuilder` | 包含已删除数据 |
| `onlyDeleted()` | 无 | `QueryBuilder` | 仅查询已删除数据 |

### 辅助方法

| 方法 | 参数 | 返回值 | 说明 |
|------|------|--------|------|
| `reset()` | 无 | `QueryBuilder` | 重置构建器状态 |
| `getQueryDescription()` | 无 | `string` | 获取查询描述（调试用） |
| `getConditions()` | 无 | `Array<WhereCondition>` | 获取所有条件 |
| `getAllConditions()` | 无 | `Array<WhereCondition>` | 获取所有条件（含软删除） |

---

## QueryExecutor API

### 构造函数

| 方法 | 参数 | 返回值 | 说明 |
|------|------|--------|------|
| `new QueryExecutor(queryBuilder)` | `queryBuilder: QueryBuilder` | `QueryExecutor` | 创建查询执行器 |

### 执行查询

| 方法 | 参数 | 返回值 | 说明 |
|------|------|--------|------|
| `get()` | 无 | `Promise<Array<EntityData>>` | 执行查询获取结果 |
| `getAsync()` | 无 | `Promise<Array<EntityData>>` | 异步执行查询（TaskPool） |
| `getOne()` | 无 | `Promise<EntityData \| null>` | 获取单条结果 |
| `getPaginated()` | 无 | `Promise<PaginatedResult>` | 执行分页查询 |
| `count()` | 无 | `Promise<number>` | 统计数量 |

---

## EntityData API

### 构造函数

| 方法 | 参数 | 返回值 | 说明 |
|------|------|--------|------|
| `new EntityData(entityName)` | `entityName: string` | `EntityData` | 创建实体数据对象 |

### 属性操作

| 方法 | 参数 | 返回值 | 说明 |
|------|------|--------|------|
| `addProperty(name, value, type)` | `name: string, value: ValueType, type: string` | `void` | 添加属性 |
| `getProperty(name)` | `name: string` | `EntityPropertyValue \| null` | 获取属性对象 |
| `getPropertyValue(name)` | `name: string` | `ValueType` | 获取属性值 |
| `setPropertyValue(name, value)` | `name: string, value: ValueType` | `void` | 设置属性值 |
| `hasProperty(name)` | `name: string` | `boolean` | 检查属性是否存在 |
| `getPropertyNames()` | 无 | `Array<string>` | 获取所有属性名 |

### 临时数据

| 方法 | 参数 | 返回值 | 说明 |
|------|------|--------|------|
| `setTransient(key, value)` | `key: string, value: ValueType` | `void` | 设置临时数据 |
| `getTransient(key)` | `key: string` | `ValueType` | 获取临时数据 |
| `getTransientKeys()` | 无 | `Array<string>` | 获取所有临时数据键 |

### 关联数据

| 方法 | 参数 | 返回值 | 说明 |
|------|------|--------|------|
| `setRelatedSingle(name, entity)` | `name: string, entity: EntityData \| null` | `void` | 设置单个关联实体 |
| `setRelatedArray(name, entities)` | `name: string, entities: Array<EntityData>` | `void` | 设置关联实体数组 |
| `getRelatedValue(name)` | `name: string` | `RelatedDataValue \| null` | 获取关联值 |
| `getRelatedPropertyNames()` | 无 | `Array<string>` | 获取所有关联属性名 |

---

## QueryCache API

### 获取实例

| 方法 | 参数 | 返回值 | 说明 |
|------|------|--------|------|
| `QueryCache.getInstance()` | 无 | `QueryCache` | 获取单例实例 |
| `QueryCache.resetInstance()` | 无 | `void` | 重置实例（测试用） |

### 配置

| 方法 | 参数 | 返回值 | 说明 |
|------|------|--------|------|
| `configure(config)` | `config: QueryCacheConfig` | `void` | 配置缓存 |
| `enable()` | 无 | `void` | 启用缓存 |
| `disable()` | 无 | `void` | 禁用缓存 |
| `isEnabled()` | 无 | `boolean` | 检查是否启用 |

### 缓存操作

| 方法 | 参数 | 返回值 | 说明 |
|------|------|--------|------|
| `get(entityName, id)` | `entityName: string, id: ValueType` | `EntityData \| null` | 获取缓存 |
| `set(entityName, id, data)` | `entityName: string, id: ValueType, data: EntityData` | `void` | 设置缓存 |
| `invalidate(entityName, id)` | `entityName: string, id: ValueType` | `void` | 使单条缓存失效 |
| `invalidateEntity(entityName)` | `entityName: string` | `void` | 使实体所有缓存失效 |
| `clear()` | 无 | `void` | 清空所有缓存 |

### 统计

| 方法 | 参数 | 返回值 | 说明 |
|------|------|--------|------|
| `getStatistics()` | 无 | `CacheStatistics` | 获取统计信息 |
| `getSize()` | 无 | `number` | 获取缓存大小 |

---

## Logger API

### 获取实例

| 方法 | 参数 | 返回值 | 说明 |
|------|------|--------|------|
| `Logger.getInstance()` | 无 | `Logger` | 获取单例实例 |
| `Logger.resetInstance()` | 无 | `void` | 重置实例（测试用） |

### 配置

| 方法 | 参数 | 返回值 | 说明 |
|------|------|--------|------|
| `configure(enabled, level)` | `enabled: boolean, level: LogLevel` | `void` | 配置日志 |
| `isEnabled()` | 无 | `boolean` | 检查是否启用 |
| `getLevel()` | 无 | `LogLevel` | 获取日志级别 |

### 日志方法

| 方法 | 参数 | 返回值 | 说明 |
|------|------|--------|------|
| `logQuery(sql, duration)` | `sql: string, duration: number` | `void` | 记录查询日志 |
| `logTransaction(action)` | `action: string` | `void` | 记录事务日志 |
| `logError(errorMessage)` | `errorMessage: string` | `void` | 记录错误日志 |
| `logDebug(debugMessage)` | `debugMessage: string` | `void` | 记录调试日志 |
| `logInfo(infoMessage)` | `infoMessage: string` | `void` | 记录信息日志 |

---
## ViewModelMapper API

### 静态方法

| 方法 | 参数 | 返回值 | 说明 |
|------|------|--------|------|
| `toViewModel<T>(entityData, factory, mapper)` | `entityData: EntityData, factory: ViewModelFactory<T>, mapper: PropertyMapper<T>` | `T` | EntityData → ViewModel |
| `toViewModelWithConfig<T>(entityData, config)` | `entityData: EntityData, config: ViewModelMappingConfig<T>` | `T` | 使用配置转换 |
| `toEntityData<T>(viewModel, entityName, propertyNames, valueGetter)` | `viewModel: T, entityName: string, propertyNames: Array<string>, valueGetter: ReversePropertyMapper<T>` | `EntityData` | ViewModel → EntityData |
| `toEntityDataWithConfig<T>(viewModel, config)` | `viewModel: T, config: ViewModelMappingConfig<T>` | `EntityData` | 使用配置转换（ViewModel → EntityData） |
| `toViewModelArray<T>(entityDataArray, factory, mapper)` | `entityDataArray: Array<EntityData>, factory: ViewModelFactory<T>, mapper: PropertyMapper<T>` | `Array<T>` | 批量转换 |
| `toEntityDataArray<T>(viewModelArray, entityName, propertyNames, valueGetter)` | `viewModelArray: Array<T>, entityName: string, propertyNames: Array<string>, valueGetter: ReversePropertyMapper<T>` | `Array<EntityData>` | 批量转换（ViewModel → EntityData） |
| `toPropertyMap(entityData)` | `entityData: EntityData` | `Map<string, ValueType>` | 转换为 Map |
| `fromPropertyMap(entityName, propertyMap)` | `entityName: string, propertyMap: Map<string, ValueType>` | `EntityData` | 从 Map 创建 |

---
## 实体定义 API

### defineEntity

```typescript
defineEntity(entityName: string, schema: EntitySchema): EntityMetadata
```

### EntitySchema

| 属性 | 类型 | 说明 |
|------|------|------|
| `tableName?` | `string` | 表名 |
| `columns` | `Array<ColumnSchema>` | 列定义数组 |
| `softDelete?` | `boolean \| SoftDeleteSchema` | 软删除配置 |

### SoftDeleteSchema

| 属性 | 类型 | 说明 |
|------|------|------|
| `propertyName?` | `string` | 实体属性名（默认 `deletedAt`） |
| `columnName?` | `string` | 数据库列名（默认 `deleted_at`） |

### ColumnSchema

| 属性 | 类型 | 说明 |
|------|------|------|
| `property` | `string` | 属性名 |
| `name?` | `string` | 列名（可选） |
| `type?` | `ColumnType` | 列类型 |
| `primaryKey?` | `boolean` | 是否主键 |
| `autoIncrement?` | `boolean` | 是否自增 |
| `nullable?` | `boolean` | 是否可空 |
| `unique?` | `boolean` | 是否唯一 |
| `defaultValue?` | `string \| number \| null` | 默认值 |
| `length?` | `number` | 最大长度 |

---
## 装饰器 API

### 实体装饰器

| 装饰器 | 参数 | 说明 |
|--------|------|------|
| `@Table(tableName?)` | `tableName?: string` | 标记类为实体（映射到表） |

### 列装饰器

| 装饰器 | 参数 | 说明 |
|--------|------|------|
| `@PrimaryKey(options?)` | `options?: PrimaryKeyOptions` | 主键列 |
| `@Column(options?)` | `options?: DecoratorColumnOptions` | 普通列 |
| `@CreatedAt(options?)` | `options?: DecoratorColumnOptions` | 创建时间列 |
| `@UpdatedAt(options?)` | `options?: DecoratorColumnOptions` | 更新时间列 |
| `@SoftDelete(options?)` | `options?: DecoratorColumnOptions` | 软删除时间列 |

---
## 初始化 API

```typescript
// 初始化 ORM
await OCORMInit(context: Context, options: OCORMInitOptions): Promise<CreateAllTablesResult | SchemaMigrationExecutionResult | null>

// 关闭连接
await DatabaseManager.getInstance().close(): Promise<void>
```

### OCORMInitOptions

| 属性 | 类型 | 说明 |
|------|------|------|
| `config` | `DatabaseConfig` | 数据库配置 |
| `databaseManager?` | `DatabaseManagerAdapter` | 自定义 DatabaseManager（用于测试） |
| `autoCreateTables?` | `boolean` | 是否自动创建表（默认 true） |
| `autoMigrate?` | `boolean` | 是否启用自动迁移（默认 false） |
| `autoMigrationOptions?` | `AutoMigrationOptions` | 自动迁移选项 |
| `migrationManager?` | `MigrationManager` | 自定义 MigrationManager |
| `enableLogger?` | `boolean` | 是否启用日志（默认使用 `DatabaseConfig.enableLogger`） |
| `logLevel?` | `LogLevel` | 日志级别（默认使用 `DatabaseConfig.loggerLevel`） |
| `schemaBuilder?` | `SchemaBuilder` | 自定义 SchemaBuilder |

### DatabaseConfig

| 属性 | 类型 | 说明 |
|------|------|------|
| `name` | `string` | 数据库文件名 |
| `securityLevel` | `relationalStore.SecurityLevel` | 安全级别（默认 S1） |
| `encrypt` | `boolean` | 是否加密（默认 false） |
| `enableLogger` | `boolean` | 是否启用日志（默认 false） |
| `loggerLevel` | `LogLevel` | 日志级别（默认 INFO） |
| `healthCheckIntervalMs` | `number` | 健康检查间隔（毫秒），0 表示禁用（默认 0） |
| `enableQueryCache` | `boolean` | 是否启用查询缓存（默认 false） |
| `queryCacheMaxSize` | `number` | 查询缓存最大条目数（默认 100） |
| `queryCacheTtlMs` | `number` | 查询缓存 TTL（毫秒，默认 60000） |
