# ViewModel 映射

本章节介绍 OCORM 的 ViewModel 映射功能，实现 EntityData 与 UI ViewModel 之间的双向转换。

## 概述

ViewModelMapper 提供 EntityData 与 TypeScript/ArkTS 对象之间的转换能力，便于在 UI 层使用。

## 基本用法

### EntityData → ViewModel

```typescript
import { ViewModelMapper } from 'ocorm'

// 定义 ViewModel 类
class UserListItem {
  id: number = 0
  displayName: string = ''
  email: string = ''
  age: number = 0
}

// 转换单个对象
const userItem = ViewModelMapper.toViewModel<UserListItem>(
  entityData,
  () => new UserListItem(),
  (data, vm) => {
    vm.id = data.getPropertyValue('id') as number
    vm.displayName = data.getPropertyValue('name') as string
    vm.email = data.getPropertyValue('email') as string
    vm.age = data.getPropertyValue('age') as number
  }
)

// 转换数组
const userItems = ViewModelMapper.toViewModelArray<UserListItem>(
  entityDataArray,
  () => new UserListItem(),
  (data, vm) => {
    vm.id = data.getPropertyValue('id') as number
    vm.displayName = data.getPropertyValue('name') as string
    vm.email = data.getPropertyValue('email') as string
  }
)
```

### ViewModel → EntityData

```typescript
import { ViewModelMapper, EntityData } from 'ocorm'

// ViewModel → EntityData
const entityData = ViewModelMapper.toEntityData<UserListItem>(
  viewModel,
  'User',
  ['id', 'name', 'email'],  // 要映射的属性列表
  (vm, propName) => {
    if (propName === 'id') return vm.id
    if (propName === 'name') return vm.displayName  // 字段名转换
    if (propName === 'email') return vm.email
    return null
  }
)
```

## 在 UI 中使用

### 列表页面

```typescript
// ViewModel
class UserItemVM {
  id: number = 0
  name: string = ''
  avatar: string = ''
  role: string = ''
}

// Service 层
async function getUserList(): Promise<UserItemVM[]> {
  const repo = new Repository('User')
  const users = await repo.findAll()
  
  return ViewModelMapper.toViewModelArray<UserItemVM>(
    users,
    () => new UserItemVM(),
    (data, vm) => {
      vm.id = data.getPropertyValue('id') as number
      vm.name = data.getPropertyValue('name') as string
      vm.avatar = data.getPropertyValue('avatar') as string
      vm.role = data.getPropertyValue('role') as string
    }
  )
}

// UI 层
@Entry
@Component
struct UserListPage {
  @State userList: UserItemVM[] = []
  
  aboutToAppear() {
    getUserList().then(list => {
      this.userList = list
    })
  }
  
  build() {
    Column() {
      List() {
        ForEach(this.userList, (user: UserItemVM) => {
          ListItem() {
            Row() {
              Image(user.avatar)
                .width(40)
                .height(40)
              Text(user.name)
                .margin({ left: 10 })
            }
          }
        })
      }
    }
  }
}
```

### 详情页面

```typescript
// ViewModel
class UserDetailVM {
  id: number = 0
  name: string = ''
  email: string = ''
  phone: string = ''
  createdAt: string = ''
}

// Service 层
async function getUserDetail(id: number): Promise<UserDetailVM | null> {
  const repo = new Repository('User')
  const user = await repo.findById(id)
  
  if (!user) return null
  
  return ViewModelMapper.toViewModel<UserDetailVM>(
    user,
    () => new UserDetailVM(),
    (data, vm) => {
      vm.id = data.getPropertyValue('id') as number
      vm.name = data.getPropertyValue('name') as string
      vm.email = data.getPropertyValue('email') as string
      vm.phone = data.getPropertyValue('phone') as string
      vm.createdAt = new Date(data.getPropertyValue('createdAt') as number)
        .toLocaleString()
    }
  )
}

// UI 层
@Entry
@Component
struct UserDetailPage {
  @State user: UserDetailVM | null = null
  private userId: number = 1
  
  aboutToAppear() {
    getUserDetail(this.userId).then(detail => {
      this.user = detail
    })
  }
  
  build() {
    if (this.user) {
      Column() {
        Text(`姓名: ${this.user.name}`)
        Text(`邮箱: ${this.user.email}`)
        Text(`手机: ${this.user.phone}`)
        Text(`创建时间: ${this.user.createdAt}`)
      }
    }
  }
}
```

