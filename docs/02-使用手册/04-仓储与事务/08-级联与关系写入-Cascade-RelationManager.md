# 08-级联与关系写入-Cascade-RelationManager

> 状态：已完成
> 适用版本：ocorm 3.x（当前仓库实现）
> 最后更新：2026-03-27

## 1. 目标
- 说明 `RelationManager` 如何处理 `attach`、`detach`、`sync`。
- 说明 `CascadeHandler` 如何在 save/update/remove 时驱动关联实体级联。
- 明确 SAVEPOINT、回退事务和重复关联的真实行为。

## 2. 背景与适用范围
仓储层里有两类“关系写入”：
- 多对多中间表写入：`RelationManager`
- 实体级联保存/更新/删除：`CascadeHandler`

前者面向 `attach/detach/sync` 这种显式关系操作，后者面向 `save/remove` 时的隐式级联。

## 3. `RelationManager` 真实行为
`attach` 会先查 join table 是否已存在，存在则直接返回成功但受影响行为 `0`。`sync` 会先删后插。二者都优先尝试 `SAVEPOINT`，失败后才退回到独立事务。

```arkts
import { Repository } from 'ocorm'

const postRepo = new Repository('Post')

await postRepo.attach(10, 3, 'tags')
await postRepo.detach(10, 3, 'tags')
await postRepo.sync(10, [1, 2, 3], 'tags')
```

```text
attach:
  SAVEPOINT attach_n
  -> 查询中间表是否已有(sourceId, targetId)
  -> 无则 INSERT
  -> RELEASE SAVEPOINT

sync:
  SAVEPOINT sync_n
  -> DELETE 当前 sourceId 的所有关系
  -> 逐条 INSERT targetIds
  -> RELEASE SAVEPOINT
```

## 4. `CascadeHandler` 真实行为
级联并不是“所有关系都自动写”。当前实现只在满足以下条件时触发：
- 关系元数据启用了对应方向的 cascade
- 关系类型在当前操作路径中被支持
- `EntityData` 上真实挂了相关联数据

```arkts
import { EntityData, EntityDataInput, Repository } from 'ocorm'

function makeProfile(id: number, bio: string): EntityData {
  const input = EntityDataInput.create()
  input.set('id', id)
  input.set('bio', bio)
  return EntityData.from('Profile', input)
}

function makeUser(id: number, name: string, profile: EntityData): EntityData {
  const input = EntityDataInput.create()
  input.set('id', id)
  input.set('name', name)
  const user = EntityData.from('User', input)
  user.setRelatedSingle('profile', profile)
  return user
}

const userRepo = new Repository('User')
const profile = makeProfile(2, 'hello')
const user = makeUser(1, 'Alice', profile)

await userRepo.save(user)
```

`CascadeHandler` 在不同操作里支持的方向不同：
- insert/update：会看 `MANY_TO_ONE`、`ONE_TO_ONE`、`ONE_TO_MANY`、`MANY_TO_MANY`
- remove：会先处理 many-to-many 清空，再处理级联删除
- 只有你把关联实体挂进 `EntityData` 的 related data（如 `setRelatedSingle/setRelatedArray`）后，级联路径才有数据可处理

## 5. 误用示例
最常见误用是把 `attach` 当成“重复调用也会插入多条”。当前实现会先查重，重复关联只返回成功 `0`，不会报错也不会重复插入。

```arkts
import { Repository } from 'ocorm'

const repo = new Repository('Post')

await repo.attach(1, 2, 'tags')
await repo.attach(1, 2, 'tags')

// 第二次不是失败，也不是插入第二行，而是 success(0)
```

另一个误用是期待“事务里不支持 SAVEPOINT 时自动无限降级”。当前实现如果已处在事务中而 SAVEPOINT 创建失败，会直接报错，不会再回退 `beginTransaction`。

```arkts
import { Repository } from 'ocorm'

const repo = new Repository('Post')

await repo.transaction(async (txRepo) => {
  // 误用：假设内部关系写入总能再开新事务兜底
  await txRepo.sync(1, [2, 3], 'tags')
})
```

## 6. 失败语义与抛错说明
`RelationManager` 的返回值有三个常见分支：
- 成功写入：`SaveResult.createSuccess(...)` / `DeleteResult.createSuccess(...)`
- 可接受的重复 attach：`SaveResult.createSuccess(0)`
- 异常失败：记录日志并返回 `createFailure(...)`，或抛 `RelationNotFoundError`

```arkts
import { Repository } from 'ocorm'

const repo = new Repository('Post')

try {
  const result = await repo.attach(1, 999, 'not_exists_relation')
  console.info(result.success)
} catch (error) {
  console.error('关系不存在会直接抛错:', error)
}
```

级联路径失败时，外层 `save/remove` 会把失败继续向上抛或包装，不会悄悄吞掉。

## 7. 实战规则
- 多对多关系写入优先 `attach/detach/sync`，不要手写 join table SQL。
- 重复 `attach` 不是异常；如果业务要强校验唯一新增，请自己检查返回值。
- 事务里要意识到关系写入优先使用 SAVEPOINT，而不是开启真正嵌套事务。
- 级联只会覆盖元数据允许的方向，不要把未配置 cascade 的关系当成自动联动。

## 8. 参考源码

## 9. 变更记录
- 2026-03-27：补全关系写入、级联规则、SAVEPOINT 与失败语义说明


