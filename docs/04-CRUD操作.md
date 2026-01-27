# CRUD 操作

本章节介绍 OCORM 中的基础 CRUD（Create、Read、Update、Delete）操作，包括数据的增删改查和 EntityData 的使用方法。

## Repository 概述

`Repository` 是 OCORM 的数据访问层，提供实体的 CRUD 操作。每个实体对应一个 Repository 实例。

```typescript
import { Repository } from 'ocorm'

// 创建 User 实体的 Repository
const userRepo = new Repository('User')
```

## 创建数据（Create）

### 使用 EntityData.from()

推荐使用 `EntityData.from()` 快速构建实体数据：

```typescript
import { Repository, EntityData } from 'ocorm'

const repo = new Repository('User')

// 使用 from() 方法创建实体数据
const userData = EntityData.from('User', {
  name: '张三',
  email: 'zhangsan@example.com',
  age: 25
})

// 保存数据
const result = await repo.save(userData)

if (result.success) {
  console.info(`用户创建成功，ID: ${result.insertId}`)
  console.info(`影响行数: ${result.affectedRows}`)
}
```

### 手动构建 EntityData

也可以手动构建 EntityData：

```typescript
import { Repository, EntityData } from 'ocorm'

const repo = new Repository('User')

// 手动创建
const userData = new EntityData('User')
userData.addProperty('name', '李四', 'string')
userData.addProperty('email', 'lisi@example.com', 'string')
userData.addProperty('age', 30, 'number')

// 如果是自增主键，ID 设置为 0 或 null
userData.addProperty('id', 0, 'number')

// 保存
await repo.save(userData)
```

### EntityData 方法说明

| 方法 | 说明 |
|------|------|
| `addProperty(key, value, type)` | 添加属性 |
| `getProperty(key)` | 获取属性 |
| `setPropertyValue(key, value)` | 设置属性值 |
| `getPropertyValue(key)` | 获取属性值 |
| `removeProperty(key)` | 删除属性 |
| `getEntityName()` | 获取实体名称 |

## 读取数据（Read）

### 根据主键查询

```typescript
import { Repository } from 'ocorm'

const repo = new Repository('User')

// 根据 ID 查询单个实体
const user = await repo.findById(1)

if (user) {
  const name = user.getPropertyValue('name') as string
  const age = user.getPropertyValue('age') as number
  console.info(`姓名: ${name}, 年龄: ${age}`)
} else {
  console.info('用户不存在')
}
```

### 查询所有数据

```typescript
// 查询所有用户
const allUsers = await repo.findAll()

allUsers.forEach(user => {
  const id = user.getPropertyValue('id') as number
  const name = user.getPropertyValue('name') as string
  console.info(`[${id}] ${name}`)
})

console.info(`共 ${allUsers.length} 个用户`)
```

### 统计数量

```typescript
const count = await repo.count()
console.info(`用户总数: ${count}`)
```

### ResultSetUtils 获取列值

`ResultSetUtils.getColumnValues` 支持传入实体元数据，用于按列类型读取值；未传入元数据时会根据 ResultSet 的运行时类型进行解析：

```typescript
import { ResultSetUtils, MetadataStorage } from 'ocorm'

const store = DatabaseManager.getInstance().getStore()
const predicates = new relationalStore.RdbPredicates('users')
const resultSet = await store.query(predicates)

const metadata = MetadataStorage.getInstance().getEntityMetadata('User')
const ids = ResultSetUtils.getColumnValues(resultSet, 'id', metadata)
resultSet.close()
```

## 更新数据（Update）

### 先查询后更新

```typescript
import { Repository } from 'ocorm'

const repo = new Repository('User')

// 1. 查询要更新的实体
const user = await repo.findById(1)

if (user) {
  // 2. 修改属性值
  user.setPropertyValue('name', '王五')
  user.setPropertyValue('age', 35)
  
  // 3. 保存更新
  const result = await repo.save(user)
  
  if (result.success) {
    console.info(`用户 ${user.getPropertyValue('id')} 已更新`)
  }
}
```

### 直接更新（带条件）

通过查询构建器进行条件更新：

```typescript
import { Repository, ConditionOperator } from 'ocorm'

const repo = new Repository('User')

// 将所有未成年用户的 status 设置为 0
const users = await repo.createQueryBuilder()
  .where('age', ConditionOperator.LESS, 18)
  .getMany()

for (const user of users) {
  user.setPropertyValue('status', 0)
  await repo.save(user)
}
```

## 删除数据（Delete）

### 根据主键删除

```typescript
import { Repository } from 'ocorm'

const repo = new Repository('User')

// 删除指定 ID 的用户
const result = await repo.removeById(1)

if (result.success) {
  console.info(`删除成功，影响行数: ${result.affectedRows}`)
} else {
  console.error(`删除失败: ${result.errorMessage}`)
}
```

### 删除实体对象

```typescript
import { Repository } from 'ocorm'

const repo = new Repository('User')

// 查询后再删除
const user = await repo.findById(1)

if (user) {
  const result = await repo.remove(user)
  if (result.success) {
    console.info('删除成功')
  }
}
```

## 保存或更新判断

`save()` 方法会自动判断是插入还是更新：

