# Repository 基础操作

`Repository` 是 OCORM 的核心类，提供实体的 CRUD 操作接口。

---

## 创建 Repository

```typescript
import { Repository } from '@offlinecat/ocorm'

// 创建 User 实体的 Repository
const userRepo = new Repository('User')

// 创建 Article 实体的 Repository
const articleRepo = new Repository('Article')
```

> **注意**：实体必须在创建 Repository 之前通过 `defineEntity` 或装饰器注册，否则会抛出 `EntityNotRegisteredError`。

---

## EntityData 数据对象

OCORM 使用 `EntityData` 对象在应用层和数据库层之间传递数据。

### 创建 EntityData

```typescript
import { EntityData } from '@offlinecat/ocorm'

// 创建新实体数据（不含主键，用于插入）
const newUser = new EntityData('User')
newUser.addProperty('name', '张三', 'string')
newUser.addProperty('email', 'zhangsan@example.com', 'string')
newUser.addProperty('age', 25, 'number')

// 创建已有实体数据（含主键，用于更新）
const existingUser = new EntityData('User')
existingUser.addProperty('id', 1, 'number')
existingUser.addProperty('name', '李四', 'string')
existingUser.addProperty('email', 'lisi@example.com', 'string')
```

### EntityData 方法

```typescript
const data = new EntityData('User')

// 添加属性
data.addProperty('name', '张三', 'string')

// 获取属性值
const name = data.getPropertyValue('name')  // '张三'

// 检查是否有属性
data.hasProperty('name')  // true

// 获取所有属性名
data.getPropertyNames()  // ['name']

// 获取实体名
data.entityName  // 'User'
```

---

## save - 保存实体

`save` 方法根据主键自动判断是插入还是更新：
- 主键为空或 0 → 执行 INSERT
- 主键有值 → 执行 UPDATE

> **注意**：当数据验证失败（`ValidationError`）或 `beforeSave` 钩子执行失败（`HookExecutionError`）时，`save` 会直接抛出异常。

> **说明**：当前实现中，`update`/`remove` 等通过 `executeSync` 执行的操作返回的 `affectedRows` 为 `1` 表示执行成功，不一定反映数据库真实影响行数。

### 插入新记录

```typescript
const userRepo = new Repository('User')

const newUser = new EntityData('User')
newUser.addProperty('name', '张三', 'string')
newUser.addProperty('email', 'zhangsan@example.com', 'string')

const result = await userRepo.save(newUser)

if (result.success) {
  console.log(`插入成功，新 ID: ${result.insertId}`)
  console.log(`影响行数: ${result.affectedRows}`)
} else {
  console.log(`插入失败: ${result.errorMessage}`)
}
```

### 更新已有记录

```typescript
const existingUser = new EntityData('User')
existingUser.addProperty('id', 1, 'number')  // 指定主键
existingUser.addProperty('name', '张三（已修改）', 'string')
existingUser.addProperty('email', 'zhangsan_new@example.com', 'string')

const result = await userRepo.save(existingUser)

if (result.success) {
  console.log('更新成功')
}
```

### SaveResult 返回值

```typescript
class SaveResult {
  success: boolean      // 是否成功
  affectedRows: number  // 影响行数
  insertId: number      // 插入的自增 ID（仅 INSERT 有效）
  errorMessage: string  // 错误信息
}

// 静态工厂方法
SaveResult.createSuccess(affectedRows, insertId)
SaveResult.createFailure(errorMessage)
```

---

## findById - 根据主键查询

```typescript
const userRepo = new Repository('User')

// 查询 ID 为 1 的用户
const user = await userRepo.findById(1)

if (user !== null) {
  console.log(user.getPropertyValue('name'))
  console.log(user.getPropertyValue('email'))
} else {
  console.log('用户不存在')
}
```

### 包含已删除数据（软删除场景）

```typescript
// 默认排除已删除数据
const user = await userRepo.findById(1)

// 包含已删除数据
const userWithDeleted = await userRepo.findById(1, true)
```

### 禁用缓存

```typescript
// 默认使用缓存
const user = await userRepo.findById(1)

// 禁用缓存，强制从数据库读取
const freshUser = await userRepo.findById(1, false, false)
```

---

## findAll - 查询所有

```typescript
const userRepo = new Repository('User')

// 查询所有用户
const users = await userRepo.findAll()

for (const user of users) {
  console.log(user.getPropertyValue('name'))
}
```

### 包含已删除数据

```typescript
// 默认排除已删除数据
const users = await userRepo.findAll()

// 包含已删除数据
const allUsers = await userRepo.findAll(true)
```

### 异步查询（大数据量优化）

```typescript
// 使用 TaskPool 优化大数据量场景
const users = await userRepo.findAllAsync()
```

---

## remove / removeById - 删除实体

### 根据 EntityData 删除

```typescript
const userRepo = new Repository('User')

const user = new EntityData('User')
user.addProperty('id', 1, 'number')

const result = await userRepo.remove(user)

if (result.success) {
  console.log(`删除成功，影响行数: ${result.affectedRows}`)
}
```

### 根据主键删除

```typescript
const result = await userRepo.removeById(1)
```

### DeleteResult 返回值

```typescript
class DeleteResult {
  success: boolean      // 是否成功
  affectedRows: number  // 影响行数
  errorMessage: string  // 错误信息
}
```

