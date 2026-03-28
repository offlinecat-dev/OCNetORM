# 01-EntityData与TypedEntityData

> 状态：完成
> 适用版本：ocorm 3.x（当前仓库实现）
> 最后更新：2026-03-27

## 1. 目标
本文定义 `EntityData`、`TypedEntityData<T>` 与 `EntityDataInput` 的使用边界，避免属性读写与类型获取不一致。

## 2. 核心对象
- `EntityData`：通用实体容器，支持属性、临时字段、关联数据、延迟关联加载。
- `TypedEntityData<T>`：面向调用侧的类型化访问包装，提供 `getString/getNumber/getBoolean` 等方法。
- `EntityDataInput`：给 `EntityData.from(entityName, input)` 的输入构造器。

## 3. 正确示例

```ts
import { EntityData } from 'ocorm'
import { EntityDataInput } from 'ocorm'

const input = EntityDataInput.create()
input.set('id', 1)
input.set('name', 'Alice')
input.set('isActive', true)

// 要求 User 已在 实体元数据注册表 注册
const user = EntityData.from('User', input)

const id = user.getPropertyValue('id')
const name = user.getPropertyValue('name')
const hasName = user.hasProperty('name')
```

```ts
import { EntityData } from 'ocorm'
import { TypedEntityData } from 'ocorm'

const entity = new EntityData('User')
entity.addProperty('id', 1001, 'number')
entity.addProperty('nickname', 'neo', 'string')

const typed = TypedEntityData.fromEntityData<{ id: number; nickname: string }>(entity)

const id = typed.getNumber('id')          // 1001
const nickname = typed.getString('nickname') // 'neo'
const names = typed.getPropertyNames()
```

## 4. 误用示例

```ts
import { TypedEntityData } from 'ocorm'

const typed = new TypedEntityData<{ score: number }>('User')
typed.setString('score', '99')

// 误用：score 实际是 string，getNumber 不会抛错，只会返回 null
const score = typed.getNumber('score') // null
```

```ts
import { EntityData } from 'ocorm'
import { TypedEntityData } from 'ocorm'

const entity = new EntityData('User')
// 误用：未先 addProperty，直接 setPropertyValue 只会写入 propertyMap
entity.setPropertyValue('age', 18)

// fromEntityData 复制来源是 entity.properties，age 不会被拷贝过去
const typed = TypedEntityData.fromEntityData<{ age: number }>(entity)
const age = typed.getNumber('age') // null
```

## 5. 转换失败/异常语义

```ts
import { EntityData } from 'ocorm'
import { EntityDataInput } from 'ocorm'
import { EntityMappingError } from 'ocorm'

const input = EntityDataInput.create()
input.set('id', 1)

try {
  // 未注册实体名会抛 EntityMappingError
  EntityData.from('NotRegisteredEntity', input)
} catch (e) {
  if (e instanceof EntityMappingError) {
    // e.message: 实体 "NotRegisteredEntity" 映射失败: 实体未注册
  }
}
```

- `EntityData.from(...)`：实体未注册时抛 `EntityMappingError`。
- `TypedEntityData.getNumber/getBoolean`：类型不匹配时返回 `null`，不抛异常。
- `EntityData.loadRelated(...)`：未设置 loader 且无已加载关系时返回 `null`，不抛异常。

## 6. 关联数据与延迟加载要点
- `setRelatedArray/propertyName` 与 `getRelatedArray` 配对使用。
- `setRelatedSingle/propertyName` 与 `getRelatedSingle` 配对使用。
- 延迟关系使用 `setLazyRelation` + `loadRelated/loadRelatedArray/loadRelatedSingle`。

## 7. 验收清单
- `EntityData.from` 仅导入元数据定义内字段，额外输入键会被忽略。
- `TypedEntityData.fromEntityData` 后，`getPropertyCount` 与来源 `properties` 数量一致。
- 未注册实体路径已覆盖 `EntityMappingError` 异常断言。


