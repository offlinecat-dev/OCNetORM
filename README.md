# ocorm

HarmonyOS / OpenHarmony 的 ArkTS SQLite ORM。

当前文档对应版本：`3.0.2`

## 安装

```bash
ohpm i ocorm
```

## 最小接入

```ts
import { ColumnType, DatabaseConfig, EntityData, EntityDataInput, OCORMInit, Repository, defineEntity } from 'ocorm'

defineEntity('User', {
  tableName: 'users',
  columns: [
    { property: 'id', name: 'id', primaryKey: true, autoIncrement: true },
    { property: 'userName', name: 'user_name', type: ColumnType.TEXT }
  ]
})

await OCORMInit(context, {
  config: new DatabaseConfig('app.db'),
  autoCreateTables: true
})

const repo = new Repository('User')
const input = EntityDataInput.create()
input.set('userName', 'neo')
await repo.save(EntityData.from('User', input))
```

## 文档入口

- [开始这里](./docs/00-开始这里/README.md)
- [快速开始](./docs/01-快速开始/01-项目接入与初始化.md)
- [使用手册](./docs/02-使用手册/README.md)
- [场景配方](./docs/03-场景配方/README.md)
- [API参考](./docs/04-API参考/README.md)
- [升级与排障](./docs/05-升级与排障/README.md)

维护者入口：
- [源码开发指南](./docs/20-源码开发指南/README.md)
- [治理与归档](./docs/30-治理与归档/README.md)

## 版本与变更

- [CHANGELOG](./CHANGELOG.md)
- [历史文档（迁移前）](./docs/开发者文档/README.md)
