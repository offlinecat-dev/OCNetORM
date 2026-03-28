# MigrationManager执行流程

`MigrationManager` 负责按顺序执行迁移并记录状态。

## 推荐执行流程
1. 启动前完成实体注册
2. 执行迁移
3. 校验版本与关键表结构
4. 记录结果并进入业务流程

## 最小调用
```ts
import { MigrationManager } from 'ocorm'

// 具体迁移列表按你的项目注册方式提供
// await MigrationManager.run([...])
```

## 失败处理
- 一次发布只做一组迁移变更
- 迁移失败立即停止后续写入
- 结合版本日志定位失败步骤后再重试
