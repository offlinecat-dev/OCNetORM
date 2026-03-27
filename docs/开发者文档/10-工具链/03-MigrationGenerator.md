# 03-MigrationGenerator

> 状态：已完成
> 适用版本：ocorm 3.x（当前仓库 3.0.2）
> 最后更新：2026-03-27

## 1. 功能概述
`MigrationGenerator` 负责把当前 Schema 差异转换成一个内存中的 `GeneratedMigration` 对象。

核心行为来自 `tools/MigrationGenerator.ets`：
- `generate(options)` 先调用 `DatabaseManager.getInstance().getStore()`，再委托给 `generateWithStore(store, options)`。
- `generateWithStore(store, options)` 默认创建 `new SchemaDiffer()`，然后调用 `diff(store, { includeJoinTables: options?.includeJoinTables !== false })`。
- 返回值包含 `upSql`、`downSql`、`fileName`、`className`、`content`，但不会自动写文件，也不会自动执行 SQL。

## 2. 输出结构与默认值
`GeneratedMigration` 的关键字段：
- `hasChanges`：是否存在结构变更。
- `version`：时间戳数字，格式来自 `yyyyMMddHHmmss`。
- `className`：默认前缀为 `Migration`，格式为 `Migration_<version>`。
- `fileName`：默认扩展名为 `ets`，格式为 `<className>.ets`。
- `description`：有变更时为 `Auto generated migration (<N> changes)`，无变更时为 `No schema changes`。
- `content`：生成的 ArkTS 迁移类源码，内部实现 `Migration`，并在 `up/down` 中逐条执行 SQL。

从源码实现看：
- 版本号只精确到秒；同一秒内并发生成，可能得到相同 `version` 和 `fileName`。
- `fileExtension` 不会自动去掉前导 `.`；传入 `.ets` 会得到双点文件名。
- `upSql/downSql` 中以 `--` 开头的语句不会执行，而是转成生成代码里的 `//` 注释。

## 3. 适用场景
- 需要先审阅 SQL，再决定是否登记到迁移目录。
- 需要在测试里断言 Schema 差异是否符合预期。
- 需要为 CI 生成稳定的迁移文本快照，而不是直接改数据库。

## 4. 最小可运行示例
下面的例子完全基于真实 API，可直接复用仓库里现有单测写法。它不依赖真实数据库查询，而是通过自定义 `SchemaDiffer` 返回确定的差异结果。

```ets
import { relationalStore } from '@kit.ArkData'
import { MigrationGenerator } from '../../src/main/ets/tools/MigrationGenerator'
import { SchemaDiffResult, SchemaDiffer, SchemaChangeType } from '../../src/main/ets/schema/SchemaDiffer'

class MockSchemaDiffer extends SchemaDiffer {
  private diffResult: SchemaDiffResult

  constructor(diffResult: SchemaDiffResult) {
    super()
    this.diffResult = diffResult
  }

  async diff(_store: relationalStore.RdbStore): Promise<SchemaDiffResult> {
    return this.diffResult
  }
}

const diff = new SchemaDiffResult()
diff.addChange({
  type: SchemaChangeType.CREATE_TABLE,
  tableName: 'users',
  sql: ['CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)'],
  rollbackSql: ['DROP TABLE users'],
  summary: 'create users',
  destructive: false
})

const generated = await MigrationGenerator.generateWithStore(
  {} as relationalStore.RdbStore,
  {
    schemaDiffer: new MockSchemaDiffer(diff),
    classNamePrefix: 'DocMigration',
    fileExtension: 'ets'
  }
)

console.info(generated.hasChanges)
console.info(generated.fileName)
console.info(generated.upSql[0])
console.info(generated.content)
```

预期结果：
- `generated.hasChanges === true`
- `generated.fileName` 类似 `DocMigration_20260327153045.ets`
- `generated.content` 中会出现 `await store.executeSql('CREATE TABLE users ...')`

## 5. 常见误用
### 5.1 把假 `store` 当成真数据库连接
如果你没有注入自定义 `schemaDiffer`，默认 `SchemaDiffer` 会立刻对 `store` 做结构查询。下面这种写法只是在单测里伪造了类型，运行时并不能工作。

```ets
import { relationalStore } from '@kit.ArkData'
import { MigrationGenerator } from '../../src/main/ets/tools/MigrationGenerator'

await MigrationGenerator.generateWithStore({} as relationalStore.RdbStore)

// 误用原因：
// 默认 SchemaDiffer 会调用 SchemaInspector.getExistingTables(store)
// 而空对象没有 querySql 等真实能力，运行时会失败
```

