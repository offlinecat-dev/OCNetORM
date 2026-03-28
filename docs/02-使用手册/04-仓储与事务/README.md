# 04-仓储与事务

本目录面向库使用者，聚焦公开 API 的事务与写入语义，不要求阅读源码。

推荐阅读顺序：
1. `00-Repository总览.md`
2. `01-CRUD与保存语义.md`
3. `03-事务选项-TransactionOptions.md`
4. `05-事务守卫-嵌套-跨仓库-未绑定写入.md`
5. `06-rawQuery-rawQuerySafe-rawExecute.md`

重点约束：
- 事务回调里只用 `txRepo`。
- 原生 SQL 必须参数化。
- 写入失败在事务路径会升级为异常并触发回滚。


