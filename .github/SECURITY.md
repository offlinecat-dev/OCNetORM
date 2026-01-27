# 安全政策

## 支持的版本

以下版本目前接受安全更新：

| 版本 | 支持状态 |
|------|---------|
| 2.4.x | ✅ 支持 |
| 2.3.x | ✅ 支持 |
| 2.2.x | ⚠️ 仅安全更新 |
| < 2.2 | ❌ 不再支持 |

## 报告漏洞

我们非常重视安全问题。如果你发现了安全漏洞，请按以下步骤报告：

### ⚠️ 请勿公开披露

**请不要**在 GitHub Issues 或其他公开渠道报告安全漏洞。

### 报告方式

1. **GitHub Security Advisory**（推荐）
   - 前往 [Security Advisories](https://github.com/offlinecat-dev/OCNetORM/security/advisories)
   - 点击 "Report a vulnerability"

2. **Email**
   - 发送邮件至：offlinecat-dev@example.com
   - 邮件主题请标注：`[SECURITY] 漏洞报告`

### 报告内容

请在报告中包含以下信息：

- **漏洞类型**：如 SQL 注入、数据泄露等
- **受影响版本**：哪些版本受到影响
- **复现步骤**：详细的复现流程
- **影响范围**：潜在的安全影响
- **建议修复方案**：如果有的话

### 示例报告

```
漏洞类型：SQL 注入
受影响版本：2.1.0 - 2.1.15
复现步骤：
1. 调用 QueryBuilder.where() 方法
2. 传入未经处理的用户输入 "1' OR '1'='1"
3. 执行查询
影响范围：可能导致未授权数据访问
```

## 响应流程

| 时间 | 动作 |
|-----|------|
| 24 小时内 | 确认收到报告 |
| 72 小时内 | 初步评估和分类 |
| 7 天内 | 修复方案确定 |
| 14 天内 | 发布安全补丁 |

## 安全更新

安全更新将通过以下方式发布：

1. **GitHub Releases** - 发布新版本
2. **Security Advisory** - 发布安全公告
3. **CHANGELOG** - 记录安全修复

## 安全最佳实践

使用 OCORM 时，请遵循以下安全建议：

### 数据库安全

```typescript
// ✅ 推荐：使用参数化查询
const users = await repo.createQueryBuilder()
  .where('email', ConditionOperator.EQUAL, userInput)
  .getMany()

// ❌ 避免：直接拼接 SQL（OCORM 已内置防护）
```

### 敏感数据

```typescript
// ✅ 推荐：使用适当的安全级别
const config = new DatabaseConfig(
  'app.db',
  relationalStore.SecurityLevel.S3,  // 敏感数据使用高安全级别
  true  // 启用加密
)
```

## 致谢

感谢所有帮助提高 OCORM 安全性的安全研究人员。

---

**安全是我们的首要任务** 🔒
