# 04-HooksProcessor生命周期钩子

> 状态：完成
> 适用版本：ocorm 3.x（基于当前源码）
> 最后更新：2026-03-27

## 1. 目标
`HooksProcessor` 负责统一执行实体生命周期钩子，并且把同步/异步回调失败都包装成 `HookExecutionError`。
如果你要确认“某个 before/after 钩子什么时候触发”“全局钩子和实体钩子谁先执行”“为什么明明注册了钩子却没有命中”，应该直接看这层。
它只负责执行与异常包装，不负责声明实体元数据。

## 2. 背景与适用范围
适用于以下场景：
- 需要梳理 `beforeSave`、`afterInsert`、`afterLoad` 等生命周期节点
- 需要解释全局钩子与实体钩子的先后顺序
- 需要定位 `HookExecutionError` 的来源、所属阶段和清洗后的错误信息

不适用于以下问题：
- 字段规则注册与字段验证：看 `EntityValidator` 与 `ValidationDecorators`
- 实体元数据如何挂载 `EntityHooks`：由实体注册层负责，不在本文展开

## 3. 前置条件
- 已通过实体元数据为目标实体配置 `EntityHooks`，或者已经通过 `registerGlobalHook` 注册全局钩子
- 调用方能够提供实体名和实体数据对象
- 调用方必须 `await` `HooksProcessor` 的异步执行方法
- 如果要在测试间隔离状态，必须显式调用 `HooksProcessor.resetInstance()` 或 `clearGlobalHooks()`

## 4. 关键概念与约束
### 4.1 支持的真实钩子名
`HookName` 只包含以下 11 个生命周期节点：

```text
beforeSave
afterLoad
beforeDelete
beforeInsert
afterInsert
beforeUpdate
afterUpdate
afterDelete
afterSave
beforeRestore
afterRestore
```

### 4.2 `EntityHooks` 与全局钩子的角色分工
- `EntityHooks`：单实体级回调，类型为 `HookCallback = (data) => void | Promise<void>`
- 全局钩子：跨实体回调，类型为 `GlobalHookCallback = (entityName, data) => void | Promise<void>`
- `registerGlobalHook` 支持同一 `hookName` 注册多个回调，按注册顺序依次执行
- `clearGlobalHooks(hookName?)` 可以清空单个阶段，或者不传参数时清空全部阶段

### 4.3 before 与 after 的执行顺序
顺序是硬编码的，不要自行假设：
- `before*`：先执行全局钩子，再执行实体钩子
- 非 `before*`：先执行实体钩子，再执行全局钩子

```text
executeHook(entityName, data, hookName)
  -> 读取实体 hooks
  -> 判断 hookName 是否以 before 开头
  -> before*: global -> entity
  -> after*:  entity -> global
  -> 任一回调抛错: 包装为 HookExecutionError 并终止后续执行
```

### 4.4 需要特别记住的实现细节
- `executeCallback` 与 `executeGlobalCallback` 都会等待 `Promise` 完成
- `executeAfterLoadBatch` 是串行 `for` 循环，不是并发执行；中途一条失败会中断后续批次
- `registerGlobalHook` 内部会复制数组后追加，当前轮执行使用的是快照，不受中途新注册影响
- `hasBeforeSaveHook`、`hasAfterLoadHook`、`hasBeforeDeleteHook`、`hasAnyHook` 只检查实体级 `EntityHooks`，不检查全局钩子
- `resetInstance()` 会把单例替换成新实例，之前注册的所有全局钩子都会丢失
- `HooksProcessor` 只负责执行；像 `rawQuery/rawQuerySafe` 这种未显式调用它的路径，不会自动触发 `afterLoad`
- `afterRestore` 是否会被调用取决于上层恢复逻辑；当前 `Repository.restore(id)` 只有在 `affectedRows > 0` 时才会执行它

## 5. 关键流程/规则
### 5.1 正例：定义实体级钩子对象
```ts
import { EntityHooks } from 'ocorm'

const hooks = new EntityHooks(
  (data) => {
    console.info('beforeSave', data)
  },
  (data) => {
    console.info('afterLoad', data)
  },
  null,
  async (data) => {
    console.info('beforeInsert', data)
  },
  async (data) => {
    console.info('afterInsert', data)
  }
)
```

### 5.2 正例：注册并执行全局钩子
```ts
import { HooksProcessor } from 'ocorm'

const hooksProcessor = HooksProcessor.getInstance()
const entityData = /* 已构造的实体数据对象 */

hooksProcessor.registerGlobalHook('beforeSave', async (entityName, data) => {
  console.info('global beforeSave', entityName, data)
})

hooksProcessor.registerGlobalHook('afterSave', (entityName) => {
  console.info('global afterSave', entityName)
})

await hooksProcessor.executeBeforeSave('User', entityData)
// 持久化动作
await hooksProcessor.executeAfterSave('User', entityData)
```

### 5.3 正例：批量执行 `afterLoad`
```ts
import { HooksProcessor } from 'ocorm'

const hooksProcessor = HooksProcessor.getInstance()
const rows = [
  /* 多个实体数据对象 */
]

await hooksProcessor.executeAfterLoadBatch('User', rows)
```

