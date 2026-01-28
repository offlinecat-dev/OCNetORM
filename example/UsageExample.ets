/**
 * OCORM 完整使用示例
 * 演示 ORM 框架的各种功能
 * 符合 ArkTS 严格类型规范
 */

import { Context } from '@kit.AbilityKit'
import {
  OCORMInit,
  OCORMInitOptions,
  DatabaseConfig,
  LogLevel,
  MetadataStorage,
  ColumnMetadata,
  ColumnType,
  Repository,
  SaveResult,
  DeleteResult,
  QueryExecutor,
  ConditionOperator,
  EntityData,
  TransactionOptions,
  TransactionOptionsConfig,
  IsolationLevel
} from 'ocorm'

import { relationalStore } from '@kit.ArkData'

/**
 * OCORMInitOptions 实现类
 */
class InitOptions implements OCORMInitOptions {
  config: DatabaseConfig
  autoCreateTables: boolean = true

  constructor(config: DatabaseConfig) {
    this.config = config
  }
}

/**
 * TransactionOptionsConfig 实现类
 */
class TxOptionsConfig implements TransactionOptionsConfig {
  isolation?: IsolationLevel
  timeout?: number
  retries?: number
  retryDelay?: number
  readOnly?: boolean
}

// ============================================
// 第一步：注册实体（使用 MetadataStorage API）
// ============================================

/**
 * 注册文章实体
 */
function registerArticleEntity(): void {
  const storage = MetadataStorage.getInstance()

  // 注册实体
  storage.registerEntity('ArticleEntity', 'articles')

  // 注册主键列
  const idColumn = new ColumnMetadata('id', 'id')
  idColumn.setType(ColumnType.INTEGER)
  idColumn.setPrimaryKey(true)
  idColumn.setAutoIncrement(true)
  storage.registerColumn('ArticleEntity', idColumn)

  // 注册标题列
  const titleColumn = new ColumnMetadata('title', 'title')
  titleColumn.setType(ColumnType.TEXT)
  titleColumn.setNullable(false)
  storage.registerColumn('ArticleEntity', titleColumn)

  // 注册内容列
  const contentColumn = new ColumnMetadata('content', 'content')
  contentColumn.setType(ColumnType.TEXT)
  contentColumn.setNullable(true)
  storage.registerColumn('ArticleEntity', contentColumn)

  // 注册作者ID列
  const authorIdColumn = new ColumnMetadata('authorId', 'author_id')
  authorIdColumn.setType(ColumnType.INTEGER)
  authorIdColumn.setNullable(false)
  storage.registerColumn('ArticleEntity', authorIdColumn)

  // 注册浏览量列
  const viewCountColumn = new ColumnMetadata('viewCount', 'view_count')
  viewCountColumn.setType(ColumnType.INTEGER)
  viewCountColumn.setDefaultValue(0)
  storage.registerColumn('ArticleEntity', viewCountColumn)

  // 注册发布状态列
  const isPublishedColumn = new ColumnMetadata('isPublished', 'is_published')
  isPublishedColumn.setType(ColumnType.INTEGER)
  isPublishedColumn.setDefaultValue(0)
  storage.registerColumn('ArticleEntity', isPublishedColumn)

  // 注册创建时间列
  const createdAtColumn = new ColumnMetadata('createdAt', 'created_at')
  createdAtColumn.setType(ColumnType.INTEGER)
  createdAtColumn.setNullable(false)
  storage.registerColumn('ArticleEntity', createdAtColumn)

  // 注册更新时间列
  const updatedAtColumn = new ColumnMetadata('updatedAt', 'updated_at')
  updatedAtColumn.setType(ColumnType.INTEGER)
  updatedAtColumn.setNullable(false)
  storage.registerColumn('ArticleEntity', updatedAtColumn)

  // 注册软删除列
  const deletedAtColumn = new ColumnMetadata('deletedAt', 'deleted_at')
  deletedAtColumn.setType(ColumnType.INTEGER)
  deletedAtColumn.setNullable(true)
  storage.registerColumn('ArticleEntity', deletedAtColumn)

  // 启用软删除
  const metadata = storage.getEntityMetadata('ArticleEntity')
  if (metadata !== null) {
    metadata.setSoftDelete(true, 'deleted_at')
  }
}

// ============================================
// 第二步：初始化数据库
// ============================================

/**
 * 初始化 OCORM
 * @param context 应用上下文
 */
async function initializeORM(context: Context): Promise<void> {
  // 注册实体
  registerArticleEntity()

  // 创建数据库配置
  const config = new DatabaseConfig(
    'example.db',
    relationalStore.SecurityLevel.S1,
    false,
    true,
    LogLevel.DEBUG
  )

  // 创建初始化选项
  const initOptions = new InitOptions(config)
  initOptions.autoCreateTables = true

  // 初始化
  await OCORMInit(context, initOptions)
}

