# ViewModel 映射

OCORM 提供 `ViewModelMapper` 用于 `EntityData` 与自定义 ViewModel 之间的双向转换，由于 ArkTS 不支持 Reflect API，采用回调函数和显式属性映射方式实现类型安全的转换。

---

## 基础概念

### 为什么需要 ViewModel 映射？

- **数据格式转换** - 将数据库字段转换为 UI 友好的格式
- **字段筛选** - 只暴露需要的字段给视图层
- **计算属性** - 添加派生属性（如全名、格式化日期）
- **类型安全** - 提供强类型的数据访问

### 核心类型

```typescript
// 属性映射器：从 EntityData 提取值并设置到 ViewModel
type PropertyMapper<T> = (entityData: EntityData, viewModel: T) => void

// 反向属性映射器：从 ViewModel 提取值
type ReversePropertyMapper<T> = (viewModel: T, propertyName: string) => ValueType

// ViewModel 工厂：创建 ViewModel 实例
type ViewModelFactory<T> = () => T
```

`ValueType` 在 OCORM 中定义为 `string | number | boolean | null`，因此反向映射（ViewModel → EntityData）需要返回基础类型：

- Date 请使用时间戳 `number`
- 复杂对象请使用 JSON 字符串 `string`

---

## 基础用法

### 定义 ViewModel

```typescript
// UserViewModel.ets
export class UserViewModel {
  id: number = 0
  name: string = ''
  email: string = ''
  displayName: string = ''  // 计算属性
  createdAtStr: string = '' // 格式化日期
}
```

### 简单转换（使用回调）

```typescript
import { ViewModelMapper, EntityData } from '@offlinecat/ocorm'
import { UserViewModel } from './UserViewModel'

// EntityData → ViewModel
const user = await userRepo.findById(1)
if (user !== null) {
  const viewModel = ViewModelMapper.toViewModel(
    user,
    () => new UserViewModel(),  // 工厂函数
    (entityData, vm) => {       // 映射回调
      vm.id = entityData.getPropertyValue('id') as number
      vm.name = entityData.getPropertyValue('name') as string
      vm.email = entityData.getPropertyValue('email') as string
      
      // 计算属性
      vm.displayName = `${vm.name} <${vm.email}>`
      
      // 格式化日期
      const timestamp = entityData.getPropertyValue('createdAt') as number
      vm.createdAtStr = new Date(timestamp).toLocaleDateString()
    }
  )
}
```

### 反向转换（ViewModel → EntityData）

```typescript
import { ViewModelMapper, EntityData } from '@offlinecat/ocorm'

const viewModel = new UserViewModel()
viewModel.name = '张三'
viewModel.email = 'zhangsan@example.com'

// ViewModel → EntityData
const entityData = ViewModelMapper.toEntityData(
  viewModel,
  'User',                          // 实体名称
  ['name', 'email'],               // 需要映射的属性名
  (vm, propertyName) => {          // 值获取回调
    switch (propertyName) {
      case 'name': return vm.name
      case 'email': return vm.email
      default: return null
    }
  }
)
```

---

## ViewModelMappingConfig - 映射配置类

使用配置类可以复用映射逻辑：

### 创建映射配置

```typescript
import { ViewModelMappingConfig, EntityData } from '@offlinecat/ocorm'
import { UserViewModel } from './UserViewModel'

const userMappingConfig = new ViewModelMappingConfig<UserViewModel>(
  'User',                    // 实体名称
  () => new UserViewModel()  // 工厂函数
)

// 添加属性映射器
userMappingConfig.addMapper((entityData, vm) => {
  vm.id = entityData.getPropertyValue('id') as number
  vm.name = entityData.getPropertyValue('name') as string
})

userMappingConfig.addMapper((entityData, vm) => {
  vm.email = entityData.getPropertyValue('email') as string
  vm.displayName = `${vm.name} <${vm.email}>`
})

// 设置反向映射器
userMappingConfig.setReverseMapper(
  (vm, propertyName) => {
    switch (propertyName) {
      case 'id': return vm.id
      case 'name': return vm.name
      case 'email': return vm.email
      default: return null
    }
  },
  ['id', 'name', 'email']  // 属性名列表
)
```

### 使用配置进行转换

```typescript
import { ViewModelMapper } from '@offlinecat/ocorm'

// EntityData → ViewModel（使用配置）
const viewModel = ViewModelMapper.toViewModelWithConfig(entityData, userMappingConfig)

// ViewModel → EntityData（使用配置）
const entityData = ViewModelMapper.toEntityDataWithConfig(viewModel, userMappingConfig)
```

