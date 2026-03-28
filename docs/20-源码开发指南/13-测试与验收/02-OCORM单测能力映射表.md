# 02-OCORM单测能力映射表

> 状态：已完成
> 适用版本：ocorm 3.x（以 `src/test/*` 当前内容为准）
> 最后更新：2026-03-28

## 1. 目标

本文用于回答两个问题：

1. OCORM 库级单测现在按什么目录分层。
2. 某类能力应该去哪个 Stage 查证，而不是到处翻测试文件。

本文只基于 `src/test/*` 的真实目录与文件名，不统计测试总数，不估算覆盖率。

## 2. 根目录与 Stage 总览

OCORM 单测根目录当前结构如下，先记住入口，再记住分层：

```text
src/test/
  List.test.ets
  LocalUnit.test.ets
  Smoke.test.ets
  Stage1Core/
  Stage2Decorators/
  Stage3Validation/
  Stage4Mapping/
  Stage5Query/
  Stage6QueryExecution/
  Stage7Repository/
  Stage8Cache/
  Stage9Database/
  Stage10SchemaMigration/
  Stage11Logging/
  Stage12Errors/
  Stage13Relations/
  Stage14SoftDelete/
  Stage15Performance/
  Stage16Compatibility/
  Stage17Tools/
```

根目录文件职责：

| 路径 | 用途 | 备注 |
| --- | --- | --- |
| `src/test/List.test.ets` | 当前 Hypium 入口聚合文件 | 目前只导入 `Smoke.test.ets` |
| `src/test/LocalUnit.test.ets` | 基础 Hypium 示例 | 属于模板式断言示例，不等于 Stage 主体测试 |
| `src/test/Smoke.test.ets` | 最小冒烟验证 | 只验证测试套件能跑起来 |

## 3. Stage 能力映射

下表只写可由目录名与文件名静态确认的能力边界。

| Stage | 真实目录 | 代表文件 | 能力边界 |
| --- | --- | --- | --- |
| Stage 1 | `src/test/Stage1Core` | `CoreContextInit.test.ets`、`EntityMetadata.test.ets`、`LocalUnit.test.ets` | 核心上下文、元数据、基础初始化 |
| Stage 2 | `src/test/Stage2Decorators` | `Decorators.test.ets` | 装饰器声明与元数据登记 |
| Stage 3 | `src/test/Stage3Validation` | `Validation.test.ets` | 验证规则与校验流程 |
| Stage 4 | `src/test/Stage4Mapping` | `DataMapper.test.ets`、`TypeConverter.test.ets`、`ResultSetUtils.test.ets` | 数据映射、类型转换、实体数据模型 |
| Stage 5 | `src/test/Stage5Query` | `QueryBuilder.test.ets`、`PredicateBuilder.test.ets`、`SubQuery.test.ets`、`WhereCondition.test.ets` | 条件构造、查询构建、子查询 |
| Stage 6 | `src/test/Stage6QueryExecution` | `QueryExecutor.test.ets`、`RelationLoader.test.ets`、`SubQueryExecutorFix.test.ets` | 查询执行、分页结果、关联加载、子查询执行修复 |
| Stage 7 | `src/test/Stage7Repository` | `RepositoryQuery.test.ets`、`RepositoryTransaction.test.ets`、`SaveInsertUpdate.test.ets` | Repository CRUD、事务、批量操作、级联、多对多 |
| Stage 8 | `src/test/Stage8Cache` | `QueryCache.test.ets` | 查询缓存 |
| Stage 9 | `src/test/Stage9Database` | `Database.test.ets` | 数据库管理与连接状态 |
| Stage 10 | `src/test/Stage10SchemaMigration` | `MigrationManager.test.ets`、`SchemaBuilder.test.ets`、`SchemaDiffer.test.ets` | Schema 构建、差异对比、迁移日志与执行 |
| Stage 11 | `src/test/Stage11Logging` | `Logger.test.ets` | 日志能力 |
| Stage 12 | `src/test/Stage12Errors` | `ErrorClasses.test.ets`、`ErrorCodes.test.ets`、`ErrorLocale.test.ets` | 错误类、错误码、本地化消息 |
| Stage 13 | `src/test/Stage13Relations` | `Relations.test.ets` | 关联关系建模与行为 |
| Stage 14 | `src/test/Stage14SoftDelete` | `SoftDelete.test.ets` | 软删除、恢复、查询过滤 |
| Stage 15 | `src/test/Stage15Performance` | `Performance.test.ets` | 性能与并行负载场景 |
| Stage 16 | `src/test/Stage16Compatibility` | `Compatibility.test.ets` | 边界值、兼容性、非法参数 |
| Stage 17 | `src/test/Stage17Tools` | `Tools.test.ets` | 工具链与开发辅助能力 |

如果只想快速定位能力，不要扫全文，直接按下面的路径映射查：