```typescript
import { Repository, EntityData } from 'ocorm'

const repo = new Repository('User')

// 新建实体（主键为 0 或 null）-> 执行 INSERT
const newUser = EntityData.from('User', {
  name: '新用户',
  email: 'new@example.com'
})
await repo.save(newUser)  // INSERT

// 已存在实体（有主键值）-> 执行 UPDATE
const existingUser = await repo.findById(1)
existingUser.setPropertyValue('name', '修改后的名字')
await repo.save(existingUser)  // UPDATE
```

## 批量保存

```typescript
import { Repository, EntityData } from 'ocorm'

const repo = new Repository('User')

const users: EntityData[] = [
  EntityData.from('User', { name: '用户1', email: 'user1@example.com' }),
  EntityData.from('User', { name: '用户2', email: 'user2@example.com' }),
  EntityData.from('User', { name: '用户3', email: 'user3@example.com' })
]

// 逐条保存
for (const user of users) {
  await repo.save(user)
}

// 或使用 saveAll
const results = await repo.saveAll(users)

results.forEach((result, index) => {
  if (result.success) {
    console.info(`用户 ${index + 1} 保存成功，ID: ${result.insertId}`)
  } else {
    console.error(`用户 ${index + 1} 保存失败: ${result.errorMessage}`)
  }
})
```

## 完整服务示例

```typescript
// services/UserService.ts
import { Repository, EntityData, ConditionOperator } from 'ocorm'

export class UserService {
  private repo: Repository

  constructor() {
    this.repo = new Repository('User')
  }

  // 创建用户
  async createUser(name: string, email: string, age: number): Promise<number | null> {
    const userData = EntityData.from('User', {
      name: name,
      email: email,
      age: age,
      createdAt: Date.now(),
      updatedAt: Date.now()
    })

    const result = await this.repo.save(userData)
    return result.success ? result.insertId : null
  }

  // 根据 ID 获取用户
  async getUserById(id: number): Promise<EntityData | null> {
    return await this.repo.findById(id)
  }

  // 获取所有用户
  async getAllUsers(): Promise<EntityData[]> {
    return await this.repo.findAll()
  }

  // 根据条件查询用户
  async getUsersByAge(minAge: number): Promise<EntityData[]> {
    return await this.repo.createQueryBuilder()
      .where('age', ConditionOperator.GREATER_OR_EQUAL, minAge)
      .orderBy('age', 'DESC')
      .getMany()
  }

  // 更新用户信息
  async updateUser(id: number, updates: Record<string, any>): Promise<boolean> {
    const user = await this.repo.findById(id)
    
    if (!user) {
      return false
    }

    // 更新指定字段
    Object.keys(updates).forEach(key => {
      user.setPropertyValue(key, updates[key])
    })
    
    // 更新修改时间
    user.setPropertyValue('updatedAt', Date.now())

    const result = await this.repo.save(user)
    return result.success
  }

  // 删除用户
  async deleteUser(id: number): Promise<boolean> {
    const result = await this.repo.removeById(id)
    return result.success && result.affectedRows > 0
  }

  // 获取用户数量
  async getUserCount(): Promise<number> {
    return await this.repo.count()
  }

  // 检查邮箱是否已存在
  async isEmailExists(email: string): Promise<boolean> {
    const users = await this.repo.createQueryBuilder()
      .where('email', ConditionOperator.EQUAL, email)
      .getMany()
    return users.length > 0
  }
}
```

## 使用示例

```typescript
// 在页面中使用
import { UserService } from '../services/UserService'

@Entry
@Component
struct UserPage {
  private userService = new UserService()
  @State users: EntityData[] = []
  @State message: string = ''

  aboutToAppear() {
    this.loadUsers()
  }

  async loadUsers() {
    this.users = await this.userService.getAllUsers()
  }

  async addUser() {
    const id = await this.userService.createUser('测试用户', 'test@example.com', 20)
    if (id) {
      this.message = `创建成功，ID: ${id}`
      this.loadUsers()
    } else {
      this.message = '创建失败'
    }
  }

  async deleteUser(id: number) {
    const success = await this.userService.deleteUser(id)
    if (success) {
      this.message = '删除成功'
      this.loadUsers()
    }
  }

  build() {
    Column() {
      Text(this.message)
      Button('添加用户')
        .onClick(() => this.addUser())
      List() {
        ForEach(this.users, (user: EntityData) => {
          ListItem() {
            Row() {
              Text(`ID: ${user.getPropertyValue('id')}`)
              Text(`姓名: ${user.getPropertyValue('name')}`)
              Button('删除')
                .onClick(() => this.deleteUser(user.getPropertyValue('id') as number))
            }
          }
        })
      }
    }
  }
}
```

## 返回值说明

### SaveResult

| 属性 | 类型 | 说明 |
|------|------|------|
| `success` | boolean | 操作是否成功 |
| `affectedRows` | number | 受影响的行数 |
| `insertId` | number | 插入的记录 ID（仅 INSERT 操作） |
| `errorMessage` | string | 错误信息 |

### DeleteResult

| 属性 | 类型 | 说明 |
|------|------|------|
| `success` | boolean | 操作是否成功 |
| `affectedRows` | number | 受影响的行数 |
| `errorMessage` | string | 错误信息 |

## 下一步

- [查询构建器](05-查询构建器.md) - 学习更复杂的查询条件
- [关联关系](06-关联关系.md) - 查询关联数据
- [生命周期钩子](08-生命周期钩子.md) - 在 CRUD 操作中嵌入业务逻辑




