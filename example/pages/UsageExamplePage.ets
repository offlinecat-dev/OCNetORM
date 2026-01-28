/**
 * OCORM 使用示例页面
 * ArkUI 图形界面演示 ORM 框架的各种功能
 * 符合 ArkTS 严格类型规范
 */

import {
  OCORMInit,
  OCORMInitOptions,
  DatabaseConfig,
  LogLevel,
  MetadataStorage,
  ColumnMetadata,
  ColumnType,
  Repository,
  EntityData,
  QueryExecutor
} from 'ocorm'
import { relationalStore } from '@kit.ArkData'

// ============================================
// OCORMInitOptions 实现类
// ============================================

class InitOptions implements OCORMInitOptions {
  config: DatabaseConfig
  autoCreateTables: boolean = true

  constructor(config: DatabaseConfig) {
    this.config = config
  }
}

// ============================================
// 注册实体
// ============================================

function registerArticleEntity(): void {
  const storage = MetadataStorage.getInstance()
  storage.registerEntity('ArticleEntity', 'articles')

  const idColumn = new ColumnMetadata('id', 'id')
  idColumn.setType(ColumnType.INTEGER)
  idColumn.setPrimaryKey(true)
  idColumn.setAutoIncrement(true)
  storage.registerColumn('ArticleEntity', idColumn)

  const titleColumn = new ColumnMetadata('title', 'title')
  titleColumn.setType(ColumnType.TEXT)
  titleColumn.setNullable(false)
  storage.registerColumn('ArticleEntity', titleColumn)

  const contentColumn = new ColumnMetadata('content', 'content')
  contentColumn.setType(ColumnType.TEXT)
  contentColumn.setNullable(true)
  storage.registerColumn('ArticleEntity', contentColumn)

  const viewCountColumn = new ColumnMetadata('viewCount', 'view_count')
  viewCountColumn.setType(ColumnType.INTEGER)
  viewCountColumn.setDefaultValue(0)
  storage.registerColumn('ArticleEntity', viewCountColumn)

  const createdAtColumn = new ColumnMetadata('createdAt', 'created_at')
  createdAtColumn.setType(ColumnType.INTEGER)
  createdAtColumn.setNullable(false)
  storage.registerColumn('ArticleEntity', createdAtColumn)

  const updatedAtColumn = new ColumnMetadata('updatedAt', 'updated_at')
  updatedAtColumn.setType(ColumnType.INTEGER)
  updatedAtColumn.setNullable(false)
  storage.registerColumn('ArticleEntity', updatedAtColumn)

  const deletedAtColumn = new ColumnMetadata('deletedAt', 'deleted_at')
  deletedAtColumn.setType(ColumnType.INTEGER)
  deletedAtColumn.setNullable(true)
  storage.registerColumn('ArticleEntity', deletedAtColumn)

  const metadata = storage.getEntityMetadata('ArticleEntity')
  if (metadata !== null) {
    metadata.setSoftDelete(true, 'deleted_at')
  }
}

// ============================================
// 文章数据模型
// ============================================

class ArticleItem {
  id: number = 0
  title: string = ''
  content: string = ''
  viewCount: number = 0
  createdAt: number = 0

  constructor(id: number, title: string, content: string, viewCount: number, createdAt: number) {
    this.id = id
    this.title = title
    this.content = content
    this.viewCount = viewCount
    this.createdAt = createdAt
  }
}

@Entry
@Component
struct UsageExamplePage {
  @State isInitialized: boolean = false
  @State isLoading: boolean = false
  @State message: string = '点击"初始化数据库"开始'
  @State articles: ArticleItem[] = []
  @State newTitle: string = ''
  @State newContent: string = ''
  @State articleCount: number = 0

  // 初始化数据库
  async initDatabase(): Promise<void> {
    this.isLoading = true
    this.message = '正在初始化数据库...'

    try {
      // 注册实体
      registerArticleEntity()

      // 创建数据库配置
      const config = new DatabaseConfig(
        'ocorm_example.db',
        relationalStore.SecurityLevel.S1,
        false,
        true,
        LogLevel.DEBUG
      )

      // 初始化 OCORM
      const initOptions = new InitOptions(config)
      await OCORMInit(getContext(this), initOptions)

      this.isInitialized = true
      this.message = '数据库初始化成功！'
      await this.refreshArticles()
    } catch (error) {
      this.message = `初始化失败: ${error instanceof Error ? error.message : String(error)}`
    } finally {
      this.isLoading = false
    }
  }

  // 创建文章
  async createArticle(): Promise<void> {
    if (!this.newTitle.trim()) {
      this.message = '请输入文章标题'
      return
    }

    this.isLoading = true
    try {
      const repository = new Repository('ArticleEntity')
      const articleData = new EntityData('ArticleEntity')
      articleData.addProperty('title', this.newTitle, 'string')
      articleData.addProperty('content', this.newContent || '暂无内容', 'string')
      articleData.addProperty('viewCount', 0, 'number')
      articleData.addProperty('createdAt', Date.now(), 'number')
      articleData.addProperty('updatedAt', Date.now(), 'number')

      const result = await repository.save(articleData)
      if (result.success) {
        this.message = `创建成功！ID: ${result.insertId}`
        this.newTitle = ''
        this.newContent = ''
        await this.refreshArticles()
      } else {
        this.message = `创建失败: ${result.errorMessage}`
      }
    } catch (error) {
      this.message = `创建失败: ${error instanceof Error ? error.message : String(error)}`
    } finally {
      this.isLoading = false
    }
  }

