# 05-ViewModelMapper双向映射

> 状态：完成
> 适用版本：ocorm 3.x（当前仓库实现）
> 最后更新：2026-03-27

## 1. 目标
本文说明 `ViewModelMapper` 在当前仓库中的真实职责：
- 在 `EntityData` 与 ViewModel 之间做显式双向转换。
- 支持配置式映射与回调式映射两种入口。
- 说明当前实现的异常语义、类型推断边界，以及常见误用。

## 2. 核心对象
`ViewModelMapper.ets` 暴露的公共契约只有这些：
- `PropertyMapper<T>`：`(entityData: EntityData, viewModel: T) => void`
- `ReversePropertyMapper<T>`：`(viewModel: T, propertyName: string) => ValueType`
- `ViewModelFactory<T>`：`() => T`
- `ViewModelMappingConfig<T>`：持有 `entityName`、`factory`、正向 mapper 列表、反向 mapper 与属性名清单
- `ViewModelMapper`：提供单个、批量、Map 中转三类转换方法

约束也很直接：
- 框架不使用 `Reflect` 自动推导字段。
- 所有字段映射都依赖调用方手写回调。
- 类型安全主要靠调用侧保证，不靠 `ViewModelMapper` 运行时校验。

## 3. 正确示例：配置式双向映射
配置式映射适合字段较多、正反向规则想集中管理的场景。

```ts
import { EntityData } from 'ocorm'
import { ViewModelMapper, ViewModelMappingConfig } from 'ocorm'

class UserCardVm {
  id: number = 0
  displayName: string = ''
  active: boolean = false
}

const config = new ViewModelMappingConfig<UserCardVm>('User', () => new UserCardVm())
  .addMapper((entityData, vm) => {
    vm.id = (entityData.getPropertyValue('id') as number) ?? 0
    vm.displayName = (entityData.getPropertyValue('name') as string) ?? ''
    vm.active = (entityData.getPropertyValue('isActive') as boolean) ?? false
  })
  .setReverseMapper((vm, propertyName) => {
    switch (propertyName) {
      case 'id':
        return vm.id
      case 'name':
        return vm.displayName
      case 'isActive':
        return vm.active
      default:
        return null
    }
  }, ['id', 'name', 'isActive'])

const entity = new EntityData('User')
entity.addProperty('id', 7, 'number')
entity.addProperty('name', 'Alice', 'string')
entity.addProperty('isActive', true, 'boolean')

const vm = ViewModelMapper.toViewModelWithConfig(entity, config)
const roundTrip = ViewModelMapper.toEntityDataWithConfig(vm, config)
```

配置式正向映射会按 `addMapper(...)` 的添加顺序依次执行，后执行的 mapper 可以覆盖前一个 mapper 写入的值。

## 4. 正确示例：回调式与批量转换
如果不需要集中配置，直接使用单个回调更简单。

```ts
import { EntityData } from 'ocorm'
import { ViewModelMapper } from 'ocorm'

class UserListVm {
  id: number = 0
  title: string = ''
}

const entity = new EntityData('User')
entity.addProperty('id', 11, 'number')
entity.addProperty('name', 'Neo', 'string')

const vm = ViewModelMapper.toViewModel(
  entity,
  () => new UserListVm(),
  (entityData, viewModel) => {
    viewModel.id = (entityData.getPropertyValue('id') as number) ?? 0
    viewModel.title = (entityData.getPropertyValue('name') as string) ?? ''
  }
)

const back = ViewModelMapper.toEntityData(vm, 'User', ['id', 'name'], (viewModel, propertyName) => {
  return propertyName === 'id' ? viewModel.id : viewModel.title
})
```

批量转换只是对单个转换的简单循环包装，不会增加额外规则。

```ts
import { EntityData } from 'ocorm'
import { ViewModelMapper } from 'ocorm'

const entityA = new EntityData('User')
entityA.addProperty('id', 1, 'number')
entityA.addProperty('name', 'A', 'string')

const entityB = new EntityData('User')
entityB.addProperty('id', 2, 'number')
entityB.addProperty('name', 'B', 'string')

const list = ViewModelMapper.toViewModelArray([entityA, entityB], () => ({ id: 0, title: '' }), (entityData, vm) => {
  vm.id = (entityData.getPropertyValue('id') as number) ?? 0
  vm.title = (entityData.getPropertyValue('name') as string) ?? ''
})

const entities = ViewModelMapper.toEntityDataArray(list, 'User', ['id', 'name'], (vm, propertyName) => {
  return propertyName === 'id' ? vm.id : vm.title
})
```

## 5. `toPropertyMap()` 与 `fromPropertyMap()`
这两个方法适合做轻量中转，但不能替代完整映射配置。

