# SchemaBuilder建表策略

`SchemaBuilder` 适合项目初期或本地开发快速落库。

## 何时使用
- 新项目首次建表
- 本地联调环境快速同步表结构

## 基本用法
```ts
import { SchemaBuilder } from 'ocorm'

const builder = new SchemaBuilder()
await builder.createAllTablesWithManager()
```

## 实践建议
- 生产环境优先使用迁移文件，不建议每次启动直接全量建表
- 建表前先完成实体注册，避免出现缺列或表不完整
- 建表失败时先检查数据库权限和实体定义一致性
