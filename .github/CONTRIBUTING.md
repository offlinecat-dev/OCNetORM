# 贡献指南

感谢你对 OCORM 的关注！我们欢迎各种形式的贡献。

## 如何贡献

### 报告 Bug

1. 在 [Issues](https://github.com/offlinecat-dev/OCNetORM/issues) 中搜索是否已存在相同问题
2. 如果没有，请创建新 Issue，使用 Bug 报告模板
3. 提供详细的复现步骤、预期行为和实际行为

### 功能建议

1. 在 Issues 中搜索是否已有相同建议
2. 创建新 Issue，使用功能请求模板
3. 清晰描述功能需求和使用场景

### 提交代码

#### 1. Fork 仓库

```bash
git clone https://github.com/YOUR_USERNAME/OCNetORM.git
cd OCORM
```

#### 2. 创建分支

```bash
git checkout -b feature/your-feature-name
# 或
git checkout -b fix/your-bug-fix
```

分支命名规范：
- `feature/xxx` - 新功能
- `fix/xxx` - Bug 修复
- `docs/xxx` - 文档更新
- `refactor/xxx` - 代码重构

#### 3. 编写代码

请遵循以下规范：

**代码风格**
- 使用 2 空格缩进
- 使用 TypeScript 严格模式
- 遵循 ArkTS 类型系统约束
- 变量和函数使用 camelCase
- 类名使用 PascalCase
- 常量使用 UPPER_SNAKE_CASE

**提交信息规范**

```
<type>(<scope>): <subject>

<body>
```

类型（type）：
- `feat`: 新功能
- `fix`: Bug 修复
- `docs`: 文档更新
- `style`: 代码格式调整
- `refactor`: 重构
- `test`: 测试相关
- `chore`: 构建/工具变更

示例：
```
feat(repository): 添加批量更新方法

- 新增 updateMany 方法
- 支持条件批量更新
- 添加单元测试
```

#### 4. 测试

确保所有测试通过：

```bash
# 运行单元测试
hvigorw test
```

#### 5. 提交 PR

1. Push 你的分支到 GitHub
2. 创建 Pull Request，使用 PR 模板
3. 等待代码审查
4. 根据反馈进行修改

## 开发环境

### 环境要求

- DevEco Studio 5.0+
- HarmonyOS SDK API 17+
- Node.js 18+

### 本地开发

```bash
# 安装依赖
ohpm install

# 构建
hvigorw assembleHar

# 运行测试
hvigorw test
```

## 项目结构

```
OCORM/
├── src/main/ets/
│   ├── core/           # 核心功能
│   ├── decorators/     # 装饰器相关
│   ├── query/          # 查询构建器
│   ├── repository/     # Repository 实现
│   ├── schema/         # Schema 相关
│   └── utils/          # 工具函数
├── src/test/           # 单元测试
└── docs/               # 文档
```

## 行为准则

参与本项目即表示你同意遵守我们的 [行为准则](CODE_OF_CONDUCT.md)。

## 问题？

如有任何问题，欢迎在 [Discussions](https://github.com/offlinecat-dev/OCNetORM/discussions) 中讨论。

---

再次感谢你的贡献！🎉
