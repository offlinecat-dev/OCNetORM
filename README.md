# OCORM

**轻量级 HarmonyOS SQLite ORM 框架**

[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/Version-2.4.12-green.svg)](https://github.com/offlinecat-dev/OCNetORM/releases)
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

[![ohpm](https://img.shields.io/badge/ohpm-v2.4.12-blue?style=for-the-badge)](https://ohpm.openharmony.cn/)

在 HarmonyOS 项目的 `oh-package.json5` 中添加依赖：

```json5
{
  "dependencies": {
    "@offlinecat/ocorm": "2.4.12"
  }
}
```

或使用命令行安装：

```bash
ohpm install @offlinecat/ocorm
```

## 快速使用

### 1. 定义实体

```typescript
import {
  MetadataStorage,
  ColumnMetadata,
  ColumnType,
  registerEntity,
  registerAutoIncrementPrimaryKey,
  createEntityOptions
} from '@offlinecat/ocorm'

registerEntity('User', createEntityOptions('users'))
registerAutoIncrementPrimaryKey('User', 'id', 'id')

const storage = MetadataStorage.getInstance()

const nameCol = new ColumnMetadata('name', 'name')
nameCol.columnType = ColumnType.TEXT
nameCol.isNullable = false
storage.registerColumn('User', nameCol)

const emailCol = new ColumnMetadata('email', 'email')
emailCol.columnType = ColumnType.TEXT
emailCol.isUnique = true
storage.registerColumn('User', emailCol)
```

### 2. 初始化数据库

```typescript
import { DatabaseManager, DatabaseConfig, SchemaBuilder } from '@offlinecat/ocorm'
import { relationalStore } from '@kit.ArkData'

const config = new DatabaseConfig('app.db', relationalStore.SecurityLevel.S1, false)
await DatabaseManager.getInstance().initialize(context, config)

const schemaBuilder = new SchemaBuilder()
await schemaBuilder.createAllTablesWithManager()
```

### 3. CRUD 操作

```typescript
import { Repository, EntityData } from '@offlinecat/ocorm'

const repo = new Repository('User')

// 创建并插入
const user = EntityData.from('User', {
  name: '张三',
  email: 'zhangsan@example.com'
})
await repo.save(user)

// 查询
const allUsers = await repo.findAll()
const user = await repo.findById(1)

// 更新
user.setPropertyValue('name', '李四')
await repo.save(user)

// 删除
await repo.removeById(1)
```

### 4. 链式查询

```typescript
const users = await repo.createQueryBuilder()
  .where('age', ConditionOperator.GREATER, 18)
  .andWhere('isActive', ConditionOperator.EQUAL, 1)
  .orderBy('name', 'ASC')
  .limit(10)
  .getMany()
```

### 5. 事务

```typescript
await repo.transaction(async (txRepo) => {
  await txRepo.save(user1)
  await txRepo.save(user2)
})
```

## 文档

📚 **[完整开发文档](./docs/developer-guide/00-目录索引.md)**

快速链接：
- [初始化配置](./docs/developer-guide/01-初始化配置.md)
- [实体定义](./docs/developer-guide/02-实体定义.md)
- [Repository操作](./docs/developer-guide/04-Repository基础操作.md)
- [QueryBuilder查询](./docs/developer-guide/05-QueryBuilder查询.md)
- [事务处理](./docs/developer-guide/08-事务处理.md)
- [关联关系](./docs/developer-guide/09-一对一关系.md)
- [错误处理](./docs/developer-guide/20-错误处理.md)
- [代码示例集](./docs/developer-guide/25-代码示例集.md)

## 兼容性

- HarmonyOS NEXT (API 17+)
- OpenHarmony 5.0+
- 目标 SDK: 6.0.1 (API 21)

## 贡献

欢迎提交 Issue 和 Pull Request！

- 📖 [贡献指南](./.github/CONTRIBUTING.md) - 如何参与贡献
- 📜 [行为准则](./.github/CODE_OF_CONDUCT.md) - 社区行为规范
- 🔒 [安全政策](./.github/SECURITY.md) - 漏洞报告流程
- 🐛 [Bug 报告模板](./.github/ISSUE_TEMPLATE/bug_report.md) - 提交 Bug
- ✨ [功能请求模板](./.github/ISSUE_TEMPLATE/feature_request.md) - 提交功能建议
- 🔀 [PR 模板](./.github/PULL_REQUEST_TEMPLATE.md) - 提交代码

## License

MIT License - Copyright (c) 2026 offlinecat-dev
