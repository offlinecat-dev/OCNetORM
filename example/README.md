# ocorm 示例说明

本目录保存 `ocorm` 模块随仓库维护的源码示例，重点是“最小可读的能力演示”，不是完整应用工程。

如果你要看可挂到页面里的运行示例，请同时看：

- [`../../entry/src/main/ets/example/README.md`](../../entry/src/main/ets/example/README.md)

## 1. 目录结构

```text
example/
├── database/
│   └── DatabaseInit.ets
├── entity/
│   └── UserEntity.ets
├── pages/
│   └── UsageExamplePage.ets
├── repository/
│   └── UserRepository.ets
├── UsageExample.ets
└── README.md
```

## 2. 各文件负责什么

| 文件 | 作用 |
| --- | --- |
| `entity/UserEntity.ets` | 演示实体定义与字段映射 |
| `database/DatabaseInit.ets` | 演示数据库初始化与 `OCORMInit` 使用 |
| `repository/UserRepository.ets` | 演示仓储层封装 |
| `UsageExample.ets` | 演示组合式用法与常见调用片段 |
| `pages/UsageExamplePage.ets` | 演示 ArkUI 页面如何接入示例逻辑 |

## 3. 推荐阅读顺序

1. `entity/UserEntity.ets`
2. `database/DatabaseInit.ets`
3. `repository/UserRepository.ets`
4. `UsageExample.ets`
5. `pages/UsageExamplePage.ets`

## 4. 最小示例

### 4.1 实体与初始化

```ts
import { ColumnType, DatabaseConfig, OCORMInit, defineEntity } from 'ocorm'

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
```

### 4.2 保存与查询

```ts
import { ConditionOperator, EntityData, EntityDataInput, QueryExecutor, Repository } from 'ocorm'

const repo = new Repository('User')
const input = EntityDataInput.create()
input.set('userName', 'demo-user')

await repo.save(EntityData.from('User', input))

const qb = repo.createQueryBuilder()
  .where('userName', ConditionOperator.EQUAL, 'demo-user')

const rows = await new QueryExecutor(qb).get()
console.info(rows.length)
```

## 5. 使用边界

- 这里的示例优先展示 API，不覆盖完整应用生命周期。
- 需要页面联调、Ability 生命周期接入时，请以 `entry/src/main/ets/example/` 为准。
- 需要系统性说明时，不要继续翻示例代码，直接进入开发者文档。

## 6. 配套文档

- [`../README.md`](../README.md)
- [`../docs/开发者文档/README.md`](../docs/开发者文档/README.md)
- [`../docs/开发者文档/18-API速查/README.md`](../docs/开发者文档/18-API速查/README.md)

## 7. 变更记录

- 2026-03-28：重写示例说明，按当前目录结构与 3.0.2 API 对齐。
