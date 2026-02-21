# OCORM 使用示例

本目录包含 OCORM 框架的完整使用示例，帮助开发者快速上手。

## 目录结构

```
example/
├── entity/                    # 实体定义示例
│   └── UserEntity.ets        # 用户实体类
├── repository/               # 仓库操作示例
│   └── UserRepository.ets    # 用户仓库类
├── database/                 # 数据库初始化示例
│   └── DatabaseInit.ets      # 数据库初始化器
├── pages/                    # ArkUI 页面示例
│   └── UsageExamplePage.ets  # 图形界面示例页面
├── UsageExample.ets          # 完整使用示例（函数版）
└── README.md                 # 本文档
```

## 快速开始

### 1. 安装依赖

```bash
ohpm install @offlinecat/ocorm
```

### 2. 定义实体

```typescript
import { defineEntity, ColumnType, EntitySchema } from '@offlinecat/ocorm'

// 定义实体类
class UserEntity {
  id: number = 0
  username: string = ''
  email: string = ''
}

// 定义 Schema
const UserSchema: EntitySchema = {
  tableName: 'users',
  columns: [
    { property: 'id', primaryKey: true, autoIncrement: true },
    { property: 'username', type: ColumnType.TEXT, nullable: false },
    { property: 'email', type: ColumnType.TEXT, unique: true }
  ]
}

// 注册实体
defineEntity('UserEntity', UserSchema)
```

### 3. 初始化数据库

在 EntryAbility 的 onCreate 中初始化：

```typescript
import { OCORMInit, DatabaseConfig } from '@offlinecat/ocorm'
import { relationalStore } from '@kit.ArkData'

async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam) {
  // 先注册实体
  defineEntity('UserEntity', UserSchema)
  
  // 初始化数据库（3.0 起 encrypt 默认为 true）
  const config = new DatabaseConfig('app.db', relationalStore.SecurityLevel.S1)
  await OCORMInit(this.context, {
    config,
    autoCreateTables: true
  })
}
```

### 4. 使用仓库进行 CRUD 操作

```typescript
import { Repository, EntityData } from '@offlinecat/ocorm'

const repository = new Repository('UserEntity')

// 创建
const userData = new EntityData('UserEntity')
userData.addProperty('username', 'zhangsan', 'string')
userData.addProperty('email', 'zhangsan@example.com', 'string')
const saveResult = await repository.save(userData)

// 查询
const user = await repository.findById(1)
const allUsers = await repository.findAll()

// 更新
if (user !== null) {
  user.setPropertyValue('username', 'lisi')
  await repository.save(user)
}

// 删除
await repository.removeById(1)
```

### 5. 使用查询构建器

```typescript
import { QueryExecutor, ConditionOperator } from '@offlinecat/ocorm'

const repository = new Repository('UserEntity')

// 条件查询
const queryBuilder = repository.createQueryBuilder()
  .where('username', ConditionOperator.EQUAL, 'zhangsan')
  .orderBy('createdAt', 'DESC')
  .limit(10)

const executor = new QueryExecutor(queryBuilder)
const results = await executor.get()
```

## 更多示例

- **实体定义**: 查看 `entity/UserEntity.ets`
- **仓库操作**: 查看 `repository/UserRepository.ets`
- **数据库初始化**: 查看 `database/DatabaseInit.ets`
- **完整示例**: 查看 `UsageExample.ets`

## 功能特性

- ✅ 实体定义与注册
- ✅ 自动建表
- ✅ CRUD 操作
- ✅ 链式查询构建器
- ✅ 分页查询
- ✅ 软删除
- ✅ 事务支持
- ✅ 查询缓存
- ✅ 日志记录

## 3.0 使用提示

- `DatabaseConfig.encrypt` 默认已开启，示例保持加密默认行为
- `TransactionOptions.serializable()` 在 3.0 中为 fail-fast（创建时直接抛错）
- 事务隔离级别建议优先使用 `READ_COMMITTED`

## 文档

完整文档请访问: https://github.com/offlinecat-dev/OCNetORM