```ts
import { EntityData } from 'ocorm'
import { ViewModelMapper } from 'ocorm'

const entity = new EntityData('User')
entity.addProperty('id', 1, 'number')
entity.addProperty('name', 'Alice', 'string')

const propertyMap = ViewModelMapper.toPropertyMap(entity)
const restored = ViewModelMapper.fromPropertyMap('User', propertyMap)
```

这里的真实语义要注意：
- `toPropertyMap(entityData)` 读取的是 `entityData.properties`，不是 `getPropertyNames()` 对应的 `propertyMap`。
- `fromPropertyMap(...)` 的类型推断只区分 `number`、`boolean`，其余都按 `'string'` 写入。

## 6. 误用示例
误用 1：以为 `toPropertyMap(...)` 会包含所有 `setPropertyValue(...)` 写入的数据。当前实现只遍历 `properties` 数组；如果某个键从未 `addProperty(...)`，它不会进入结果。

```ts
import { EntityData } from 'ocorm'
import { ViewModelMapper } from 'ocorm'

const entity = new EntityData('User')
entity.setPropertyValue('name', 'OnlyInPropertyMap')

const propertyMap = ViewModelMapper.toPropertyMap(entity)
const hasName = propertyMap.has('name')
// false：因为 name 没有出现在 entity.properties 中
```

误用 2：假设 `toEntityDataWithConfig(...)` 会根据实体元数据恢复 `Date`、`object` 等精确类型。当前实现虽然读取了 `MetadataStorage`，但没有真正用元数据覆盖 `propertyType`，仍然只做简单推断：
- `number -> 'number'`
- `boolean -> 'boolean'`
- 其他全部 -> `'string'`

```ts
import { ViewModelMapper, ViewModelMappingConfig } from 'ocorm'

class UserVm {
  createdAt: Date = new Date(1710000000000)
}

const config = new ViewModelMappingConfig<UserVm>('User', () => new UserVm())
  .setReverseMapper((vm, propertyName) => vm.createdAt, ['createdAt'])

const entity = ViewModelMapper.toEntityDataWithConfig(new UserVm(), config)
const prop = entity.getProperty('createdAt')
// prop?.propertyType 的真实值是 'string'，不是 'Date'
```

误用 3：把 `ViewModelMapper` 当成实体注册校验器。回调式 `toEntityData(...)`、`toEntityDataArray(...)`、`fromPropertyMap(...)` 都不会验证 `entityName` 是否已注册。

## 7. 转换失败与异常语义
`ViewModelMapper` 这一层只有少量显式异常，核心是 `EntityMappingError`。

```ts
import { EntityData } from 'ocorm'
import { ViewModelMapper, ViewModelMappingConfig } from 'ocorm'
import { EntityMappingError } from 'ocorm'

class UserVm {
  name: string = ''
}

const config = new ViewModelMappingConfig<UserVm>('User', () => new UserVm())

try {
  ViewModelMapper.toEntityDataWithConfig(new UserVm(), config)
} catch (e) {
  if (e instanceof EntityMappingError) {
    // e.message: 实体 "User" 映射失败: 反向属性映射器未配置
  }
}

config.factory = null

try {
  ViewModelMapper.toViewModelWithConfig(new EntityData('User'), config)
} catch (e) {
  if (e instanceof EntityMappingError) {
    // e.message: 实体 "User" 映射失败: ViewModel 工厂函数未配置
  }
}
```

还需要记住这些非异常语义：
- `toViewModelWithConfig(...)` 不检查是否存在任何 `addMapper(...)`；没有 mapper 时只会返回一个工厂创建出的空 ViewModel。
- `toEntityDataWithConfig(...)` 与 `toEntityData(...)` 不检查 `propertyNames` 是否为空；为空时会返回没有属性的 `EntityData`。
- `ReversePropertyMapper` 对未知字段返回什么，`ViewModelMapper` 就写什么；常见做法是返回 `null`。
- `toEntityDataWithConfig(...)` 即使 `entityName` 未注册也不会抛错，因为内部对 `MetadataStorage.getEntityMetadata(...)` 的结果允许为 `null`。
- `toPropertyMap(...)` / `fromPropertyMap(...)` 不会抛 `MappingError` 体系异常。

## 8. 验收清单
- 已覆盖配置式、回调式、批量转换三类真实入口。
- 已明确 `toPropertyMap(...)` 只读 `properties` 数组，不读 `propertyMap`。
- 已明确 `toEntityDataWithConfig(...)` 的类型推断非常有限，元数据当前没有真正参与覆盖。
- 已覆盖 `EntityMappingError` 的两个触发点与其余静默行为。

## 9. 变更记录
- 2026-03-27：补全 `ViewModelMapper` 双向映射、误用示例与异常语义。
