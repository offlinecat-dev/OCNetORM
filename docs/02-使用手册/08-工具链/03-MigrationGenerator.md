# MigrationGenerator

`MigrationGenerator` 用于根据差异生成迁移文件骨架，减少手写模板成本。

## 基本示例
```ts
import { MigrationGenerator } from 'ocorm'

const generated = await MigrationGenerator.generate()
console.info(generated.fileName)
```

## 使用建议
- 生成后必须人工审核 SQL
- 生产发布前在预发库先跑一次
- 迁移文件命名包含时间与语义，便于追踪
