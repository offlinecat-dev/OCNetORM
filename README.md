# OCORM

**轻量级 HarmonyOS SQLite ORM 框架**

[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/Version-2.4.14-green.svg)](https://github.com/offlinecat-dev/OCNetORM/releases)
[![HarmonyOS](https://img.shields.io/badge/HarmonyOS-Next-orange.svg)](https://developer.harmonyos.com)
[![OpenHarmony](https://img.shields.io/badge/OpenHarmony-5.0+-purple.svg)](https://www.openharmony.cn)

基于 `@ohos.data.relationalStore` 构建，提供类型安全的数据库操作 API。

[![GitHub Repo](https://img.shields.io/badge/GitHub-Repository-black?style=for-the-badge&logo=github)](https://github.com/offlinecat-dev/OCNetORM)
[![Report Bug](https://img.shields.io/badge/Issues-Report_Bug-red?style=for-the-badge&logo=github)](https://github.com/offlinecat-dev/OCNetORM/issues)

## 特性

- 🚀 轻量高效，无额外依赖
- 🔒 类型安全，严格遵循 ArkTS 类型系统
- 🔗 链式查询，流畅的 QueryBuilder API
- 📦 Repository 模式，简洁的 CRUD 接口
- 🔄 完整的事务支持
- 🛠️ 自动建表与数据库迁移
- ⚡ 自动类型转换
- 🔗 关联查询 (OneToMany/ManyToOne/ManyToMany)
- 📥 预加载/延迟加载策略
- 🪝 生命周期钩子
- ✅ 数据验证 (required/length/email)
- 🗑️ 软删除支持
- 📄 分页查询
- ⚙️ 批量插入
- 💾 查询缓存 (TTL/LRU)
- ⏱️ 高级事务（超时/重试/隔离级别）
- 🔀 ViewModel 双向映射
- 🎯 响应式数据绑定 (@ObservedV2)

## 性能基准

> 测试设备：HarmonyOS 真机 | 测试日期：2026-01-27

| 操作类型 | 数据量 | 耗时 | 平均速度 |
|---------|--------|------|----------|
| 非事务插入 | 100 条 | 82ms | 0.82ms/条 |
| 非事务插入 | 1000 条 | 660ms | 0.66ms/条 |
| **事务插入** | 1000 条 | 356ms | **0.36ms/条** |
| **事务插入** | 10000 条 | 4577ms | **0.46ms/条** |
| 查询 | 200 条 | 38ms | - |
| 条件查询 | 22 条 | 5ms | - |

💡 **建议**：批量操作请使用事务包裹，性能可提升 **2-5 倍**。

> ⚠️ 实际性能因设备而异，但差异通常不大。模拟器性能约为真机的 1/3 ~ 1/5。

## 安装

[![ohpm](https://img.shields.io/badge/ohpm-v2.4.14-blue?style=for-the-badge)](https://ohpm.openharmony.cn/)

在 HarmonyOS 项目的 `oh-package.json5` 中添加依赖：

```json5
{
  "dependencies": {
    "@offlinecat/ocorm": "2.4.14"
  }
}
```

或使用命令行安装：

```bash
ohpm install @offlinecat/ocorm
```

## 快速开始

### 1. 定义实体

推荐使用 `defineEntity` 简洁方式：

```typescript
import { defineEntity, ColumnType } from '@offlinecat/ocorm'

defineEntity('User', {
  tableName: 'users',
  columns: [
    { property: 'id', primaryKey: true },
    { property: 'name', type: ColumnType.TEXT, nullable: false },
    { property: 'email', type: ColumnType.TEXT, unique: true },
    { property: 'age', type: ColumnType.INTEGER },
    { property: 'createdAt', name: 'created_at', type: ColumnType.INTEGER },
    { property: 'deletedAt', name: 'deleted_at', type: ColumnType.INTEGER }
  ],
  softDelete: true  // 启用软删除
})
```

### 2. 初始化数据库

```typescript
import { OCORMInit, DatabaseConfig } from '@offlinecat/ocorm'

const config = new DatabaseConfig('app.db')
await OCORMInit(context, { config })
```

### 3. CRUD 操作

```typescript
import { Repository, EntityData } from '@offlinecat/ocorm'

const repo = new Repository('User')

// 创建
const user = new EntityData('User')
user.addProperty('name', '张三', 'string')
user.addProperty('email', 'zhangsan@example.com', 'string')
user.addProperty('age', 25, 'number')
await repo.save(user)

// 查询
const allUsers = await repo.findAll()
const oneUser = await repo.findById(1)

// 更新
oneUser?.setPropertyValue('name', '李四')
await repo.save(oneUser!)

// 删除（软删除/物理删除自动判断）
await repo.removeById(1)

// 恢复软删除
await repo.restore(1)
```

### 4. 链式查询

```typescript
import { QueryExecutor, ConditionOperator } from '@offlinecat/ocorm'

const qb = repo.createQueryBuilder()
  .where('age', ConditionOperator.GREATER, 18)
  .andWhere('isActive', ConditionOperator.EQUAL, 1)
  .orderBy('name', 'ASC')
  .limit(10)

const executor = new QueryExecutor(qb)
const users = await executor.get()
```

### 5. 分页查询

```typescript
// 简单分页
const result = await repo.findPaginated(1, 20)
console.log(`第 ${result.page} 页，共 ${result.totalPages} 页，总计 ${result.total} 条`)

// QueryBuilder 分页
const qb = repo.createQueryBuilder()
  .where('isActive', ConditionOperator.EQUAL, 1)
  .paginate(1, 20)
const paginatedResult = await new QueryExecutor(qb).getPaginated()
```

### 6. 事务处理

```typescript
import { TransactionOptions, IsolationLevel } from '@offlinecat/ocorm'

// 基础事务
await repo.transaction(async (txRepo) => {
  await txRepo.save(user1)
  await txRepo.save(user2)
  // 抛出异常会自动回滚
})

// 高级事务（超时、重试、隔离级别）
const options = TransactionOptions.fromConfig({
  timeout: 10000,
  retries: 3,
  isolation: IsolationLevel.SERIALIZABLE
})
await repo.transactionWithOptions(async (txRepo) => {
  // 关键业务操作
}, options)
```

### 7. 批量插入

```typescript
import { BatchInsertOptions } from '@offlinecat/ocorm'

const users: Array<EntityData> = []
for (let i = 0; i < 1000; i++) {
  const user = new EntityData('User')
  user.addProperty('name', `用户${i}`, 'string')
  users.push(user)
}

// 默认（使用事务，执行钩子和验证）
await repo.batchInsert(users)

// 快速模式（跳过钩子和验证，适合大量数据导入）
await repo.batchInsert(users, BatchInsertOptions.createFast())
```

### 8. 关联查询

```typescript
import { MetadataStorage, RelationMetadata, RelationType } from '@offlinecat/ocorm'

// 注册一对多关系
const storage = MetadataStorage.getInstance()
storage.registerRelation('User', new RelationMetadata(
  RelationType.ONE_TO_MANY, 'User', 'Post', 'posts', 'user_id'
))

// 预加载关联
const qb = repo.createQueryBuilder().with('posts')
const usersWithPosts = await new QueryExecutor(qb).get()

// 访问关联数据
const posts = usersWithPosts[0]?.getRelatedArray('posts')
```

### 9. 数据验证

```typescript
import { ValidationMetadataStorage } from '@offlinecat/ocorm'

const storage = ValidationMetadataStorage.getInstance()
storage.registerRule('User', 'name', { type: 'required' })
storage.registerRule('User', 'name', { type: 'length', min: 2, max: 50 })
storage.registerRule('User', 'email', { type: 'email' })

// save 时自动验证，失败抛出 ValidationError
await repo.save(user)
```

### 10. ViewModel 映射

```typescript
import { ViewModelMapper } from '@offlinecat/ocorm'

class UserViewModel {
  id: number = 0
  name: string = ''
  displayName: string = ''
}

// EntityData → ViewModel
const vm = ViewModelMapper.toViewModel(
  entityData,
  () => new UserViewModel(),
  (data, vm) => {
    vm.id = data.getPropertyValue('id') as number
    vm.name = data.getPropertyValue('name') as string
    vm.displayName = `${vm.name} (ID: ${vm.id})`
  }
)

// 批量转换
const viewModels = ViewModelMapper.toViewModelArray(entities, factory, mapper)
```

### 11. 日志与调试

```typescript
import { Logger, LogLevel } from '@offlinecat/ocorm'

const logger = Logger.getInstance()
logger.configure(true, LogLevel.DEBUG)  // 开发环境
logger.configure(true, LogLevel.ERROR)  // 生产环境

// 敏感数据自动脱敏
// SQL: SELECT * FROM users WHERE name = '[***]'
```

### 12. 查询缓存

```typescript
import { QueryCache } from '@offlinecat/ocorm'

const cache = QueryCache.getInstance()
cache.configure({
  maxSize: 200,
  ttlMs: 60000,
  enabled: true
})

// Repository.findById 自动使用缓存
// 写操作自动使缓存失效
```

## 文档

📚 **[完整开发文档](./docs/developer-guide/00-目录索引.md)**

### 入门基础
| 文档 | 说明 |
|------|------|
| [初始化配置](./docs/developer-guide/01-初始化配置.md) | DatabaseConfig、OCORMInit、自动建表 |
| [实体定义](./docs/developer-guide/02-实体定义.md) | Schema 方式、装饰器方式、EntitySchema |
| [列类型与选项](./docs/developer-guide/03-列类型与选项.md) | ColumnType、列选项、主键定义 |

### 数据操作
| 文档 | 说明 |
|------|------|
| [Repository操作](./docs/developer-guide/04-Repository基础操作.md) | CRUD、EntityData、SaveResult |
| [QueryBuilder查询](./docs/developer-guide/05-QueryBuilder查询.md) | 链式 API、ConditionOperator |
| [分页与排序](./docs/developer-guide/06-分页与排序.md) | PaginatedResult、orderBy |
| [批量操作](./docs/developer-guide/07-批量操作.md) | batchInsert、BatchInsertOptions |
| [事务处理](./docs/developer-guide/08-事务处理.md) | TransactionOptions、隔离级别 |

### 关系映射
| 文档 | 说明 |
|------|------|
| [一对一关系](./docs/developer-guide/09-一对一关系.md) | RelationMetadata、外键位置 |
| [一对多关系](./docs/developer-guide/10-一对多关系.md) | ONE_TO_MANY、MANY_TO_ONE |
| [多对多关系](./docs/developer-guide/11-多对多关系.md) | 中间表、attach/detach/sync |
| [关联加载策略](./docs/developer-guide/12-关联加载策略.md) | with 预加载、withLazy 延迟加载 |

### 高级功能
| 文档 | 说明 |
|------|------|
| [软删除](./docs/developer-guide/13-软删除.md) | 软删除配置、restore、withDeleted |
| [生命周期钩子](./docs/developer-guide/14-生命周期钩子.md) | beforeSave、afterLoad、beforeDelete |
| [数据验证](./docs/developer-guide/15-数据验证.md) | required、length、email |
| [Schema迁移](./docs/developer-guide/16-Schema迁移.md) | MigrationManager、自动迁移 |

### 数据处理与运维
| 文档 | 说明 |
|------|------|
| [数据映射](./docs/developer-guide/17-数据映射.md) | EntityData、DataMapper、TypeConverter |
| [ViewModel映射](./docs/developer-guide/18-ViewModel映射.md) | ViewModelMapper、双向转换 |
| [日志系统](./docs/developer-guide/19-日志系统.md) | Logger、LogLevel、敏感数据脱敏 |
| [错误处理](./docs/developer-guide/20-错误处理.md) | OrmError、错误码、国际化 |
| [查询缓存](./docs/developer-guide/21-查询缓存.md) | QueryCache、TTL、缓存失效 |

### 参考资料
| 文档 | 说明 |
|------|------|
| [API速查表](./docs/developer-guide/22-API速查表.md) | Repository、QueryBuilder、EntityData API |
| [类型定义速查](./docs/developer-guide/23-类型定义速查.md) | 枚举、接口、结果类型 |
| [最佳实践](./docs/developer-guide/24-最佳实践.md) | 项目结构、性能优化、常见问题 |
| [代码示例集](./docs/developer-guide/25-代码示例集.md) | 完整场景代码示例 |

## 兼容性

- HarmonyOS NEXT (API 17+)
- OpenHarmony 5.0+
- 目标 SDK: 6.0.1 (API 21)

## 贡献

欢迎提交 Issue 和 Pull Request！

- 📖 [贡献指南](https://github.com/offlinecat-dev/OCNetORM/blob/main/.github/CONTRIBUTING.md) - 如何参与贡献
- 📜 [行为准则](https://github.com/offlinecat-dev/OCNetORM/blob/main/.github/CODE_OF_CONDUCT.md) - 社区行为规范
- 🔒 [安全政策](https://github.com/offlinecat-dev/OCNetORM/blob/main/.github/SECURITY.md) - 漏洞报告流程
- 🐛 [Bug 报告](https://github.com/offlinecat-dev/OCNetORM/issues/new?template=bug_report.md) - 提交 Bug
- ✨ [功能请求](https://github.com/offlinecat-dev/OCNetORM/issues/new?template=feature_request.md) - 提交功能建议
- 🔀 [Pull Request](https://github.com/offlinecat-dev/OCNetORM/pulls) - 提交代码

## License

MIT License - Copyright (c) 2026 offlinecat-dev