### 5.4 误用示例：不 `await` 钩子执行
```ts
import { HooksProcessor } from 'ocorm'

const hooksProcessor = HooksProcessor.getInstance()
const entityData = /* 已构造的实体数据对象 */

// 误用：未等待 beforeSave 完成，就继续执行持久化
hooksProcessor.executeBeforeSave('User', entityData)
// saveToDatabase(entityData)
```

这会让异步钩子与持久化并发，顺序保证直接失效；如果钩子抛错，异常也不会在当前调用栈里被正确处理。

### 5.5 误用示例：拿 `hasAnyHook` 判断“不会触发任何钩子”
```ts
import { HooksProcessor } from 'ocorm'

const hooksProcessor = HooksProcessor.getInstance()

if (!hooksProcessor.hasAnyHook('User')) {
  console.info('误判：这里并不代表 beforeSave/afterSave 一定不会执行')
}
```

原因很直接：`hasAnyHook` 只看实体级 `EntityHooks`，如果你注册了全局钩子，`executeBeforeSave` / `executeAfterSave` 仍然会执行。

## 6. 示例
### 6.1 生命周期顺序示意
```ts
import { HooksProcessor } from 'ocorm'

const hooksProcessor = HooksProcessor.getInstance()
const entityData = /* 已构造的实体数据对象 */

await hooksProcessor.executeBeforeInsert('User', entityData)
// insert
await hooksProcessor.executeAfterInsert('User', entityData)
await hooksProcessor.executeAfterSave('User', entityData)
```

如果同时存在实体级与全局级回调，则实际顺序为：
1. `beforeInsert`: 全局 -> 实体
2. `afterInsert`: 实体 -> 全局
3. `afterSave`: 实体 -> 全局

### 6.2 测试隔离正例
```ts
import { HooksProcessor } from 'ocorm'

HooksProcessor.resetInstance()
const hooksProcessor = HooksProcessor.getInstance()

hooksProcessor.registerGlobalHook('beforeDelete', (entityName) => {
  console.info('beforeDelete', entityName)
})

hooksProcessor.clearGlobalHooks('beforeDelete')
```

## 7. 验收与测试
最小验收应覆盖以下断言：
- `before*` 阶段执行顺序是“全局先、实体后”
- `after*` 阶段执行顺序是“实体先、全局后”
- 同步回调与返回 `Promise` 的回调都能被正确等待
- 任一钩子抛错时，后续同阶段钩子不再继续执行
- `executeAfterLoadBatch` 遇到第一条失败时会中断批处理
- `hasAnyHook` 对全局钩子返回值不敏感

```ts
import { HookExecutionError } from 'ocorm'
import { HooksProcessor } from 'ocorm'

const hooksProcessor = HooksProcessor.getInstance()
const entityData = /* 已构造的实体数据对象 */

hooksProcessor.registerGlobalHook('beforeUpdate', () => {
  throw new Error('version mismatch')
})

try {
  await hooksProcessor.executeBeforeUpdate('User', entityData)
} catch (error) {
  if (error instanceof HookExecutionError) {
    console.error(error.name, error.message)
  }
}
```

## 8. 常见问题
### 8.1 为什么一个阶段里后面的钩子没有执行？
因为 `HooksProcessor` 遇到异常会立刻抛出 `HookExecutionError`，当前阶段后续回调不会继续跑。这是刻意设计，不是漏执行。

### 8.2 为什么捕获到的是 `HookExecutionError`，不是原始错误？
`executeCallback` 和 `executeGlobalCallback` 会统一包装异常。这样上层只需要处理一个错误类型，同时还能从 `operation` 看出是哪个生命周期阶段失败。

### 8.3 如何定位具体失败阶段与实体？
看 `HookExecutionError` 的三个关键面向：
- `error.name`：固定为 `HookExecutionError`
- `error.message`：包含实体名、钩子名和清洗后的错误信息
- 错误上下文：`entityName` 在上下文里，`operation` 等于 `hookName`，`details` 是清洗后的原始错误

### 8.4 报错与定位方式
```ts
import { HookExecutionError } from 'ocorm'
import { HooksProcessor } from 'ocorm'

const hooksProcessor = HooksProcessor.getInstance()
const entityData = /* 已构造的实体数据对象 */

hooksProcessor.registerGlobalHook('afterRestore', () => {
  throw 'restore failed'
})

try {
  await hooksProcessor.executeAfterRestore('ArchiveUser', entityData)
} catch (error) {
  if (error instanceof HookExecutionError) {
    console.error('阶段:', error.message)
    // 实际定位时优先读取 hookName 对应的 operation，再回查该阶段注册的全局/实体回调
  }
}
```

建议定位顺序：
1. 先看失败的是哪个执行入口，例如 `executeBeforeUpdate` 或 `executeAfterRestore`。
2. 再确认该阶段的顺序是“全局先”还是“实体先”。
3. 如果是批量加载场景，检查是否由 `executeAfterLoadBatch` 中某一条数据提前中断。
4. 最后核对是否在测试中调用过 `resetInstance()` 或 `clearGlobalHooks()`，避免把注册状态清空了还以为钩子丢失。

## 9. 变更记录
- 2026-03-27：完成生命周期钩子文档，补齐执行顺序、全局/实体差异、误用示例与错误定位。

