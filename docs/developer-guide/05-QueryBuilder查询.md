# QueryBuilder 查询

`QueryBuilder` 提供链式调用 API 构建复杂的数据库查询。

---

## 创建 QueryBuilder

```typescript
import { QueryBuilder, Repository } from '@aspect/ocorm'

// 方式1：直接创建
const qb = new QueryBuilder('User')

// 方式2：通过 Repository 创建（推荐）
const userRepo = new Repository('User')
const qb = userRepo.createQueryBuilder()
```

---

## 执行查询

QueryBuilder 构建查询后，需要通过 `QueryExecutor` 执行：

```typescript
import { QueryBuilder, QueryExecutor, ConditionOperator } from '@aspect/ocorm'

const qb = new QueryBuilder('User')
qb.where('age', ConditionOperator.GREATER, 18)
  .orderBy('name', 'ASC')
  .limit(10)

const executor = new QueryExecutor(qb)

// 获取所有结果
const users = await executor.get()

// 获取单条结果
const user = await executor.first()

// 获取数量
const count = await executor.count()

// 分页查询
const paginated = await executor.getPaginated()
```

---

## ConditionOperator 操作符

```typescript
import { ConditionOperator } from '@aspect/ocorm'

enum ConditionOperator {
  EQUAL = 'EQUAL',               // =
  NOT_EQUAL = 'NOT_EQUAL',       // !=
  GREATER = 'GREATER',           // >
  GREATER_EQUAL = 'GREATER_EQUAL', // >=
  LESS = 'LESS',                 // <
  LESS_EQUAL = 'LESS_EQUAL',     // <=
  LIKE = 'LIKE',                 // LIKE
  NOT_LIKE = 'NOT_LIKE',         // NOT LIKE
  IN = 'IN',                     // IN
  NOT_IN = 'NOT_IN',             // NOT IN
  IS_NULL = 'IS_NULL',           // IS NULL
  IS_NOT_NULL = 'IS_NOT_NULL',   // IS NOT NULL
  BETWEEN = 'BETWEEN'            // BETWEEN
}
```

---

## where - 基础条件

```typescript
import { QueryBuilder, ConditionOperator } from '@aspect/ocorm'

const qb = new QueryBuilder('User')

// 等于
qb.where('name', ConditionOperator.EQUAL, '张三')

// 不等于
qb.where('status', ConditionOperator.NOT_EQUAL, 0)

// 大于
qb.where('age', ConditionOperator.GREATER, 18)

// 大于等于
qb.where('age', ConditionOperator.GREATER_EQUAL, 18)

// 小于
qb.where('age', ConditionOperator.LESS, 60)

// 小于等于
qb.where('age', ConditionOperator.LESS_EQUAL, 60)
```

### 使用属性名或列名

```typescript
// 使用属性名（推荐）
qb.where('userName', ConditionOperator.EQUAL, '张三')

// 使用数据库列名
qb.where('user_name', ConditionOperator.EQUAL, '张三')
```

---

## andWhere / orWhere - 组合条件

```typescript
const qb = new QueryBuilder('User')

// AND 条件
qb.where('age', ConditionOperator.GREATER, 18)
  .andWhere('status', ConditionOperator.EQUAL, 1)

// OR 条件
qb.where('name', ConditionOperator.EQUAL, '张三')
  .orWhere('name', ConditionOperator.EQUAL, '李四')

// 混合使用
qb.where('status', ConditionOperator.EQUAL, 1)
  .andWhere('age', ConditionOperator.GREATER, 18)
  .orWhere('isVip', ConditionOperator.EQUAL, 1)
// 等价于: status = 1 AND age > 18 OR isVip = 1
```

---

## whereIn - IN 条件

```typescript
const qb = new QueryBuilder('User')

// 查询 ID 在指定列表中的用户
qb.whereIn('id', [1, 2, 3, 4, 5])

// 查询状态为多个值之一
qb.whereIn('status', [1, 2])
```

---

## whereNull / whereNotNull - NULL 条件

```typescript
const qb = new QueryBuilder('User')

// 查询 email 为空的用户
qb.whereNull('email')

// 查询 email 不为空的用户
qb.whereNotNull('email')
```

---

## whereBetween - 区间条件

```typescript
const qb = new QueryBuilder('User')

// 查询年龄在 18-60 之间的用户
qb.whereBetween('age', 18, 60)

// 查询指定时间范围内创建的用户
const startTime = Date.now() - 7 * 24 * 60 * 60 * 1000  // 7天前
const endTime = Date.now()
qb.whereBetween('createdAt', startTime, endTime)
```

---

## whereLike - 模糊匹配

```typescript
const qb = new QueryBuilder('User')

// 包含匹配
qb.whereLike('name', '%张%')

// 前缀匹配
qb.whereLike('name', '张%')

// 后缀匹配
qb.whereLike('email', '%@gmail.com')
```

---

## orderBy - 排序

```typescript
const qb = new QueryBuilder('User')

// 升序
qb.orderBy('name', 'ASC')

// 降序
qb.orderBy('createdAt', 'DESC')

// 多字段排序
qb.orderBy('status', 'DESC')
  .orderBy('createdAt', 'DESC')
```

---

## limit / offset - 限制和偏移

```typescript
const qb = new QueryBuilder('User')

// 限制返回数量
qb.limit(10)

// 设置偏移量
qb.offset(20)

// 组合使用（跳过前20条，取10条）
qb.limit(10).offset(20)
```

---

## paginate / forPage - 分页

