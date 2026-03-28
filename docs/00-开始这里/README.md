# 00-开始这里

面向“只安装 `ocorm` 包、不看源码”的库使用者。

## 前置条件
- 已有可编译的 HarmonyOS/OpenHarmony ArkTS 工程
- 本机可执行 `ohpm`
- 能获取应用 `Context`（例如 UIAbility 的 `this.context`）

## 30 秒自检代码
```ts
import { Context } from '@kit.AbilityKit'
import { ColumnType, DatabaseConfig, EntityData, EntityDataInput, OCORMInit, Repository, defineEntity } from 'ocorm'

let bootstrapped = false

export async function smokeStartHere(context: Context): Promise<void> {
  if (!bootstrapped) {
    defineEntity('StartHereUser', {
      tableName: 'start_here_users',
      columns: [
        { property: 'id', name: 'id', primaryKey: true, autoIncrement: true },
        { property: 'name', name: 'name', type: ColumnType.TEXT }
      ]
    })

    await OCORMInit(context, {
      config: new DatabaseConfig('start-here.db'),
      autoCreateTables: true
    })
    bootstrapped = true
  }

  const repo = new Repository('StartHereUser')
  const input = EntityDataInput.create()
  input.set('name', 'starter')
  await repo.save(EntityData.from('StartHereUser', input))

  const rows = await repo.findAll()
  if (rows.length === 0) {
    throw new Error('ocorm 最小闭环未通过')
  }
}
```

## 验证步骤
1. 在应用启动或测试入口执行 `await smokeStartHere(this.context)`。
2. 看到无异常返回，即表示“安装 -> 初始化 -> 建模 -> 写入 -> 查询”闭环可用。
3. 若报错，优先跳转 [05-能力边界与不适用场景](./05-能力边界与不适用场景.md) 与 `docs/05-升级与排障/04-高频报错对照表.md`。

## 推荐阅读顺序
1. [01-我该看哪套文档](./01-我该看哪套文档.md)
2. [02-安装与导入约定](./02-安装与导入约定.md)
3. [03-10分钟最小闭环](./03-10分钟最小闭环.md)
4. [04-版本与运行环境](./04-版本与运行环境.md)
5. [05-能力边界与不适用场景](./05-能力边界与不适用场景.md)
