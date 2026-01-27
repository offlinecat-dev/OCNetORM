/**
 * 映射层模块统一导出
 */

// 类型转换器
export { TypeConverter } from './TypeConverter'

// 数据映射器
export {
  ValuesBucket,
  EntityPropertyValue,
  RelatedDataValue,
  EntityData,
  ResultSetRow,
  DataMapper
} from './DataMapper'

// 实体数据输入
export { EntityDataInput } from './EntityDataInput'

// 泛型实体数据
export { TypedEntityData } from './TypedEntityData'

// ViewModel 映射器
export {
  PropertyMapper,
  ReversePropertyMapper,
  ViewModelFactory,
  ViewModelMappingConfig,
  ViewModelMapper
} from './ViewModelMapper'

// ResultSet 工具类
export { ResultSetUtils } from './ResultSetUtils'
