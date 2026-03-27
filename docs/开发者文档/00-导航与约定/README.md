# 00-导航与约定

> 适用版本：`ocorm 3.0.2`  
> 最后校准：`2026-03-27`

本目录是开发者文档的入口层，负责三件事：
1. 给出读者路径（先读什么、按什么任务读）。
2. 固定术语定义（避免同一个词被不同文章写成不同含义）。
3. 固定版本与兼容口径（HAR/HAP、API 版本、测试档位）。

## 1. 文档边界（只写真实行为）
- 本文档只描述仓库中可追溯的代码与配置行为，不写“计划中能力”。
- 对外 API 以 `OCORM/Index.ets` 实际导出为准，不以历史文档为准。
- 构建与兼容信息以 `build-profile.json5`、模块 `module.json5`、`oh-package.json5`、`BuildProfile.ets` 为准。
- 测试档位行为以 `entry/src/main/ets/suites/index.ets` 和 `entry/src/main/ets/testcore/CommandSuiteRunner.ets` 为准。

## 2. 建议阅读顺序
1. [01-文档阅读路径](./01-文档阅读路径.md)
2. [02-术语表](./02-术语表.md)
3. [03-版本与兼容矩阵](./03-版本与兼容矩阵.md)
4. 再进入能力章节（`01-工程与构建` 到 `19-Roadmap与变更计划`）

## 3. 关键源码索引
- 导出入口：`OCORM/Index.ets`
- 统一导出：
  - `OCORM/src/main/ets/core/index.ets`
  - `OCORM/src/main/ets/database/index.ets`
  - `OCORM/src/main/ets/query/index.ets`
  - `OCORM/src/main/ets/repository/index.ets`
- 构建配置：
  - `build-profile.json5`（根工程 products/modules）
  - `OCORM/build-profile.json5`（HAR release 混淆）
  - `OCORM/src/main/module.json5`（`type: har`）
  - `entry/src/main/module.json5`（`type: entry`）
  - `OCORM/src/ohosTest/module.json5`（`type: feature`）
- 版本口径：
  - `OCORM/BuildProfile.ets`（`HAR_VERSION = '3.0.2'`）
  - `OCORM/oh-package.json5`（`version: "3.0.2"`）
- 测试档位：
  - `entry/src/main/ets/suites/index.ets`
  - `entry/src/main/ets/entryability/EntryAbility.ets`
  - `entry/src/main/ets/testcore/CommandSuiteRunner.ets`

## 4. 文档维护约定
- 涉及 API 变更：先改对应章节，再回写本目录三篇总览文档。
- 涉及行为边界（事务、隔离级别、raw SQL、连接池）：必须在文档里写清“支持/不支持/回退/失败语义”。
- 涉及测试口径：除了更新总数，还要说明档位选择逻辑是否变化（`default/ci/ci-performance`）。

## 5. 快速代码路径（代码驱动）

```bash
# 正确示例：先看公共导出面，再追到子模块导出，最后看实现
rg "export \\{" OCORM/Index.ets
rg "export \\{ OCORMInit|export \\{ QueryBuilder|export \\{ DatabaseConfig" OCORM/src/main/ets -g "index.ets"
rg "class DatabaseConfig|function OCORMInit|class QueryExecutor" OCORM/src/main/ets
```

```bash
# 常见错误示例：只看历史文档，不看当前源码导出
# (错误不是命令语法错误，而是流程错误)
rg "OCORMInit" OCORM/docs
```

预期行为：
- 正确流程会先锁定 `OCORM/Index.ets` 的真实 export，再定位到 `src/main/ets/*/index.ets` 与实现文件。
- 错误流程容易把“文档提到过的能力”当成“当前版本稳定 API”。

```arkts
// 正确示例：只使用公共导出面（Index.ets）暴露的 API
import { OCORMInit, DatabaseConfig, LogLevel } from 'ocorm'

const config = new DatabaseConfig('app.db')
  .setMaxConcurrentQueries(4)
  .setQueryTimeout(3000)
  .setRelationInClauseLimit(500)

await OCORMInit(this.context, {
  config,
  enableLogger: true,
  logLevel: LogLevel.INFO,
  autoCreateTables: true
})
```

```arkts
// 常见错误示例：直接依赖内部路径（绕过公共导出面）
import { OCORMInit } from 'ocorm/src/main/ets/core/OrmInit'
```

预期行为：
- 正确示例与 `OCORM/Index.ets` 对齐，属于稳定公开面。
- 错误示例会把内部实现路径暴露给业务层，升级时极易断裂。