### 软删除行为

如果实体启用了软删除：
- `remove` / `removeById` → 执行软删除（设置 `deleted_at` 字段）
- `forceRemove` / `forceRemoveById` → 执行物理删除

```typescript
// 软删除（设置 deleted_at）
await userRepo.removeById(1)

// 强制物理删除
await userRepo.forceRemoveById(1)
```

---

## restore - 恢复软删除

```typescript
const articleRepo = new Repository('Article')

// 恢复 ID 为 1 的文章
const result = await articleRepo.restore(1)

if (result.success) {
  console.log('恢复成功')
}
```

> **注意**：仅对启用软删除的实体有效，否则抛出 `SoftDeleteNotEnabledError`。

---

## count - 统计数量

```typescript
const userRepo = new Repository('User')

// 统计用户数量（排除已删除）
const count = await userRepo.count()

// 统计所有用户（包含已删除）
const totalCount = await userRepo.count(true)
```

---

## findPaginated - 分页查询

```typescript
const userRepo = new Repository('User')

// 查询第 1 页，每页 10 条
const result = await userRepo.findPaginated(1, 10)

console.log(`当前页: ${result.page}`)
console.log(`每页数量: ${result.pageSize}`)
console.log(`总数: ${result.total}`)
console.log(`总页数: ${result.totalPages}`)
console.log(`数据:`, result.data)
```

### PaginatedResult 结构

```typescript
class PaginatedResult {
  data: Array<EntityData>  // 当前页数据
  total: number            // 总记录数
  page: number             // 当前页码
  pageSize: number         // 每页数量
  totalPages: number       // 总页数
}
```

---

## saveAll - 批量保存

```typescript
const userRepo = new Repository('User')

const users: EntityData[] = []
for (let i = 0; i < 10; i++) {
  const user = new EntityData('User')
  user.addProperty('name', `用户${i}`, 'string')
  user.addProperty('email', `user${i}@example.com`, 'string')
  users.push(user)
}

const results = await userRepo.saveAll(users)

for (const result of results) {
  if (result.success) {
    console.log(`插入成功: ${result.insertId}`)
  }
}
```

---

## batchInsert - 高性能批量插入

使用 `RdbStore.batchInsert` API 实现高性能批量插入。

```typescript
import { BatchInsertOptions } from '@offlinecat/ocorm'

const userRepo = new Repository('User')

const users: EntityData[] = []
for (let i = 0; i < 1000; i++) {
  const user = new EntityData('User')
  user.addProperty('name', `用户${i}`, 'string')
  users.push(user)
}

// 使用默认选项（开启事务、执行钩子）
const result = await userRepo.batchInsert(users)

// 自定义选项
const options = new BatchInsertOptions()
options.useTransaction = true
options.executeHooks = false
options.executeValidation = true

const result2 = await userRepo.batchInsert(users, options)

console.log(`成功: ${result.success}`)
console.log(`插入数量: ${result.insertedCount}`)
console.log(`总数量: ${result.totalCount}`)
```

### BatchInsertResult 结构

```typescript
class BatchInsertResult {
  success: boolean           // 是否全部成功
  insertedCount: number      // 成功插入数量
  totalCount: number         // 总数量
  failedIndexes: number[]    // 失败的索引
  errorMessage: string       // 错误信息
}
```

---

## createQueryBuilder - 创建查询构建器

```typescript
const userRepo = new Repository('User')

// 获取 QueryBuilder 进行复杂查询
const qb = userRepo.createQueryBuilder()

// 参见 05-QueryBuilder查询.md
```

---

## 获取元数据和映射器

```typescript
const userRepo = new Repository('User')

// 获取实体元数据
const metadata = userRepo.getMetadata()
console.log(metadata.tableName)  // 'users'

// 获取数据映射器
const dataMapper = userRepo.getDataMapper()
```

---

## 完整 CRUD 示例

```typescript
import { Repository, EntityData, defineEntity, ColumnType, OCORMInit, DatabaseConfig } from '@offlinecat/ocorm'

// 1. 定义实体
defineEntity('User', {
  tableName: 'users',
  columns: [
    { property: 'id', primaryKey: true },
    { property: 'name', type: ColumnType.TEXT },
    { property: 'email', type: ColumnType.TEXT, unique: true },
    { property: 'createdAt', name: 'created_at', type: ColumnType.INTEGER }
  ]
})

// 2. 初始化 ORM
await OCORMInit(context, { config: new DatabaseConfig('app.db') })

// 3. 创建 Repository
const userRepo = new Repository('User')

// 4. 创建用户
const newUser = new EntityData('User')
newUser.addProperty('name', '张三', 'string')
newUser.addProperty('email', 'zhangsan@example.com', 'string')
newUser.addProperty('createdAt', Date.now(), 'number')

const saveResult = await userRepo.save(newUser)
const userId = saveResult.insertId

// 5. 查询用户
const user = await userRepo.findById(userId)
console.log(user?.getPropertyValue('name'))

// 6. 更新用户
user?.setPropertyValue('name', '张三（已更新）')
if (user) {
  await userRepo.save(user)
}

// 7. 查询所有用户
const allUsers = await userRepo.findAll()

// 8. 分页查询
const pagedUsers = await userRepo.findPaginated(1, 10)

// 9. 删除用户
await userRepo.removeById(userId)
```