// ============================================
// 第三步：CRUD 操作示例
// ============================================

/**
 * 创建文章
 */
async function createArticle(title: string, content: string, authorId: number): Promise<SaveResult> {
  const repository = new Repository('ArticleEntity')

  const articleData = new EntityData('ArticleEntity')
  articleData.addProperty('title', title, 'string')
  articleData.addProperty('content', content, 'string')
  articleData.addProperty('authorId', authorId, 'number')
  articleData.addProperty('viewCount', 0, 'number')
  articleData.addProperty('isPublished', false, 'boolean')
  articleData.addProperty('createdAt', Date.now(), 'number')
  articleData.addProperty('updatedAt', Date.now(), 'number')

  return await repository.save(articleData)
}

/**
 * 根据 ID 查询文章
 */
async function findArticleById(id: number): Promise<EntityData | null> {
  const repository = new Repository('ArticleEntity')
  return await repository.findById(id)
}

/**
 * 查询所有文章
 */
async function findAllArticles(): Promise<Array<EntityData>> {
  const repository = new Repository('ArticleEntity')
  return await repository.findAll()
}

/**
 * 更新文章
 */
async function updateArticle(id: number, title?: string, content?: string): Promise<SaveResult> {
  const repository = new Repository('ArticleEntity')
  const existing = await repository.findById(id)

  if (existing === null) {
    return SaveResult.createFailure('文章不存在')
  }

  // 使用 setPropertyValue 更新属性
  if (title !== undefined) {
    existing.setPropertyValue('title', title)
  }
  if (content !== undefined) {
    existing.setPropertyValue('content', content)
  }
  existing.setPropertyValue('updatedAt', Date.now())

  return await repository.save(existing)
}

/**
 * 删除文章（软删除）
 */
async function deleteArticle(id: number): Promise<DeleteResult> {
  const repository = new Repository('ArticleEntity')
  return await repository.removeById(id)
}

// ============================================
// 第四步：查询构建器示例
// ============================================

/**
 * 基础查询示例
 */
async function basicQueryExamples(): Promise<void> {
  const repository = new Repository('ArticleEntity')

  // 1. 简单条件查询
  const publishedArticles = repository.createQueryBuilder()
    .where('isPublished', ConditionOperator.EQUAL, true)
    .orderBy('createdAt', 'DESC')
    .limit(10)

  const executor1 = new QueryExecutor(publishedArticles)
  const results1 = await executor1.get()
  console.info(`已发布文章数量: ${results1.length}`)

  // 2. 多条件查询
  const queryBuilder2 = repository.createQueryBuilder()
    .where('authorId', ConditionOperator.EQUAL, 1)
    .andWhere('viewCount', ConditionOperator.GREATER, 100)
    .orderBy('viewCount', 'DESC')

  const executor2 = new QueryExecutor(queryBuilder2)
  const results2 = await executor2.get()
  console.info(`热门文章数量: ${results2.length}`)

  // 3. LIKE 模糊查询
  const queryBuilder3 = repository.createQueryBuilder()
    .whereLike('title', '%HarmonyOS%')

  const executor3 = new QueryExecutor(queryBuilder3)
  const results3 = await executor3.get()
  console.info(`包含 HarmonyOS 的文章: ${results3.length}`)

  // 4. IN 查询
  const queryBuilder4 = repository.createQueryBuilder()
    .whereIn('authorId', [1, 2, 3])

  const executor4 = new QueryExecutor(queryBuilder4)
  const results4 = await executor4.get()
  console.info(`指定作者的文章: ${results4.length}`)

  // 5. BETWEEN 范围查询
  const oneWeekAgo = Date.now() - 7 * 24 * 60 * 60 * 1000
  const queryBuilder5 = repository.createQueryBuilder()
    .whereBetween('createdAt', oneWeekAgo, Date.now())
    .orderBy('createdAt', 'DESC')

  const executor5 = new QueryExecutor(queryBuilder5)
  const results5 = await executor5.get()
  console.info(`最近一周的文章: ${results5.length}`)

  // 6. NULL 查询
  const queryBuilder6 = repository.createQueryBuilder()
    .whereNull('content')

  const executor6 = new QueryExecutor(queryBuilder6)
  const results6 = await executor6.get()
  console.info(`无内容的文章: ${results6.length}`)

  // 7. OR 条件查询
  const queryBuilder7 = repository.createQueryBuilder()
    .where('isPublished', ConditionOperator.EQUAL, true)
    .orWhere('viewCount', ConditionOperator.GREATER, 1000)

  const executor7 = new QueryExecutor(queryBuilder7)
  const results7 = await executor7.get()
  console.info(`已发布或热门文章: ${results7.length}`)
}

/**
 * 分页查询示例
 */
