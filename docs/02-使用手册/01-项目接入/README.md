# 01-项目接入

## 何时用
在应用第一次接入 `ocorm` 时。

## 怎么用
建议按 01 -> 02 -> 03 -> 04 顺序阅读，先跑通“纯库最小模板”，再做参数调优。

- [01-推荐目录结构](./01-推荐目录结构.md)
- [02-实体注册时机](./02-实体注册时机.md)
- [03-DatabaseConfig配置](./03-DatabaseConfig配置.md)
- [04-配置文件与权限](./04-配置文件与权限.md)

## 最小可运行模板（纯库接入，不依赖 entry）
```ts
import { Context } from '@kit.AbilityKit'
import { ColumnType, DatabaseConfig, OCORMInit, Repository, defineEntity } from 'ocorm'

let initialized: boolean = false

export async function initOrm(context: Context): Promise<void> {
  if (initialized) {
    return
  }

  defineEntity('User', {
    tableName: 'users',
    columns: [
      { property: 'id', primaryKey: true, autoIncrement: true },
      { property: 'name', type: ColumnType.TEXT, nullable: false },
      { property: 'age', type: ColumnType.INTEGER, nullable: true }
    ]
  })

  await OCORMInit(context, {
    config: new DatabaseConfig('app.db'),
    autoCreateTables: true
  })

  initialized = true
}

export function userRepository(): Repository {
  return new Repository('User')
}
```

## 失败示例与修复
失败示例（先用仓储，后初始化）：
```ts
const repo = new Repository('User') // EntityNotRegisteredError
```

修复：
1. 先执行 `defineEntity('User', ...)`
2. 再执行 `await OCORMInit(context, ...)`
3. 最后再创建 `new Repository('User')`
