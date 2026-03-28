# ocorm 示例说明

本目录面向库使用者，示例只依赖 `ocorm` 公共导出 API。

## 推荐阅读顺序

1. `entity/UserEntity.ets`
2. `database/DatabaseInit.ets`
3. `repository/UserRepository.ets`
4. `UsageExample.ets`
5. `pages/UsageExamplePage.ets`

## 最小示例

```ts
import { ColumnType, DatabaseConfig, EntityData, EntityDataInput, OCORMInit, QueryExecutor, Repository, defineEntity } from 'ocorm'

defineEntity('User', {
  tableName: 'users',
  columns: [
    { property: 'id', primaryKey: true, autoIncrement: true },
    { property: 'userName', name: 'user_name', type: ColumnType.TEXT }
  ]
})

await OCORMInit(context, {
  config: new DatabaseConfig('example.db'),
  autoCreateTables: true
})

const repo = new Repository('User')
const input = EntityDataInput.create()
input.set('userName', 'demo-user')
await repo.save(EntityData.from('User', input))

const qb = repo.createQueryBuilder()
const rows = await new QueryExecutor(qb).get()
console.info(rows.length)
```

## 配套文档

- [开始这里](../docs/00-开始这里/README.md)
- [快速开始](../docs/01-快速开始/01-项目接入与初始化.md)
- [API参考](../docs/04-API参考/README.md)