注意：

- `toViewModelWithConfig` 在未配置 `factory` 时会抛出 `EntityMappingError`
- `toEntityDataWithConfig` 在未配置 `reverseMapper` 时会抛出 `EntityMappingError`

### 链式配置

```typescript
const config = new ViewModelMappingConfig<UserViewModel>('User', () => new UserViewModel())
  .addMapper((data, vm) => {
    vm.id = data.getPropertyValue('id') as number
    vm.name = data.getPropertyValue('name') as string
  })
  .addMapper((data, vm) => {
    vm.email = data.getPropertyValue('email') as string
  })
  .setReverseMapper(
    (vm, prop) => prop === 'name' ? vm.name : prop === 'email' ? vm.email : null,
    ['name', 'email']
  )
```

---

## 批量转换

### EntityData 数组 → ViewModel 数组

```typescript
import { ViewModelMapper, Repository } from '@offlinecat/ocorm'

const userRepo = new Repository('User')
const users = await userRepo.findAll()

// 批量转换
const viewModels = ViewModelMapper.toViewModelArray(
  users,
  () => new UserViewModel(),
  (entityData, vm) => {
    vm.id = entityData.getPropertyValue('id') as number
    vm.name = entityData.getPropertyValue('name') as string
    vm.email = entityData.getPropertyValue('email') as string
  }
)
```

### ViewModel 数组 → EntityData 数组

```typescript
const viewModels: Array<UserViewModel> = [vm1, vm2, vm3]

const entityDataArray = ViewModelMapper.toEntityDataArray(
  viewModels,
  'User',
  ['name', 'email'],
  (vm, prop) => {
    switch (prop) {
      case 'name': return vm.name
      case 'email': return vm.email
      default: return null
    }
  }
)
```

---

## 属性 Map 转换

### EntityData → 属性 Map

```typescript
import { ViewModelMapper } from '@offlinecat/ocorm'

const user = await userRepo.findById(1)
if (user !== null) {
  const propertyMap = ViewModelMapper.toPropertyMap(user)
  
  console.log(propertyMap.get('name'))   // '张三'
  console.log(propertyMap.get('email'))  // 'zhangsan@example.com'
}
```

### 属性 Map → EntityData

```typescript
const propertyMap = new Map<string, ValueType>()
propertyMap.set('name', '李四')
propertyMap.set('email', 'lisi@example.com')
propertyMap.set('age', 25)

const entityData = ViewModelMapper.fromPropertyMap('User', propertyMap)
```

---

## 复杂映射示例

### 嵌套对象映射

```typescript
// 定义嵌套 ViewModel
class UserDetailViewModel {
  id: number = 0
  name: string = ''
  profile: ProfileViewModel = new ProfileViewModel()
  posts: Array<PostViewModel> = []
}

class ProfileViewModel {
  bio: string = ''
  avatar: string = ''
}

class PostViewModel {
  id: number = 0
  title: string = ''
}

// 映射配置
const userDetailConfig = new ViewModelMappingConfig<UserDetailViewModel>(
  'User',
  () => new UserDetailViewModel()
)
  .addMapper((data, vm) => {
    vm.id = data.getPropertyValue('id') as number
    vm.name = data.getPropertyValue('name') as string
    
    // 映射 profile（从 JSON 字段）
    const profileJson = data.getPropertyValue('profile') as string
    if (profileJson) {
      const profile = JSON.parse(profileJson)
      vm.profile.bio = profile.bio || ''
      vm.profile.avatar = profile.avatar || ''
    }
    
    // 映射关联的 posts
    const postsData = data.getRelatedArray('posts')
    vm.posts = postsData.map(postData => {
      const postVm = new PostViewModel()
      postVm.id = postData.getPropertyValue('id') as number
      postVm.title = postData.getPropertyValue('title') as string
      return postVm
    })
  })
```

### 日期格式化映射

```typescript
class ArticleViewModel {
  id: number = 0
  title: string = ''
  publishedAt: string = ''      // 格式化后的日期字符串
  publishedAtDate: Date | null = null  // Date 对象
}

const articleConfig = new ViewModelMappingConfig<ArticleViewModel>(
  'Article',
  () => new ArticleViewModel()
)
  .addMapper((data, vm) => {
    vm.id = data.getPropertyValue('id') as number
    vm.title = data.getPropertyValue('title') as string
    
    const timestamp = data.getPropertyValue('publishedAt') as number | null
    if (timestamp !== null) {
      vm.publishedAtDate = new Date(timestamp)
      vm.publishedAt = vm.publishedAtDate.toLocaleDateString('zh-CN', {
        year: 'numeric',
        month: 'long',
        day: 'numeric'
      })
    }
  })
```

