# 05-映射与数据转换

本目录说明 `EntityData`、`DataMapper`、`TypeConverter` 等公开能力在业务代码中的正确用法。

推荐阅读顺序：
1. `01-EntityData与TypedEntityData.md`
2. `02-DataMapper映射流程.md`
3. `03-TypeConverter严格与宽松模式.md`
4. `04-ResultSetRow与ResultSetUtils.md`
5. `05-ViewModelMapper双向映射.md`

重点约束：
- 以实体定义为映射边界，不依赖隐式字段。
- 类型转换失败按错误语义处理，不做静默吞错。


