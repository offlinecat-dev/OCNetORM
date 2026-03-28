# 02-实体与建模

## 何时用
需要定义实体字段、关系和默认过滤规则时。

## 怎么用
优先使用 `defineEntity`；需要类模型时再选择装饰器方式。

- [01-实体模型与元数据](./01-实体模型与元数据.md)
- [02-defineEntity与EntitySchema](./02-defineEntity与EntitySchema.md)
- [03-装饰器建模方式](./03-装饰器建模方式.md)
- [04-关系元数据](./04-关系元数据-Relation-ManyToMany-MorphTo.md)
- [05-ScopeRegistry与作用域](./05-ScopeRegistry与作用域.md)

## 常见误用
同一实体混用多套建模方式导致配置冲突。
