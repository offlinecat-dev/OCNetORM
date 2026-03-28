# 03-Breaking-Changes

> 状态：已完成
> 适用范围：当前仓库可证明的 breaking changes
> 最后更新：2026-03-28

## 1. 文档边界
这里不写“想象中的历史变更”，只写当前仓库能直接证明、或能从 `CHANGELOG + 当前实现` 推导出的兼容性断点。

## 2. 当前可确认的 breaking changes
### 2.1 `rawQuery` 默认强制参数化
这是当前最明确、最硬的行为断点。`3.0.2` 的 `CHANGELOG` 与当前 `Repository.ets` 都能证明：无占位符或占位符数量不匹配的 `rawQuery` 会直接失败。

```arkts
// 旧写法：在当前仓库 3.0.2 下不再兼容
await repo.rawQuery('SELECT * FROM user')
```

```arkts
// 新写法：必须使用参数化
await repo.rawQuery('SELECT * FROM user WHERE id = ?', [1])
```

### 2.2 实体查询路径拒绝 `selectRaw/groupBy/having`
这条在 `3.0.1` 已经建立，并在当前仓库继续保持。如果业务还把实体查询和聚合语义混在一起，会直接出错。

```arkts
// 旧混用方式：当前仓库不接受
await new QueryExecutor(
  repo.createQueryBuilder()
    .selectRaw(['COUNT(*) AS total'])
).get()
```

```arkts
// 正确做法：走 getRaw 或 aggregate
await new QueryExecutor(
  repo.createQueryBuilder()
    .selectRaw(['COUNT(*) AS total'])
).getRaw()
```


```arkts

```

### 2.4 事务边界更严格
从 `3.0.0` 开始，仓储层对同 Repository 嵌套事务、跨 Repository 嵌套事务、未绑定事务上下文写入的拦截都已收紧。继续沿用“外层事务里随手再 new 一个 Repository 写入”的老习惯，会直接失败。

```arkts
import { EntityData, EntityDataInput, Repository } from 'ocorm'

function makeUser(id: number, name: string): EntityData {
  const input = EntityDataInput.create()
  input.set('id', id)
  input.set('name', name)
  return EntityData.from('User', input)
}

const repo = new Repository('User')

await repo.transaction(async (txRepo) => {
  await repo.save(makeUser(1, 'blocked'))
})
```

## 3. 高风险兼容点
下面这些不是“导入名消失”，但实际迁移风险同样高：
- 把 `saveAll` 当原子批处理
- 把 `transactionWithOptions(timeout)` 当成“底层会立刻取消”
- 把 `READ_UNCOMMITTED` / `SERIALIZABLE` 当成总是可用
- 直接依赖内部实现文件如 `QueryExecutor*Support`、`rawsql/*` 作为公开 API

```text
兼容性判断原则:
调用侧只要依赖了“旧宽松行为”，升级到当前仓库就要当 breaking change 处理
```

## 4. 误用示例
下面这些在迁移时都要清理掉：

```arkts
await repo.rawQuery('SELECT * FROM user')
await repo.rawExecute('DELETE FROM user WHERE id = 1')
```

```arkts
await repo.transaction(async (txRepo) => {
  await repo.removeById(1)
})
```

```arkts
const options = TransactionOptions.serializable()
```

## 5. 升级检查清单
- [ ] 所有 `rawQuery/rawQuerySafe/rawExecute` 调用已参数化
- [ ] 聚合/分组查询已从实体模式切到 `getRaw()/aggregate()`
- [ ] 事务回调里统一复用 `txRepo`
- [ ] 未直接依赖内部 support 模块或 `rawsql/*` 作为对外 API

```bash
```

## 6. 参考路径
- `OCORM/CHANGELOG.md`

## 7. 变更记录
- 2026-03-28：基于当前仓库可证明行为补全 breaking changes 清单