## 表单处理

### 表单 → EntityData

```typescript
// 表单数据
class UserFormVM {
  name: string = ''
  email: string = ''
  age: number = 18
}

// 转换为 EntityData 保存
async function saveUser(form: UserFormVM, userId?: number): Promise<void> {
  const repo = new Repository('User')
  
  let entityData: EntityData
  
  if (userId) {
    // 更新
    const existing = await repo.findById(userId)
    if (existing) {
      entityData = existing
    } else {
      throw new Error('用户不存在')
    }
  } else {
    // 新建
    entityData = EntityData.from('User', {
      createdAt: Date.now()
    })
  }
  
  // 映射表单数据到 EntityData
  ViewModelMapper.toEntityData<UserFormVM>(
    form,
    'User',
    ['name', 'email', 'age'],
    (vm, propName) => {
      if (propName === 'name') return vm.name
      if (propName === 'email') return vm.email
      if (propName === 'age') return vm.age
      return null
    },
    entityData  // 可选：目标 EntityData
  )
  
  await repo.save(entityData)
}
```

## 复杂映射场景

### 字段重命名

```typescript
class UserVM {
  userId: number = 0
  userName: string = ''
  userEmail: string = ''
}

const userVM = ViewModelMapper.toViewModel<UserVM>(
  entityData,
  () => new UserVM(),
  (data, vm) => {
    // 数据库字段名 → ViewModel 字段名
    vm.userId = data.getPropertyValue('id') as number
    vm.userName = data.getPropertyValue('name') as string
    vm.userEmail = data.getPropertyValue('email') as string
  }
)
```

### 计算字段

```typescript
class UserSummaryVM {
  id: number = 0
  fullName: string = ''
  age: number = 0
  isAdult: boolean = false  // 计算字段
  birthYear: number = 0     // 计算字段
}

const userVM = ViewModelMapper.toViewModel<UserSummaryVM>(
  entityData,
  () => new UserSummaryVM(),
  (data, vm) => {
    vm.id = data.getPropertyValue('id') as number
    vm.fullName = data.getPropertyValue('name') as string
    vm.age = data.getPropertyValue('age') as number
    vm.isAdult = vm.age >= 18  // 计算
    vm.birthYear = new Date().getFullYear() - vm.age  // 计算
  }
)
```

### 关联数据映射

```typescript
class OrderWithUserVM {
  orderId: number = 0
  amount: number = 0
  userName: string = ''
  userEmail: string = []
}

async function getOrderWithUser(orderId: number): Promise<OrderWithUserVM | null> {
  const orderRepo = new Repository('Order')
  
  const orders = await orderRepo.createQueryBuilder()
    .where('id', ConditionOperator.EQUAL, orderId)
    .with('user')  // 加载关联用户
    .getMany()
  
  if (orders.length === 0) return null
  
  const order = orders[0]
  const user = order.getRelatedData('user') as EntityData
  
  return ViewModelMapper.toViewModel<OrderWithUserVM>(
    order,
    () => new OrderWithUserVM(),
    (data, vm) => {
      vm.orderId = data.getPropertyValue('id') as number
      vm.amount = data.getPropertyValue('amount') as number
      
      // 映射关联数据
      if (user) {
        vm.userName = user.getPropertyValue('name') as string
        vm.userEmail = user.getPropertyValue('email') as string
      }
    }
  )
}
```

## 封装映射器

