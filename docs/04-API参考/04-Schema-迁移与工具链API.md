# 04-Schema-迁移与工具链API

何时用：建表、迁移、测试数据生成。

怎么用：
```ts
import { SchemaBuilder, MigrationManager, SeederManager, defineFactory } from 'ocorm'
```

常见误用：生产环境直接依赖自动建表替代迁移流程。