### 枚举值映射

```typescript
// 状态枚举
enum UserStatus {
  ACTIVE = 1,
  INACTIVE = 0,
  BANNED = -1
}

class UserStatusViewModel {
  id: number = 0
  status: UserStatus = UserStatus.INACTIVE
  statusText: string = ''
}

const statusConfig = new ViewModelMappingConfig<UserStatusViewModel>(
  'User',
  () => new UserStatusViewModel()
)
  .addMapper((data, vm) => {
    vm.id = data.getPropertyValue('id') as number
    vm.status = data.getPropertyValue('status') as UserStatus
    
    // 状态文本映射
    switch (vm.status) {
      case UserStatus.ACTIVE:
        vm.statusText = '正常'
        break
      case UserStatus.INACTIVE:
        vm.statusText = '未激活'
        break
      case UserStatus.BANNED:
        vm.statusText = '已封禁'
        break
    }
  })
```

---

## 在 UI 组件中使用

### 列表页面

```typescript
import { ViewModelMapper, Repository } from '@offlinecat/ocorm'

@Entry
@Component
struct UserListPage {
  @State users: Array<UserViewModel> = []

  async aboutToAppear() {
    const repo = new Repository('User')
    const entityDataList = await repo.findAll()
    
    this.users = ViewModelMapper.toViewModelArray(
      entityDataList,
      () => new UserViewModel(),
      (data, vm) => {
        vm.id = data.getPropertyValue('id') as number
        vm.name = data.getPropertyValue('name') as string
        vm.email = data.getPropertyValue('email') as string
      }
    )
  }

  build() {
    List() {
      ForEach(this.users, (user: UserViewModel) => {
        ListItem() {
          Column() {
            Text(user.name).fontSize(16).fontWeight(FontWeight.Bold)
            Text(user.email).fontSize(14).fontColor('#666')
          }
          .alignItems(HorizontalAlign.Start)
          .padding(12)
        }
      })
    }
  }
}
```

### 表单页面

```typescript
@Entry
@Component
struct UserFormPage {
  @State formData: UserViewModel = new UserViewModel()

  build() {
    Column() {
      TextInput({ placeholder: '姓名', text: this.formData.name })
        .onChange((value: string) => {
          this.formData.name = value
        })
      
      TextInput({ placeholder: '邮箱', text: this.formData.email })
        .onChange((value: string) => {
          this.formData.email = value
        })
      
      Button('保存')
        .onClick(() => this.saveUser())
    }
    .padding(16)
  }

  async saveUser() {
    const entityData = ViewModelMapper.toEntityData(
      this.formData,
      'User',
      ['name', 'email'],
      (vm, prop) => {
        if (prop === 'name') return vm.name
        if (prop === 'email') return vm.email
        return null
      }
    )
    
    const repo = new Repository('User')
    await repo.save(entityData)
  }
}
```

---

## 最佳实践

1. **分离映射逻辑** - 将映射配置放在单独的文件中，便于复用和测试
2. **使用配置类** - 对于复杂的映射逻辑，使用 `ViewModelMappingConfig` 而非内联回调
3. **处理空值** - 映射时始终检查属性是否为 null
4. **批量转换** - 使用 `toViewModelArray` 进行批量转换，避免循环调用
5. **计算属性** - 在映射回调中处理计算属性，保持 ViewModel 简洁

```typescript
// mappings/UserMapping.ets - 推荐的文件组织方式
import { ViewModelMappingConfig } from '@offlinecat/ocorm'
import { UserViewModel } from '../viewmodels/UserViewModel'

export const userMappingConfig = new ViewModelMappingConfig<UserViewModel>(
  'User',
  () => new UserViewModel()
)
  .addMapper((data, vm) => {
    vm.id = data.getPropertyValue('id') as number ?? 0
    vm.name = data.getPropertyValue('name') as string ?? ''
    vm.email = data.getPropertyValue('email') as string ?? ''
  })
  .setReverseMapper(
    (vm, prop) => {
      switch (prop) {
        case 'id': return vm.id
        case 'name': return vm.name
        case 'email': return vm.email
        default: return null
      }
    },
    ['id', 'name', 'email']
  )
```