```typescript
// mappers/UserMapper.ts
import { ViewModelMapper, EntityData } from 'ocorm'

// 各种 ViewModel
export class UserListItem {
  id: number = 0
  name: string = ''
  email: string = ''
  status: number = 0
}

export class UserDetail {
  id: number = 0
  name: string = ''
  email: string = ''
  phone: string = ''
  age: number = 0
  createdAt: string = ''
}

export class UserForm {
  name: string = ''
  email: string = ''
  phone: string = ''
  age: number = 18
}

// 映射器类
export class UserMapper {
  // EntityData → UserListItem
  static toListItem(data: EntityData): UserListItem {
    return ViewModelMapper.toViewModel<UserListItem>(
      data,
      () => new UserListItem(),
      (data, vm) => {
        vm.id = data.getPropertyValue('id') as number
        vm.name = data.getPropertyValue('name') as string
        vm.email = data.getPropertyValue('email') as string
        vm.status = data.getPropertyValue('status') as number
      }
    )
  }
  
  // EntityData[] → UserListItem[]
  static toListItems(dataArray: EntityData[]): UserListItem[] {
    return ViewModelMapper.toViewModelArray<UserListItem>(
      dataArray,
      () => new UserListItem(),
      (data, vm) => {
        vm.id = data.getPropertyValue('id') as number
        vm.name = data.getPropertyValue('name') as string
        vm.email = data.getPropertyValue('email') as string
        vm.status = data.getPropertyValue('status') as number
      }
    )
  }
  
  // EntityData → UserDetail
  static toDetail(data: EntityData): UserDetail {
    return ViewModelMapper.toViewModel<UserDetail>(
      data,
      () => new UserDetail(),
      (data, vm) => {
        vm.id = data.getPropertyValue('id') as number
        vm.name = data.getPropertyValue('name') as string
        vm.email = data.getPropertyValue('email') as string
        vm.phone = data.getPropertyValue('phone') as string
        vm.age = data.getPropertyValue('age') as number
        vm.createdAt = new Date(data.getPropertyValue('createdAt') as number)
          .toLocaleString()
      }
    )
  }
  
  // UserForm → EntityData
  static toEntityData(form: UserForm, existing?: EntityData): EntityData {
    const data = existing || EntityData.from('User', {
      createdAt: Date.now()
    })
    
    ViewModelMapper.toEntityData<UserForm>(
      form,
      'User',
      ['name', 'email', 'phone', 'age'],
      (vm, propName) => {
        if (propName === 'name') return vm.name
        if (propName === 'email') return vm.email
        if (propName === 'phone') return vm.phone
        if (propName === 'age') return vm.age
        return null
      },
      data
    )
    
    data.setPropertyValue('updatedAt', Date.now())
    return data
  }
}
```

## 使用封装映射器

```typescript
// Service 层
import { UserMapper } from '../mappers/UserMapper'

async function getUserList(): Promise<UserListItem[]> {
  const repo = new Repository('User')
  const users = await repo.findAll()
  
  // 使用映射器
  return UserMapper.toListItems(users)
}

async function getUserDetail(id: number): Promise<UserDetail | null> {
  const repo = new Repository('User')
  const user = await repo.findById(id)
  
  if (!user) return null
  
  return UserMapper.toDetail(user)
}

async function saveUser(form: UserForm, id?: number): Promise<void> {
  const repo = new Repository('User')
  const data = UserMapper.toEntityData(form, id ? await repo.findById(id) : undefined)
  await repo.save(data)
}

// UI 层
@Entry
@Component
struct UserPage {
  @State users: UserListItem[] = []
  
  aboutToAppear() {
    getUserList().then(list => {
      this.users = list
    })
  }
  
  build() {
    // 使用 UserListItem
    List() {
      ForEach(this.users, (user: UserListItem) => {
        ListItem() {
          Text(user.name)
        }
      })
    }
  }
}
```

## 下一步

- [完整示例](16-完整示例.md) - 查看完整的业务场景示例
- [项目结构推荐](15-项目结构推荐.md) - 组织映射器代码




