# 查询安全守卫（QueryBuilderGuards）

## 何时用
使用 `selectRaw`、`having`、`orderBy` 等高风险入口时。

## 怎么用
遵循参数化和白名单规则，避免拼接表达式。

关键规则：
- `having` 使用 `?` 占位并传入参数数组。
- `orderBy` 方向仅允许 `ASC` 或 `DESC`。
- `selectRaw` 仅使用受控表达式。

## 常见误用
把 guard 当作可关闭开关，直接传入拼接字符串。
