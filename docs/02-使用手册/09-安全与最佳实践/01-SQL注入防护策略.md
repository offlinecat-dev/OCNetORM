# SQL注入防护策略

## 基线规则
- 一律参数化，不拼接用户输入
- 优先 `rawQuerySafe`，谨慎使用 `rawExecute`
- 禁止多语句和注释片段混入业务 SQL

## 推荐示例
```ts
import { Repository } from 'ocorm'

const repo = new Repository('User')
const rows = await repo.rawQuerySafe(
  'SELECT id, user_name FROM users WHERE age >= ?',
  [18]
)
```

## 误用示例
```ts
// 不要这样做
const sql = `SELECT * FROM users WHERE user_name = '${name}'`
```

## 排查建议
- 遇到原生 SQL 拒绝，先检查占位符和参数数量
- 对写操作逐条核查 SQL 来源，避免动态拼接
