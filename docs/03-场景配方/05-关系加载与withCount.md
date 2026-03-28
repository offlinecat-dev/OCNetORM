# 05-关系加载与withCount

> 状态：已完成  
> 适用版本：ocorm 3.x（当前仓库）
> 最后更新：2026-03-28

## 场景问题
你要在一个列表请求里同时拿到：
1. 主实体（如 User）
2. 受条件约束的关联（如最近 5 条 Post）
3. 关联计数（如评论总数）
4. 可按需触发的延迟关联（如 profile）

如果做成 N+1 查询，性能和一致性都会变差。

## 完整方案
在同一个 `QueryBuilder` 上组合 `with`、`withWhere`、`withCount`、`withLazy`，再由 `QueryExecutor` 一次执行。

```arkts
import { ConditionOperator, QueryExecutor, Repository } from 'ocorm'

export async function queryUsersWithRelations(repo: Repository) {
  const qb = repo.createQueryBuilder()
    .with('posts.comments')
    .withWhere('posts', (relationQb) => {
      relationQb
        .where('title', ConditionOperator.LIKE, '%ArkTS%')
        .orderBy('title', 'DESC')
        .limit(5)
    })
    .withCount('posts.comments', 'comments_count')
    .withLazy('profile')

  return await new QueryExecutor(qb).get()
}
```

读取结果时，`withCount` 计数别名会被写入实体字段和 transient：

```arkts
import { EntityData } from 'ocorm'

function printUserRelationView(users: Array<EntityData>): void {
  for (let i = 0; i < users.length; i++) {
    const user = users[i]
    const postList = user.getRelatedArray('posts')
    const commentsCount = user.getTransient('comments_count')
    const profileLazy = user.hasLazyRelation('profile')

    console.info(`posts=${postList.length}, comments=${commentsCount}, lazyProfile=${profileLazy}`)
  }
}
```

## 验证
三步够用：
1. 验证 `withCount('posts')` 默认别名为 `posts_count`
2. 验证 `withWhere` 回调异常会抛 `InvalidConditionError('withWhere', ... )`
3. 验证 `withLazy` 关联可以通过 `loadRelated*` 按需加载

```arkts
import { InvalidConditionError, QueryBuilder, Repository } from 'ocorm'

async function verify(repo: Repository): Promise<void> {
  const qb = repo.createQueryBuilder().withCount('posts')
  const options = qb.getRelationCountOptions()
  console.info(options[0].alias) // posts_count

  try {
    repo.createQueryBuilder().withWhere('posts', () => {
      throw new Error('callback failed')
    })
  } catch (error) {
    if (error instanceof InvalidConditionError) {
      console.error('withWhere 保护生效:', error.message)
    }
  }
}
```

## 失败修复
1. 失败：`RelationNotFoundError`（关系路径写错）  
修复：关系名必须与 `MetadataStorage` 注册的 relation 名一致，嵌套路径逐段检查。

2. 失败：`InvalidConditionError('withCount', '非法别名: ...')`  
修复：别名只允许 `[A-Za-z_][A-Za-z0-9_]*`。

3. 失败：`withWhere` 回调抛异常导致整条查询失败  
修复：把复杂条件构建拆成纯函数，先单测回调逻辑，再接入 `withWhere`。

4. 失败：误把 `withLazy` 当成已加载数据  
修复：读取前先判断 `hasLazyRelation`，需要时调用 `loadRelatedArray` / `loadRelatedSingle`。