```text
核心上下文/元数据         -> src/test/Stage1Core/*
装饰器                   -> src/test/Stage2Decorators/*
验证                     -> src/test/Stage3Validation/*
映射/类型转换            -> src/test/Stage4Mapping/*
QueryBuilder/Where/SubQuery -> src/test/Stage5Query/*
QueryExecutor/RelationLoader -> src/test/Stage6QueryExecution/*
Repository/Transaction   -> src/test/Stage7Repository/*
Cache                    -> src/test/Stage8Cache/*
Database                 -> src/test/Stage9Database/*
Schema/Migration         -> src/test/Stage10SchemaMigration/*
Logging                  -> src/test/Stage11Logging/*
Errors                   -> src/test/Stage12Errors/*
Relations                -> src/test/Stage13Relations/*
SoftDelete               -> src/test/Stage14SoftDelete/*
Performance              -> src/test/Stage15Performance/*
Compatibility            -> src/test/Stage16Compatibility/*
Tools                    -> src/test/Stage17Tools/*
```

## 4. 正确示例

### 4.1 查询能力应落在 Stage5Query

下面这种写法符合当前分层，因为它把 `QueryBuilder` 行为验证放在 `Stage5Query/QueryBuilder.test.ets` 这一层。

```ts
it('whereExists should add sub query', 0, () => {
  setupTestEntity();
  setupRelations();
  const builder = new QueryBuilder('User');
  builder.whereExists('posts', (subQuery) => {
    subQuery.whereLike('title', '%test%');
  });
  const relationSubQueries = builder.getRelationSubQueries();
  expect(relationSubQueries.length).assertEqual(1);
});
```

### 4.2 事务行为应落在 Stage7Repository

事务超时、回滚、重试，不应该写去 Query 层；当前真实测试就在 `RepositoryTransaction.test.ets`。

```ts
it('transactionWithOptions timeout should rollback without commit', 0, async () => {
  setupUserEntity();
  const repo = new Repository('User');
  const options = TransactionOptions.withTimeout(10);

  let threw = false;
  try {
    await repo.transactionWithOptions(async () => {
    }, options);
  } catch (error) {
    threw = error instanceof TransactionRollbackError;
  }

  expect(threw).assertEqual(true);
});
```

## 5. 误用示例

下面这种做法是错的：把 Repository 事务回归塞进 Stage5Query，只因为它“也会生成 SQL”。这会直接破坏目录语义。

```ts
// 错误示例：不要这样放文件
// src/test/Stage5Query/RepositoryTransaction.test.ets

import { Repository } from '../../main/ets/repository/index';

export default function repositoryTransactionTest() {
  // 错误点 1：事务属于 Repository 能力边界，不属于 QueryBuilder / PredicateBuilder / SubQuery
  // 错误点 2：后续检索 Stage7Repository 时会漏掉这类测试
  // 错误点 3：Stage 语义被打散后，回归定位成本会上升
}
```

另一个误用是想当然地把根入口当成“全量单测入口”：

```text
错误认知：
  “我把新测试加到 src/test/Stage6QueryExecution/NewFix.test.ets 里，
   只要跑 src/test/List.test.ets 就一定会执行到。”

当前仓库事实：
  src/test/List.test.ets 目前只导入 Smoke.test.ets。
  是否执行到 Stage 文件，必须看实际入口和运行配置，不能靠猜。
```

## 6. 验收命令与检查清单

不要报“覆盖了哪些能力”，除非先把真实路径列出来。

```powershell
# 1. 列出 OCORM 单测真实目录与文件
Get-ChildItem 'src/test' -Directory | Sort-Object Name
Get-ChildItem 'src/test' -Recurse -Filter '*.test.ets' | Sort-Object FullName

# 2. 核对关键能力对应文件
rg -n "QueryBuilder|whereExists|orderBy|having" src/test/Stage5Query
rg -n "transactionWithOptions|TransactionRollbackError|嵌套调用" src/test/Stage7Repository
rg -n "leading-zero|string ids|前导零" src/test/Stage6QueryExecution
rg -n "Compatibility|invalid_column|negative_limit|unicode" src/test/Stage16Compatibility

# 3. 如需执行仓库测试入口，使用项目现有命令
hvigor test
```

```text
[验收检查清单]
1. 能力映射必须能落回真实路径，不能只写概念名词。
2. 新增 Query 构造测试时，优先放 Stage5Query，而不是 Stage6/Stage7。
3. 新增执行器、分页、关联加载修复时，优先放 Stage6QueryExecution。
4. 新增事务、保存、删除、批量、级联回归时，优先放 Stage7Repository。
5. 不得声称根目录 List.test.ets 已聚合全部 Stage 文件，除非源码已更新并复核。
6. 不得编造“共 N 个测试”或“覆盖率 X%”；需要时用命令现场列出。
```

## 7. 结论

OCORM 单测不是按业务模块随意堆放，而是按能力边界拆到 `Stage1` 到 `Stage17`。

实际使用时按这条规则定位：

1. 先判断能力边界。
2. 再匹配 Stage 目录。
3. 最后再挑同目录下最接近的现有测试文件扩展。

顺序错了，目录很快就会变成垃圾桶。

## 8. 变更记录

- 2026-03-28：按 `src/test/*` 真实目录补全 Stage 能力映射、正确示例、误用示例与验收命令。