```typescript
const qb = new QueryBuilder('User')

// 设置分页（页码从1开始）
qb.paginate(1, 10)  // 第1页，每页10条
qb.paginate(2, 10)  // 第2页，每页10条

// forPage 是 paginate 的别名
qb.forPage(1, 10)
```

### 分页查询执行

```typescript
const qb = new QueryBuilder('User')
qb.paginate(1, 10)

const executor = new QueryExecutor(qb)
const result = await executor.getPaginated()

console.log(result.data)        // 当前页数据
console.log(result.total)       // 总记录数
console.log(result.page)        // 当前页码
console.log(result.pageSize)    // 每页数量
console.log(result.totalPages)  // 总页数
```

---

## select - 选择列

```typescript
const qb = new QueryBuilder('User')

// 只选择指定列
qb.select(['id', 'name', 'email'])

// 默认选择所有列
qb.select([])  // 或不调用 select
```

---

## with - 关联预加载

```typescript
const qb = new QueryBuilder('User')

// 预加载 posts 关联
qb.with('posts')

// 预加载多个关联
qb.with('posts').with('profile')
```

### withLazy - 延迟加载

```typescript
const qb = new QueryBuilder('User')

// 延迟加载（不立即查询关联数据）
qb.withLazy('posts')
```

---

## 软删除相关

### withDeleted - 包含已删除数据

```typescript
const qb = new QueryBuilder('Article')

// 默认排除已删除数据
const articles = await new QueryExecutor(qb).get()

// 包含已删除数据
qb.withDeleted()
const allArticles = await new QueryExecutor(qb).get()
```

### onlyDeleted - 仅查询已删除数据

```typescript
const qb = new QueryBuilder('Article')

// 仅查询已删除的文章
qb.onlyDeleted()
const deletedArticles = await new QueryExecutor(qb).get()
```

---

## whereExists - 子查询过滤

基于关联实体的存在性过滤主实体。

```typescript
const qb = new QueryBuilder('User')

// 查询有文章的用户
qb.whereExists('posts', (subQuery) => {
  // 可以在子查询中添加条件
})

// 查询有已发布文章的用户
qb.whereExists('posts', (subQuery) => {
  subQuery.where('status', ConditionOperator.EQUAL, 'published')
})

// 查询有标题包含"技术"的文章的用户
qb.whereExists('posts', (subQuery) => {
  subQuery.where('title', ConditionOperator.LIKE, '%技术%')
})
```

---

## reset - 重置查询

```typescript
const qb = new QueryBuilder('User')

qb.where('age', ConditionOperator.GREATER, 18)
  .limit(10)

// 重置所有查询条件
qb.reset()

// 重新构建查询
qb.where('status', ConditionOperator.EQUAL, 1)
```

---

## 获取查询信息

```typescript
const qb = new QueryBuilder('User')
qb.where('age', ConditionOperator.GREATER, 18)
  .orderBy('name', 'ASC')
  .limit(10)

// 获取实体名
qb.getEntityName()  // 'User'

// 获取表名
qb.getTableName()  // 'users'

// 获取条件
qb.getConditions()

// 获取排序
qb.getOrderByColumns()

// 获取限制值
qb.getLimitValue()

// 获取偏移值
qb.getOffsetValue()

// 获取选择的列
qb.getSelectedColumns()

// 检查是否有分页
qb.hasPagination()

// 检查是否有关联
qb.hasRelations()

// 获取查询描述（调试用）
console.log(qb.getQueryDescription())
```

---

## 完整查询示例

### 基础查询

```typescript
import { QueryBuilder, QueryExecutor, ConditionOperator } from '@aspect/ocorm'

// 查询年龄大于18的活跃用户，按创建时间倒序，取前10条
const qb = new QueryBuilder('User')
qb.where('age', ConditionOperator.GREATER, 18)
  .andWhere('status', ConditionOperator.EQUAL, 1)
  .orderBy('createdAt', 'DESC')
  .limit(10)

const users = await new QueryExecutor(qb).get()
```

### 复杂条件查询

```typescript
const qb = new QueryBuilder('Article')

// 查询已发布的、标题包含"技术"的文章
qb.where('status', ConditionOperator.EQUAL, 'published')
  .andWhere('title', ConditionOperator.LIKE, '%技术%')
  .whereBetween('createdAt', startTime, endTime)
  .orderBy('viewCount', 'DESC')
  .paginate(1, 20)

const result = await new QueryExecutor(qb).getPaginated()
```

### 关联查询

```typescript
const qb = new QueryBuilder('User')

// 查询有文章的VIP用户，并预加载文章
qb.where('isVip', ConditionOperator.EQUAL, 1)
  .whereExists('posts', (sub) => {
    sub.where('status', ConditionOperator.EQUAL, 'published')
  })
  .with('posts')
  .orderBy('createdAt', 'DESC')

const users = await new QueryExecutor(qb).get()
```

### 软删除查询

```typescript
const qb = new QueryBuilder('Article')

// 查询所有文章（包括已删除）
qb.withDeleted()
  .orderBy('createdAt', 'DESC')

const allArticles = await new QueryExecutor(qb).get()

// 仅查询已删除的文章
qb.reset()
  .onlyDeleted()

const deletedArticles = await new QueryExecutor(qb).get()
```

---

## 链式调用模式

QueryBuilder 支持完整的链式调用：

```typescript
const result = await new QueryExecutor(
  new QueryBuilder('User')
    .where('status', ConditionOperator.EQUAL, 1)
    .andWhere('age', ConditionOperator.GREATER_EQUAL, 18)
    .whereNotNull('email')
    .orderBy('createdAt', 'DESC')
    .paginate(1, 20)
).getPaginated()
```
