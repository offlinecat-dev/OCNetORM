# SeederManager

`SeederManager` 用于执行种子任务，适合初始化基础数据和开发环境填充。

## 典型场景
- 首次部署后写入基础字典
- 本地开发快速初始化演示数据

## 基本示例
```ts
import { SeederManager } from 'ocorm'

await SeederManager.run([])
```

## 实践建议
- 把种子分成“基础数据”和“演示数据”两类
- 生产只执行基础数据种子
- 保持幂等，避免重复执行脏数据
