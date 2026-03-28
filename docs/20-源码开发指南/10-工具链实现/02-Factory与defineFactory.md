# 02-Factory与defineFactory

> 状态：已完成
> 适用版本：ocorm 3.x（当前仓库 3.0.2）
> 最后更新：2026-03-27

## 1. 功能概述
`defineFactory(entityName, builder)` 返回 `EntityFactory`，用于构造和持久化测试/初始化数据。

核心行为来自 `tools/Factory.ets`：
- `make/makeMany` 只构建 `EntityData`，不落库。
- `create/createMany` 通过 `Repository.save` 落库，失败会抛错。
- 仅保留实体元数据中声明过的字段（未知字段会被过滤）。

## 2. 最小可运行示例
```ets
import { defineEntity } from '../../src/main/ets/core/EntitySchema'
import { ColumnType } from '../../src/main/ets/types/ColumnType'
import { defineFactory } from '../../src/main/ets/tools/Factory'

defineEntity('User', {
  columns: [
    { property: 'id', type: ColumnType.INTEGER, primaryKey: true },
    { property: 'name', type: ColumnType.TEXT },
    { property: 'email', type: ColumnType.TEXT }
  ]
})

const userFactory = defineFactory('User', (faker, index) => ({
  id: index + 1,
  name: faker.name(),
  email: faker.email('example.com')
}))

const draft = await userFactory.make({ name: 'override-name' })
const persisted = await userFactory.create()
console.info(`${draft.getPropertyValue('name')} / ${persisted.getPropertyValue('email')}`)
```

## 3. 误用示例
```ets
import { defineFactory } from '../../src/main/ets/tools/Factory'

// 误用：实体未注册会在构造阶段直接抛错（MetadataStorage.getEntityMetadata 返回 null）
const factory = defineFactory('NotRegisteredEntity', () => ({
  name: 'x'
}))
```

```ets
import { defineEntity } from '../../src/main/ets/core/EntitySchema'
import { ColumnType } from '../../src/main/ets/types/ColumnType'
import { defineFactory } from '../../src/main/ets/tools/Factory'

defineEntity('User', {
  columns: [
    { property: 'id', type: ColumnType.INTEGER, primaryKey: true },
    { property: 'name', type: ColumnType.TEXT }
  ]
})

const factory = defineFactory('User', () => ({
  id: 1,
  name: 'alice',
  age: 30 // 误用：未在元数据中声明，toInput 时会被静默过滤
}))

const entity = await factory.make()
console.info(entity.hasProperty('age')) // false
```

## 4. 批量构建与覆盖
```ets
import { defineFactory } from '../../src/main/ets/tools/Factory'

const userFactory = defineFactory('User', (faker, index) => ({
  id: index + 1,
  name: faker.name(),
  email: faker.email()
}))

const users = await userFactory.makeMany(3, (index) => ({
  name: `user-${index}`
}))

const savedUsers = await userFactory.createMany(2, (index) => ({
  email: `ci_${index}@example.com`
}))
console.info(`${users.length}/${savedUsers.length}`)
```

## 5. 脚本化 / CI 用法（仓库现有测试）
当前仓库可直接对照的 Factory 工具链测试文件是 `src/test/Stage17Tools/Tools.test.ets`，其中包含字段过滤行为断言。

```ets
// src/test/Stage17Tools/Tools.test.ets
import { describe, beforeEach, it, expect } from '@ohos/hypium'
import { MetadataStorage } from '../../main/ets/core/MetadataStorage'
import { defineEntity } from '../../main/ets/core/EntitySchema'
import { ColumnType } from '../../main/ets/types/ColumnType'
import { defineFactory } from '../../main/ets/tools/Factory'

export default function toolsTest() {
  describe('toolsTest', () => {
    beforeEach(() => {
      MetadataStorage.resetInstance()
    })

    it('defineFactory should create EntityData with metadata properties', 0, async () => {
      defineEntity('User', {
        columns: [
          { property: 'id', type: ColumnType.INTEGER, primaryKey: true },
          { property: 'name', type: ColumnType.TEXT }
        ]
      })
      const factory = defineFactory('User', () => ({ id: 1, name: 'n', age: 99 }))
      const data = await factory.make()
      expect(data.hasProperty('name')).assertEqual(true)
      expect(data.hasProperty('age')).assertEqual(false)
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