### 5.2 误以为 `fileExtension` 会自动规范化
源码只是把扩展名直接拼到 `${className}.${extension}`。如果把 `.ets` 传进去，结果会带双点。

```ets
import { relationalStore } from '@kit.ArkData'
import { MigrationGenerator } from '../../src/main/ets/tools/MigrationGenerator'
import { SchemaDiffResult, SchemaDiffer } from '../../src/main/ets/schema/SchemaDiffer'

class EmptySchemaDiffer extends SchemaDiffer {
  async diff(_store: relationalStore.RdbStore): Promise<SchemaDiffResult> {
    return new SchemaDiffResult()
  }
}

const generated = await MigrationGenerator.generateWithStore(
  {} as relationalStore.RdbStore,
  {
    schemaDiffer: new EmptySchemaDiffer(),
    fileExtension: '.ets'
  }
)

console.info(generated.fileName)
// 常见输出：Migration_20260327153045..ets
```

### 5.3 误以为 `generateWithStore` 会自动落盘
下面的代码只会拿到字符串，不会在磁盘上生成迁移文件。

```ets
const generated = await MigrationGenerator.generateWithStore(store, options)

console.info(generated.content)
// 到这里为止，磁盘上仍然没有新文件
// 你需要自行决定保存路径、文件名和审核流程
```

## 6. 脚本化 / CI 用法（仓库现有测试）
仓库当前可直接对照的测试文件是 `src/test/Stage17Tools/Tools.test.ets`，其中使用自定义 `SchemaDiffer` 断言生成结果。

```ets
// src/test/Stage17Tools/Tools.test.ets
import { describe, it, expect } from '@ohos/hypium'
import { relationalStore } from '@kit.ArkData'
import { MigrationGenerator } from '../../main/ets/tools/MigrationGenerator'
import { SchemaDiffResult, SchemaDiffer, SchemaChangeType } from '../../main/ets/schema/SchemaDiffer'

class MockSchemaDiffer extends SchemaDiffer {
  private result: SchemaDiffResult

  constructor(result: SchemaDiffResult) {
    super()
    this.result = result
  }

  async diff(_store: relationalStore.RdbStore): Promise<SchemaDiffResult> {
    return this.result
  }
}

// 以下断言片段来自 toolsTest() 中的同名用例
it('MigrationGenerator should generate migration content from diff', 0, async () => {
  const diff = new SchemaDiffResult()
  diff.addChange({
    type: SchemaChangeType.CREATE_TABLE,
    tableName: 'users',
    sql: ['CREATE TABLE users (id INTEGER PRIMARY KEY)'],
    rollbackSql: ['DROP TABLE users'],
    summary: 'create users',
    destructive: false
  })

  const generated = await MigrationGenerator.generateWithStore(
    {} as relationalStore.RdbStore,
    { schemaDiffer: new MockSchemaDiffer(diff), classNamePrefix: 'Migration', fileExtension: 'ets' }
  )

  expect(generated.hasChanges).assertEqual(true)
  expect(generated.fileName.indexOf('Migration_') >= 0).assertEqual(true)
  expect(generated.content.indexOf('await store.executeSql') >= 0).assertEqual(true)
})
```

```powershell
# 文档示例对应的最小 CI 步骤
ohpm install
hvigor clean
hvigor test
```

## 7. 与 `SchemaDiffer` 的协作边界
`MigrationGenerator` 自身不分析表结构，真正的差异计算由 `SchemaDiffer` 完成：
- `SchemaDiffResult.changes` 决定 `description` 中的变更数量。
- `SchemaDiffResult.plannedSql` 会被原样复制到 `GeneratedMigration.upSql`。
- `SchemaDiffResult.rollbackSql` 会被原样复制到 `GeneratedMigration.downSql`。

如果你需要稳定、可预测的输出，优先在测试里注入自定义 `schemaDiffer`，不要把真实数据库状态直接混进单元测试。

## 8. 验收清单
- `hasChanges` 与 `diff.hasChanges()` 一致。
- `fileName`、`className` 使用了约定前缀和扩展名。
- `content` 中的 `up/down` 方法与 `upSql/downSql` 一一对应。
- 注释型 SQL（`-- ...`）在生成代码中变成 `// ...`，而不是 `executeSql(...)`。
- 无差异时 `description === 'No schema changes'`，并且 `up/down` 生成 `// no-op`。

## 9. 变更记录
- 2026-03-27：补全文档，覆盖最小示例、误用示例、CI 用法与源码行为约束
