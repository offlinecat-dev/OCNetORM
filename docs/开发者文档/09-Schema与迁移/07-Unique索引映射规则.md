# 07-Unique索引映射规则

> 状态：已完成
> 适用版本：ocorm 3.x（当前仓库实现）
> 最后更新：2026-03-27

## 1. 目标
- 说明 `resolveEntityIndexes(metadata)` 如何把验证层的 `unique` 规则补充为数据库唯一索引元数据。
- 区分三类来源：列级 `isUnique`、显式 `IndexMetadata(unique=true)`、验证规则 `type='unique'`。
- 明确去重、命名、执行边界，避免重复建索引或误判联合唯一约束。

## 2. 映射规则
- 输入：单个 `EntityMetadata`。
- 输出：`Array<IndexMetadata>`，来源于 `metadata.getIndexes()` 的副本，再追加“缺失的唯一单列索引”。
- 只有满足以下条件的列才会从验证规则映射出唯一索引：
  - 该属性存在 `ValidationRule.type === 'unique'`
  - 该属性能映射到真实列 `metadata.getColumnByProperty(propertyName)`
  - 该列不是主键
  - 该列本身不是 `column.isUnique === true`
- 只补单列唯一索引，不生成联合索引。

```arkts
import { resolveEntityIndexes } from '../schema/UniqueIndexResolver'

const indexes = resolveEntityIndexes(metadata)
for (let i = 0; i < indexes.length; i++) {
  console.info(`name=${indexes[i].name}, unique=${indexes[i].unique}, columns=${indexes[i].columns.join(',')}`)
}
```

## 3. 去重与命名
- 单列唯一索引去重规则：
  - 必须是 `unique=true`
  - 必须只包含 1 列
  - 列名比较按 `trim().toLowerCase()` 处理
- 索引名冲突规则：
  - 先生成基础名 `uidx_${safeTableName}_${safeColumnName}`
  - 若名字已存在，则自动加后缀 `_1`、`_2`、`_3` ...
- 安全名称规则：
  - `tableName` 与 `columnName` 中非 `[a-zA-Z0-9_]` 字符会被替换成 `_`

```arkts
// 命名示例
// tableName = "validated-users", columnName = "email.address"
// => baseName = "uidx_validated_users_email_address"
```

```sql
-- 最终生成的 SQL 由 SchemaDiffer / SchemaBuilder 消费 IndexMetadata 后产出
CREATE UNIQUE INDEX IF NOT EXISTS "uidx_validated_users_email"
ON "validated_users" ("email");
```

## 4. 正确迁移示例（推荐）
- 推荐做法是：先注册实体与列，再注册验证规则，然后让 `SchemaDiffer` / `SchemaBuilder` 自动消费 `resolveEntityIndexes()` 的结果。
- 仓库测试已覆盖：当数据库中不存在等价唯一索引时，`SchemaDiffer.diff()` 会产出 `CREATE_INDEX` 变更，且索引名包含 `uidx_...`。

```arkts
import { ColumnMetadata } from '../core/ColumnMetadata'
import { MetadataStorage } from '../core/MetadataStorage'
import { ColumnType } from '../types/ColumnType'
import { ValidationMetadataStorage } from '../validation/ValidationMetadataStorage'
import { resolveEntityIndexes } from '../schema/UniqueIndexResolver'

const storage = MetadataStorage.getInstance()
storage.registerEntity('ValidatedUser', 'validated_users')
storage.registerColumn('ValidatedUser', new ColumnMetadata('id', 'id').setType(ColumnType.INTEGER).setPrimaryKey(true))
storage.registerColumn('ValidatedUser', new ColumnMetadata('email', 'email').setType(ColumnType.TEXT))

ValidationMetadataStorage.getInstance().registerRule('ValidatedUser', 'email', { type: 'unique' })

const metadata = storage.getEntityMetadata('ValidatedUser')
if (metadata === null) {
  throw new Error('实体未注册')
}

const indexes = resolveEntityIndexes(metadata)
console.info(indexes[0].name) // 典型结果: uidx_validated_users_email
```

