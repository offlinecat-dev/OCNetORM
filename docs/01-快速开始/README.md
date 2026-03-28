# 01-快速开始

目标：面向纯库用户，在 10 分钟内跑通 `安装 -> 初始化 -> 建模 -> 保存/查询 -> 事务 -> 关系分页`。

## 前置条件
- 已有 HarmonyOS 工程，且能在业务代码拿到 `Context`（例如 `this.context`）。
- 依赖安装命令统一使用：`ohpm i @offlinecat/ocorm`。
- 导入约定统一使用：`from 'ocorm'`。

## 完整代码
```ts
import { Context } from '@kit.AbilityKit'
import {
  ColumnType,
  ConditionOperator,
  DatabaseConfig,
  EntityData,
  EntityDataInput,
  LogLevel,
  OCORMInit,
  QueryExecutor,
  Repository,
  defineEntity
} from 'ocorm'

let inited = false

export async function quickStartSmoke(context: Context): Promise<void> {
  if (!inited) {
    defineEntity('QuickStartUser', {
      tableName: 'quick_start_users',
      columns: [
        { property: 'id', name: 'id', primaryKey: true, autoIncrement: true },
        { property: 'userName', name: 'user_name', type: ColumnType.TEXT, unique: true },
        { property: 'age', name: 'age', type: ColumnType.INTEGER, nullable: true }
      ]
    })

    await OCORMInit(context, {
      config: new DatabaseConfig('quick-start.db')
        .setQueryCache(true, 200, 60000)
        .setQueryTimeout(1500),
      autoCreateTables: true,
      enableLogger: true,
      logLevel: LogLevel.INFO
    })

    inited = true
  }

  const repo = new Repository('QuickStartUser')
  const input = EntityDataInput.create()
  input.set('userName', 'neo')
  input.set('age', 20)
  await repo.save(EntityData.from('QuickStartUser', input))

  const page = await new QueryExecutor(
    repo.createQueryBuilder()
      .where('age', ConditionOperator.GREATER_EQUAL, 18)
      .paginate(1, 10)
  ).getPaginated()

  if (page.total < 1) {
    throw new Error('快速开始闭环失败：未查询到刚写入的数据')
  }
}
```

## 验证步骤
1. 安装依赖：`ohpm i @offlinecat/ocorm`。
2. 在应用入口调用 `await quickStartSmoke(this.context)`。
3. 无异常且 `page.total >= 1` 说明最小闭环通过。

## 常见失败
- `EntityNotRegisteredError`：`new Repository(...)` 前没有先 `defineEntity(...)`。
- `DatabaseNotInitializedError` / `ExecutionError`：`OCORMInit(...)` 未执行或执行失败。
- `ValidationError`：写入数据不满足字段验证规则（例如唯一约束冲突）。

## 建议阅读顺序
1. [01-项目接入与初始化.md](./01-项目接入与初始化.md)
2. [02-定义第一个实体.md](./02-定义第一个实体.md)
3. [03-第一次保存与查询.md](./03-第一次保存与查询.md)
4. [04-第一次事务.md](./04-第一次事务.md)
5. [05-关系加载与分页.md](./05-关系加载与分页.md)