async function paginationExample(): Promise<void> {
  const repository = new Repository('ArticleEntity')

  // 使用 Repository 的分页方法
  const page1 = await repository.findPaginated(1, 10)
  console.info(`第一页数据: ${page1.data.length} 条`)
  console.info(`总记录数: ${page1.total}`)
  console.info(`总页数: ${page1.totalPages}`)
  console.info(`当前页: ${page1.page}`)
  console.info(`是否有下一页: ${page1.hasNextPage()}`)

  // 使用 QueryBuilder 的分页
  const queryBuilder = repository.createQueryBuilder()
    .where('isPublished', ConditionOperator.EQUAL, true)
    .orderBy('createdAt', 'DESC')
    .paginate(2, 10)

  const executor = new QueryExecutor(queryBuilder)
  const page2 = await executor.getPaginated()
  console.info(`第二页已发布文章: ${page2.data.length} 条`)
}

/**
 * 软删除示例
 */
async function softDeleteExample(): Promise<void> {
  const repository = new Repository('ArticleEntity')

  // 1. 正常查询（自动排除已删除数据）
  const activeArticles = await repository.findAll()
  console.info(`活跃文章: ${activeArticles.length}`)

  // 2. 包含已删除数据的查询
  const allArticles = await repository.findAll(true)
  console.info(`所有文章(含已删除): ${allArticles.length}`)

  // 3. 仅查询已删除数据
  const queryBuilder = repository.createQueryBuilder()
    .onlyDeleted()

  const executor = new QueryExecutor(queryBuilder)
  const deletedArticles = await executor.get()
  console.info(`已删除文章: ${deletedArticles.length}`)

  // 4. 恢复已删除的文章
  if (deletedArticles.length > 0) {
    const firstDeleted = deletedArticles[0]
    const articleId = firstDeleted.getPropertyValue('id') as number
    const restoreResult = await repository.restore(articleId)
    console.info(`恢复结果: ${restoreResult.success}`)
  }
}

/**
 * 统计查询示例
 */
async function countExample(): Promise<void> {
  const repository = new Repository('ArticleEntity')

  // 1. 统计所有文章
  const totalCount = await repository.count()
  console.info(`文章总数: ${totalCount}`)

  // 2. 使用 QueryExecutor 统计
  const queryBuilder = repository.createQueryBuilder()
    .where('isPublished', ConditionOperator.EQUAL, true)

  const executor = new QueryExecutor(queryBuilder)
  const publishedCount = await executor.count()
  console.info(`已发布文章数: ${publishedCount}`)
}

// ============================================
// 第五步：事务操作示例
// ============================================

/**
 * 事务示例
 */
async function transactionExample(): Promise<void> {
  const repository = new Repository('ArticleEntity')

  // 基本事务
  const result = await repository.transaction(async () => {
    const article1 = await createArticle('事务文章1', '内容1', 1)
    if (!article1.success) {
      throw new Error('创建文章1失败')
    }

    const article2 = await createArticle('事务文章2', '内容2', 1)
    if (!article2.success) {
      throw new Error('创建文章2失败')
    }
  })

  if (result.success) {
    console.info('事务执行成功')
  } else {
    console.error(`事务执行失败: ${result.errorMessage}`)
  }
}

/**
 * 带配置的事务示例
 */
async function transactionWithOptionsExample(): Promise<void> {
  const repository = new Repository('ArticleEntity')

  // 创建默认配置
  const defaultOptions = TransactionOptions.createDefault()
  console.info(`默认超时: ${defaultOptions.timeout}ms`)

  // 只读事务
  const readOnlyOptions = TransactionOptions.readOnly()
  console.info(`只读模式: ${readOnlyOptions.readOnly}`)

  // 带重试的事务
  const retryOptions = TransactionOptions.withRetry(3, 200)
  console.info(`重试次数: ${retryOptions.retries}, 重试延迟: ${retryOptions.retryDelay}ms`)

  // 自定义配置
  const txConfig = new TxOptionsConfig()
  txConfig.isolation = IsolationLevel.SERIALIZABLE
  txConfig.timeout = 5000
  txConfig.retries = 2
  txConfig.retryDelay = 100
  txConfig.readOnly = false
  const customOptions = TransactionOptions.fromConfig(txConfig)

  // 执行带配置的事务
  const result = await repository.transactionWithOptions(async () => {
    await createArticle('配置事务文章', '内容', 1)
  }, customOptions)

  console.info(`事务结果: ${result.success}`)
}

// ============================================
// 导出示例函数
// ============================================

export {
  initializeORM,
  createArticle,
  findArticleById,
  findAllArticles,
  updateArticle,
  deleteArticle,
  basicQueryExamples,
  paginationExample,
  softDeleteExample,
  countExample,
  transactionExample,
  transactionWithOptionsExample
}
