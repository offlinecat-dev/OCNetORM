# OCORM

> **QQ 交流群：`1012852504`**  
> 欢迎加入交流 OCORM 使用经验、问题反馈与最佳实践。

**轻量级 HarmonyOS SQLite ORM 框架**

[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/Version-3.0.0-green.svg)](https://github.com/offlinecat-dev/OCNetORM/releases)
[![HarmonyOS](https://img.shields.io/badge/HarmonyOS-Next-orange.svg)](https://developer.harmonyos.com)
[![OpenHarmony](https://img.shields.io/badge/OpenHarmony-5.0+-purple.svg)](https://www.openharmony.cn)

基于 `@ohos.data.relationalStore` 构建，提供类型安全的数据库操作 API。  
当前文档对应 **OCORM 3.0.0**。

[![GitHub Repo](https://img.shields.io/badge/GitHub-Repository-black?style=for-the-badge&logo=github)](https://github.com/offlinecat-dev/OCNetORM)
[![Report Bug](https://img.shields.io/badge/Issues-Report_Bug-red?style=for-the-badge&logo=github)](https://github.com/offlinecat-dev/OCNetORM/issues)

## 目录

- [特性](#特性)
- [3.0 版本说明](#30-版本说明)
- [性能基准](#性能基准)
- [安装](#安装)
- [快速开始](#快速开始)
- [事务只读说明](#事务只读说明)
- [常用工作流](#常用工作流)
- [文档](#文档)
- [兼容性](#兼容性)
- [2.x 兼容性与升级说明](#2x-兼容性与升级说明)
- [常见问题](#常见问题)
- [贡献](#贡献)
- [License](#license)

## 特性

### 核心版（8 条）

- 🚀 轻量无额外运行时依赖，面向 HarmonyOS SQLite 的 ArkTS ORM
- 🔒 类型安全 API，统一 `Repository` + `QueryBuilder` + `QueryExecutor`
- 🧱 支持 `defineEntity` 与装饰器双模式建模
- 📦 完整 CRUD 与链式条件查询（分页、排序、过滤）
- 🔗 关系映射与加载（一对一/一对多/多对一/多对多，`with`/`withLazy`）
- 🔄 事务能力（基础事务 + 超时/重试/隔离级别）
- ✅ 数据治理（生命周期钩子、验证、软删除）
- 🛠️ Schema 自动建表与迁移（版本管理、回滚）

### 企业版扩展能力

- 🛡️ 原生 SQL 只读保护与 `readOnly` 事务连接状态自动恢复
- 🔍 高级查询能力（聚合、子查询 `whereExists`、`withCount`）
- ⚡ 性能增强（批量插入、查询缓存 TTL/LRU、查询并发槽控制）
- 🔀 工具链支持（Seeder / Factory / MigrationGenerator）
- 📈 工程化能力（ViewModel 双向映射、日志脱敏、错误国际化）

## 3.0 版本说明

- OCORM 3.0 是在 2.4.x 稳定线基础上的主版本升级，重点是安全策略统一与模块化重构收敛。
- 对日常开发最直接的变化是默认行为更安全、事务语义更严格、工具链能力更完整。

3.0 重点变化：
- 默认加密开启：`DatabaseConfig.encrypt` 默认值为 `true`
- 事务策略收紧：`serializable()` fail-fast；`REPEATABLE_READ/SERIALIZABLE` 当前实现显式拒绝执行
- SQL 安全增强：`HAVING` 风险关键字拦截，`ORDER BY` 方向运行时双重校验
- 新增工具链：`SeederManager`、`defineFactory`、`MigrationGenerator`

来自《功能增强路线图》的已落地能力（`docs/99-功能增强路线图.md`）：
- 聚合与分组查询（`sum/avg/max/min`、`groupBy/having/selectRaw`）
- 原生 SQL 能力（`rawQuery/rawExecute`，含安全约束）
- 查询作用域（`scope/scopes`）
- 关联增强（`withWhere`、`withCount`、MorphTo 9.4）
- 批量更新/删除与分块查询（`update/delete/chunk`）

来自《安全审查报告》的闭环修复（`docs/17-安全审查报告-2026-02-10.md`）：
- 事务一致性硬化（并发串行互斥、超时清理后释放锁、只读语义收紧）
- SQL 安全加固（`HAVING`、`ORDER BY`、`rawExecute` 安全闸）
- 数据正确性修复（类型转换严格化、`@Unique` 索引映射、ManyToMany 主键类型统一）
- 缓存隔离修复（数据库命名空间与切库清缓存）

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

[![ohpm](https://img.shields.io/badge/ohpm-v3.0.0-blue?style=for-the-badge)](https://ohpm.openharmony.cn/)

在 HarmonyOS 项目的 `oh-package.json5` 中添加依赖：

```json5
{
  "dependencies": {
    "@offlinecat/ocorm": "3.0.0"
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
  isolation: IsolationLevel.READ_COMMITTED
})
await repo.transactionWithOptions(async (txRepo) => {
  // 关键业务操作
}, options)
```

## 事务只读说明

- `TransactionOptions.readOnly = true` 会在事务开始后尝试启用连接级只读模式（`PRAGMA query_only = 1`）。
- 事务结束后会自动恢复连接状态（`PRAGMA query_only = 0`），避免影响后续普通写操作。
- 如果底层环境不支持该 PRAGMA，事务会明确失败并返回错误，避免只读语义被静默绕过。
- 只读模式用于业务安全兜底，不建议将其作为数据库权限控制的唯一手段。

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

## 常用工作流

```bash
# 安装依赖
ohpm install

# 构建 HAR（OCORM 模块）
hvigor assembleHar

# 运行 OCORM 测试
hvigor test
```

- 示例代码：`../entry/src/main/ets/example`
- 开发文档：`./docs/developer-guide`
- 变更记录：`./CHANGELOG.md`

## 文档

📚 **[完整开发文档](./docs/developer-guide/00-目录索引.md)**
📍 **[文档入口导航](./docs/README.md)**

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

## 2.x 兼容性与升级说明

3.0 对 2.x 的定位是“API 主体兼容，默认行为收紧”。

保持兼容（通常无需改动）：
- `Repository` / `QueryBuilder` / `EntityData` 核心用法
- 关系映射、分页、缓存、迁移、验证的主调用路径
- 包入口导入方式：`import { ... } from '@offlinecat/ocorm'`

需要关注（可能影响旧行为）：
- `DatabaseConfig.encrypt` 默认值改为 `true`
- `TransactionOptions.serializable()` 改为 fail-fast
- `REPEATABLE_READ/SERIALIZABLE` 当前实现显式拒绝执行
- 只读事务在 `PRAGMA query_only` 不可用时将直接失败

升级建议（2.x -> 3.0）：
1. 显式检查 `DatabaseConfig` 中 `encrypt` 配置是否符合业务预期。
2. 将事务隔离级别统一调整为当前已支持级别（优先 `READ_COMMITTED`）。
3. 对 `readOnly` 事务补充失败分支处理，避免依赖旧版“降级继续执行”假设。

## 常见问题

### Q1：readOnly 事务会不会影响后续写操作？
- 不会。事务结束时会自动恢复连接级只读状态。

### Q2：为什么我看到“已降级为兼容模式”的日志？
- 3.0 起事务语义更严格。若你仍看到类似日志，通常来自旧版本运行日志或自定义封装层，请以当前版本行为为准并检查事务配置。

### Q3：生产环境建议开启什么日志级别？
- 建议 `LogLevel.ERROR`，开发环境可使用 `LogLevel.DEBUG`。

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