```arkts
import { SchemaDiffer } from '../schema/SchemaDiffer'

const diff = await new SchemaDiffer().diff(store)
for (let i = 0; i < diff.changes.length; i++) {
  const change = diff.changes[i]
  if (change.type === 'CREATE_INDEX') {
    console.info(change.sql[0])
  }
}
```

## 5. 误用示例（禁止）
- 误用 1：以为验证规则 `unique` 会自动生成联合唯一索引。
- 误用 2：列已经 `isUnique=true`，还期待 `resolveEntityIndexes()` 再补一条重复索引。
- 误用 3：属性未映射到列，却期待注册 `unique` 规则后也能生成索引。

```arkts
// 误用：unique 验证规则只会映射单列唯一索引，不支持组合键
ValidationMetadataStorage.getInstance().registerRule('OrderItem', 'orderId', { type: 'unique' })
ValidationMetadataStorage.getInstance().registerRule('OrderItem', 'productId', { type: 'unique' })

// 结果不会自动变成 UNIQUE(order_id, product_id)
```

```arkts
import { ColumnMetadata } from '../core/ColumnMetadata'
import { ColumnType } from '../types/ColumnType'

storage.registerEntity('DirectUniqueUser', 'direct_unique_users')
storage.registerColumn(
  'DirectUniqueUser',
  new ColumnMetadata('email', 'email').setType(ColumnType.TEXT).setUnique(true)
)
ValidationMetadataStorage.getInstance().registerRule('DirectUniqueUser', 'email', { type: 'unique' })

// 误用：这里不会再追加一条重复的 unique 单列索引
```

```arkts
storage.registerEntity('BrokenUser', 'broken_users')
ValidationMetadataStorage.getInstance().registerRule('BrokenUser', 'email', { type: 'unique' })

const brokenMetadata = storage.getEntityMetadata('BrokenUser')
if (brokenMetadata !== null) {
  const indexes = resolveEntityIndexes(brokenMetadata)
  console.info(indexes.length) // 误用：没有映射列时，不会自动生成索引
}
```

## 6. 失败处理 / 日志 / 回滚说明
- `resolveEntityIndexes()` 自身只做内存计算：
  - 不执行 SQL
  - 不开事务
  - 不写 `_migrations`
  - 不做 `rollBack()`
- 真正的失败点在后续执行阶段：
  - `SchemaDiffer` 可能为该索引生成 `CREATE_INDEX`
  - `SchemaBuilder` 可能在建表阶段执行该索引 SQL
  - `AutoMigrationHandler` / `MigrationManager` 负责事务、日志与回滚
- 如果唯一索引创建失败，日志应到 `AUTO_SCHEMA` 或 `MIGRATION` 表记录中排查，而不是指望 `resolveEntityIndexes()` 产生日志。

```arkts
import { MigrationManager, AutoMigrationMode } from '../schema/MigrationManager'

const manager = new MigrationManager({
  enableLog: true,
  autoMigrationMode: AutoMigrationMode.SAFE
})

const result = await manager.autoMigrate(store, {
  mode: AutoMigrationMode.SAFE,
  logChanges: true
})

if (!result.success) {
  console.error(result.errorMessage)
}
```

```sql
-- 排查唯一索引相关自动迁移日志
SELECT type, table_name, column_name, sql, success, error_message, created_at
FROM "_migrations"
WHERE type = 'AUTO_SCHEMA'
  AND sql LIKE '%CREATE UNIQUE INDEX%'
ORDER BY id DESC
LIMIT 20;
```

```sql
-- SchemaDiffer 测试中验证的典型索引名
CREATE UNIQUE INDEX IF NOT EXISTS "uidx_validated_users_email"
ON "validated_users" ("email");
```

## 7. 验收清单
- `unique` 验证规则能补出单列唯一索引，且名字以 `uidx_` 开头。
- 数据库若已存在“列相同且 unique=true”的单列索引，即使名字不同，也不会重复生成。
- 主键列或 `column.isUnique=true` 的列不会再被重复映射。
- 非法字符会在索引名中被替换成 `_`，重名时自动追加数值后缀。

## 8. 变更记录
- 2026-03-27：基于 `UniqueIndexResolver`、`SchemaDiffer`、`ValidationMetadataStorage` 及相关测试补全文档。
