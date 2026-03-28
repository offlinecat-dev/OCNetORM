# 04-安全原生SQL

> 状态：已完成  
> 适用版本：ocorm 3.x（当前仓库）
> 最后更新：2026-03-28

## 场景问题
你需要执行 ORM 链式 API 不好表达的 SQL（CTE、Explain、复杂统计），但又要保证：
1. 只读查询不会误写库
2. 写 SQL 走参数化，避免注入和误操作
3. 写后缓存一致性可控

## 完整方案
- 读：优先 `rawQuerySafe`
- 写：只用 `rawExecute`
- 全部 SQL 必须使用 `?` 占位符，并与参数数量严格一致

```arkts
import { EntityData, Repository } from 'ocorm'

export async function queryAdults(repo: Repository, minAge: number): Promise<Array<EntityData>> {
  return await repo.rawQuerySafe(
    'SELECT id, user_name FROM users WHERE age >= ?',
    [minAge]
  )
}

export async function renameUser(repo: Repository, id: number, newName: string): Promise<void> {
  await repo.rawExecute(
    'UPDATE users SET user_name = ? WHERE id = ?',
    [newName, id]
  )
}
```

## 验证
最小验证集：
1. 占位符数量不匹配会抛 `ExecutionError('RAW_QUERY', ...)`
2. `rawQuery` 禁止写 SQL
3. `rawExecute` 成功后会清空查询缓存

```arkts
import { EntityData, ExecutionError, QueryCache, Repository } from 'ocorm'

async function verify(repo: Repository): Promise<void> {
  try {
    await repo.rawQuerySafe('SELECT * FROM users WHERE id = ?', [])
  } catch (error) {
    if (error instanceof ExecutionError) {
      console.error('参数校验生效:', error.message)
    }
  }

  try {
    await repo.rawQuery('DELETE FROM users WHERE id = ?', [1])
  } catch (error) {
    if (error instanceof ExecutionError) {
      console.error('只读守卫生效:', error.message)
    }
  }

  const cache = QueryCache.getInstance()
  cache.configure({ enabled: true })
  const cached = new EntityData('User')
  cached.addProperty('id', 1, 'number')
  cache.set('User', 1, cached)

  await repo.rawExecute('UPDATE users SET user_name = ? WHERE id = ?', ['Alice', 1])
  console.info(cache.getSize()) // 0（rawExecute 内部 clear）
}
```

## 失败修复
1. 失败：`RAW_QUERY 仅允许参数化 SQL` / `RAW_EXECUTE 仅允许参数化 SQL`  
修复：禁止拼接值，全部改成 `?` + 参数数组。

2. 失败：`RAW_QUERY 禁止写操作 SQL`  
修复：读写分离；写操作改走 `rawExecute`。

3. 失败：`RAW_EXECUTE 不允许执行多条 SQL` 或 `禁止 SQL 注释片段`  
修复：一条 SQL 做一件事，去掉 `;` 后续语句和注释片段。

4. 失败：事务里被写入守卫拦截（未绑定事务上下文）  
修复：事务回调内使用 `txRepo.rawExecute(...)`，不要混用外部 repo 实例。
