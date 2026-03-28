# 01-SeederManager

> 状态：已完成
> 适用版本：ocorm 3.x（当前仓库 3.0.2）
> 最后更新：2026-03-27

## 1. 功能概述
`SeederManager.run(seeders)` 按顺序执行种子任务，每个任务都会拿到 `new Repository(entityName)`，最终返回 `SeederExecutionResult`。

核心行为来自 `tools/SeederManager.ets`：
- `entityName` 优先使用 seeder 实例上的 `entityName` 字段。
- 若未显式设置，按类名推断：`UserSeeder` -> `User`。
- 单个 Seeder 失败不会中断后续 Seeder，结果在 `items` 中逐条记录。

## 2. 最小可运行示例
```ets
import { ColumnType, EntityData, EntityDataInput, Repository, Seeder, SeederManager, defineEntity } from 'ocorm'

function makeUser(id: number, name: string): EntityData {
  const input = EntityDataInput.create()
  input.set('id', id)
  input.set('name', name)
  return EntityData.from('User', input)
}

class UserSeeder implements Seeder {
  async run(repo: Repository): Promise<void> {
    await repo.save(makeUser(1, 'alice'))
  }
}

defineEntity('User', {
  columns: [
    { property: 'id', type: ColumnType.INTEGER, primaryKey: true },
    { property: 'name', type: ColumnType.TEXT }
  ]
})

const result = await SeederManager.run([new UserSeeder()])
console.info(`success=${result.success}, successCount=${result.successCount}`)
```

## 3. 误用示例
```ets
import { EntityData, EntityDataInput, Repository, Seeder, SeederManager } from 'ocorm'

function makeUserIdOnly(id: number): EntityData {
  const input = EntityDataInput.create()
  input.set('id', id)
  return EntityData.from('User', input)
}

// 误用：对象字面量没有 entityName，类名推断会落到 Object
const badSeeder: Seeder = {
  async run(repo: Repository): Promise<void> {
    await repo.save(makeUserIdOnly(1))
  }
}

const result = await SeederManager.run([badSeeder])
// 常见表现：result.failureCount === 1，items[0].entityName === 'Object'
console.info(JSON.stringify(result.items))
```

```ets
import { EntityData, EntityDataInput, Repository, Seeder, SeederManager } from 'ocorm'

function makeUserIdOnly(id: number): EntityData {
  const input = EntityDataInput.create()
  input.set('id', id)
  return EntityData.from('User', input)
}

class AccountSeeder implements Seeder {
  // 误用：实体名和元数据注册名不一致
  entityName: string = 'UserAccountTypo'
  async run(repo: Repository): Promise<void> {
    await repo.save(makeUserIdOnly(1))
  }
}

const result = await SeederManager.run([new AccountSeeder()])
console.info(`failureCount=${result.failureCount}`)
```

## 4. 脚本化 / CI 用法（仓库现有测试）
当前仓库可直接对照的 Seeder 工具链测试文件是 `src/test/Stage17Tools/Tools.test.ets`，其中包含 `SeederManager` 的最小断言。

```ets
// src/test/Stage17Tools/Tools.test.ets
import { describe, beforeEach, it, expect } from '@ohos/hypium'
import { ColumnType, MetadataStorage, Repository, Seeder, SeederManager, defineEntity } from 'ocorm'

class UserSeeder implements Seeder {
  static count: number = 0
  async run(_repo: Repository): Promise<void> {
    UserSeeder.count += 1
  }
}

export default function toolsTest() {
  describe('toolsTest', () => {
    beforeEach(() => {
      MetadataStorage.resetInstance()
      UserSeeder.count = 0
    })

    it('SeederManager should infer entity name from class name', 0, async () => {
      defineEntity('User', {
        columns: [
          { property: 'id', type: ColumnType.INTEGER, primaryKey: true },
          { property: 'name', type: ColumnType.TEXT }
        ]
      })
      const result = await SeederManager.run([new UserSeeder()])
      expect(result.success).assertEqual(true)
      expect(result.successCount).assertEqual(1)
      expect(UserSeeder.count).assertEqual(1)
    })
  })
}
```

```powershell
# CI 步骤（示例）
ohpm install
hvigor clean
hvigor test
```

## 5. 与结果对象交互
```ets
import { SeederExecutionResult } from 'ocorm'

function assertAllSeedersOk(result: SeederExecutionResult): void {
  if (!result.success) {
    for (let i = 0; i < result.items.length; i++) {
      const item = result.items[i]
      if (!item.success) {
        throw new Error(`${item.seederName} failed on ${item.entityName}: ${item.errorMessage}`)
      }
    }
  }
}
```