  // 刷新文章列表
  async refreshArticles(): Promise<void> {
    try {
      const repository = new Repository('ArticleEntity')
      const allArticles = await repository.findAll()

      this.articles = allArticles.map((item): ArticleItem => {
        return new ArticleItem(
          item.getPropertyValue('id') as number,
          item.getPropertyValue('title') as string,
          item.getPropertyValue('content') as string,
          item.getPropertyValue('viewCount') as number,
          item.getPropertyValue('createdAt') as number
        )
      })

      this.articleCount = await repository.count()
    } catch (error) {
      this.message = `刷新失败: ${error instanceof Error ? error.message : String(error)}`
    }
  }

  // 删除文章
  async deleteArticle(id: number): Promise<void> {
    this.isLoading = true
    try {
      const repository = new Repository('ArticleEntity')
      const result = await repository.removeById(id)
      if (result.success) {
        this.message = `删除成功！`
        await this.refreshArticles()
      } else {
        this.message = `删除失败: ${result.errorMessage}`
      }
    } catch (error) {
      this.message = `删除失败: ${error instanceof Error ? error.message : String(error)}`
    } finally {
      this.isLoading = false
    }
  }

  // 查询示例
  async queryExample(): Promise<void> {
    this.isLoading = true
    try {
      const repository = new Repository('ArticleEntity')
      const queryBuilder = repository.createQueryBuilder()
        .orderBy('createdAt', 'DESC')
        .limit(5)

      const executor = new QueryExecutor(queryBuilder)
      const results = await executor.get()
      this.message = `查询到 ${results.length} 条最新文章`
    } catch (error) {
      this.message = `查询失败: ${error instanceof Error ? error.message : String(error)}`
    } finally {
      this.isLoading = false
    }
  }

  // 格式化时间
  formatTime(timestamp: number): string {
    const date = new Date(timestamp)
    return `${date.getMonth() + 1}/${date.getDate()} ${date.getHours()}:${date.getMinutes().toString().padStart(2, '0')}`
  }

  build() {
    Column() {
      // 标题
      Text('OCORM 示例')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 16 })

      // 状态消息
      Text(this.message)
        .fontSize(14)
        .fontColor(this.message.includes('失败') ? '#F44336' : '#4CAF50')
        .margin({ bottom: 16 })
        .textAlign(TextAlign.Center)

      // 初始化按钮
      if (!this.isInitialized) {
        Button('初始化数据库')
          .width('80%')
          .height(48)
          .fontSize(16)
          .enabled(!this.isLoading)
          .onClick(() => this.initDatabase())
      } else {
        // 创建文章区域
        Column() {
          Text('创建文章')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .margin({ bottom: 8 })

          TextInput({ placeholder: '文章标题', text: this.newTitle })
            .width('100%')
            .height(44)
            .margin({ bottom: 8 })
            .backgroundColor('#FFFFFF')
            .borderRadius(4)
            .padding({ left: 12, right: 12 })
            .fontColor('#333333')
            .placeholderColor('#999999')
            .onChange((value: string) => this.newTitle = value)

          TextInput({ placeholder: '文章内容（可选）', text: this.newContent })
            .width('100%')
            .height(44)
            .margin({ bottom: 8 })
            .backgroundColor('#FFFFFF')
            .borderRadius(4)
            .padding({ left: 12, right: 12 })
            .fontColor('#333333')
            .placeholderColor('#999999')
            .onChange((value: string) => this.newContent = value)

          Row() {
            Button('创建')
              .width('45%')
              .height(40)
              .enabled(!this.isLoading)
              .onClick(() => this.createArticle())

            Button('查询示例')
              .width('45%')
              .height(40)
              .backgroundColor('#2196F3')
              .enabled(!this.isLoading)
              .onClick(() => this.queryExample())
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)
        }
        .width('90%')
        .padding(16)
        .backgroundColor('#F5F5F5')
        .borderRadius(8)
        .margin({ bottom: 16 })

        // 文章统计
        Text(`文章总数: ${this.articleCount}`)
          .fontSize(14)
          .fontColor('#666')
          .margin({ bottom: 8 })

        // 文章列表
        if (this.articles.length > 0) {
          List() {
            ForEach(this.articles, (article: ArticleItem) => {
              ListItem() {
                Row() {
                  Column() {
                    Text(article.title)
                      .fontSize(16)
                      .fontWeight(FontWeight.Medium)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })

                    Text(article.content)
                      .fontSize(12)
                      .fontColor('#888')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .margin({ top: 4 })

                    Text(`ID: ${article.id} | ${this.formatTime(article.createdAt)}`)
                      .fontSize(10)
                      .fontColor('#AAA')
                      .margin({ top: 4 })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  Button('删除')
                    .width(60)
                    .height(32)
                    .fontSize(12)
                    .backgroundColor('#F44336')
                    .onClick(() => this.deleteArticle(article.id))
                }
                .width('100%')
                .padding(12)
                .backgroundColor('#FFFFFF')
                .borderRadius(8)
              }
              .margin({ bottom: 8 })
            }, (article: ArticleItem) => article.id.toString())
          }
          .width('90%')
          .layoutWeight(1)
        } else {
          Text('暂无文章，请先创建')
            .fontSize(14)
            .fontColor('#999')
            .margin({ top: 32 })
        }

        // 刷新按钮
        Button('刷新列表')
          .width('80%')
          .height(40)
          .backgroundColor('#9E9E9E')
          .margin({ top: 16 })
          .enabled(!this.isLoading)
          .onClick(() => this.refreshArticles())
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: 48, bottom: 24 })
    .backgroundColor('#FAFAFA')
  }
}
