/**
 * 关联数据加载器
 * 负责执行关联数据的二次查询加载
 */

import { relationalStore } from '@kit.ArkData'
import { MetadataStorage } from '../core/MetadataStorage'
import { RelationMetadata } from '../core/RelationMetadata'
import { ManyToManyMetadata } from '../core/ManyToManyMetadata'
import { EntityMetadata } from '../core/EntityMetadata'
import { RelationType } from '../types/RelationType'
import { DataMapper, EntityData, ResultSetRow } from '../mapping/DataMapper'
import { DatabaseManager } from '../database/DatabaseManager'
import { ValueType } from '../types/ValueTypes'
import { RelationNotFoundError } from '../errors/RelationError'
import { ExecutionError } from '../errors/DatabaseError'
import { ColumnType } from '../types/ColumnType'
import { RelationLoadResult, ParallelRelationLoadResult } from './RelationLoadResult'
import { Logger } from '../logging/Logger'
import { ResultSetUtils } from '../mapping/ResultSetUtils'

/**
 * 关联数据加载器类
 * 使用应用层二次查询策略加载关联数据
 */
export class RelationLoader {
  /** 源实体名称 */
  private sourceEntityName: string

  /** IN 条件参数数量限制（SQLite 默认限制为 999，保守设置为 500） */
  private static readonly IN_CLAUSE_LIMIT: number = 500

  /**
   * 构造函数
   * @param sourceEntityName 源实体名称
   */
  constructor(sourceEntityName: string) {
    this.sourceEntityName = sourceEntityName
  }

  /**
   * 将数组分批处理
   * @param values 原始数组
   * @param batchSize 每批大小
   * @returns 分批后的二维数组
   */
  private splitIntoBatches<T>(values: Array<T>, batchSize: number): Array<Array<T>> {
    const batches: Array<Array<T>> = []
    for (let i = 0; i < values.length; i += batchSize) {
      const batch: Array<T> = []
      for (let j = i; j < Math.min(i + batchSize, values.length); j++) {
        batch.push(values[j])
      }
      batches.push(batch)
    }
    return batches
  }

  /**
   * 获取 RdbStore 实例
   * @returns RdbStore 实例
   * @throws ExecutionError 如果数据库未初始化
   */
  private getStore(): relationalStore.RdbStore {
    try {
      return DatabaseManager.getInstance().getStore()
    } catch (e) {
      const errorMessage = e instanceof Error ? e.message : String(e)
      throw new ExecutionError('DATABASE', errorMessage)
    }
  }

  /**
   * 加载关联数据
   * @param entities 主实体数据数组
   * @param relationName 关联属性名
   * @returns 带有关联数据的实体数组
   * @throws RelationNotFoundError 如果关联关系未注册
   */
  async loadRelation(
    entities: Array<EntityData>,
    relationName: string
  ): Promise<Array<EntityData>> {
    if (entities.length === 0) {
      return entities
    }

    // 获取关联关系元数据
    const relation = MetadataStorage.getInstance().getRelation(this.sourceEntityName, relationName)
    if (relation === null) {
      throw new RelationNotFoundError(this.sourceEntityName, relationName)
    }

    // 根据关系类型执行不同的加载策略
    if (relation.type === RelationType.ONE_TO_ONE) {
      return await this.loadOneToOne(entities, relation)
    } else if (relation.type === RelationType.ONE_TO_MANY) {
      return await this.loadOneToMany(entities, relation)
    } else if (relation.type === RelationType.MANY_TO_ONE) {
      return await this.loadManyToOne(entities, relation)
    } else if (relation.type === RelationType.MANY_TO_MANY) {
      return await this.loadManyToMany(entities, relation as ManyToManyMetadata)
    }

    return entities
  }

  /**
   * 并行加载多个关联数据
   * 使用 Promise.all 并行执行多个关联的加载
   * @param entities 主实体数据数组
   * @param relationNames 关联属性名数组
   * @returns 带有所有关联数据的实体数组
   */
  async loadRelationsParallel(
    entities: Array<EntityData>,
    relationNames: Array<string>
  ): Promise<Array<EntityData>> {
    if (entities.length === 0 || relationNames.length === 0) {
      return entities
    }

    const startTime = Date.now()
    const logger = Logger.getInstance()

    // 如果只有一个关联，直接调用单个加载方法
    if (relationNames.length === 1) {
      try {
        const result = await this.loadRelation(entities, relationNames[0])
        const duration = Date.now() - startTime
        logger.logDebug(`并行关联加载完成: 1 个关联, 耗时 ${duration}ms`)
        return result
      } catch (e) {
        const error = e instanceof Error ? e : new Error(String(e))
        logger.logInfo(`关联 '${relationNames[0]}' 加载失败: ${error.message}`)
        return entities
      }
    }

    // 创建并行加载任务
    const loadTasks: Array<Promise<RelationLoadResult>> = []

    for (let i = 0; i < relationNames.length; i++) {
      const relationName = relationNames[i]
      const task = this.loadRelationWithResult(entities, relationName)
      loadTasks.push(task)
    }

    // 并行执行所有加载任务
    const results = await Promise.all(loadTasks)

    // 统计结果
    const parallelResult = new ParallelRelationLoadResult()
    parallelResult.totalDuration = Date.now() - startTime

    let successCount = 0
    let failureCount = 0

    for (let i = 0; i < results.length; i++) {
      parallelResult.addResult(results[i])
      if (results[i].success) {
        successCount++
      } else {
        failureCount++
        // 记录失败的关联
        logger.logInfo(`关联 '${results[i].relationName}' 加载失败: ${results[i].errorMessage}`)
      }
    }

    // 记录并行加载日志
    logger.logDebug(`并行关联加载完成: ${relationNames.length} 个关联, 成功 ${successCount}, 失败 ${failureCount}, 总耗时 ${parallelResult.totalDuration}ms`)

    return entities
  }

  /**
   * 加载单个关联并返回结果对象
   * 用于并行加载时收集每个关联的加载结果
   * @param entities 主实体数据数组
   * @param relationName 关联属性名
   * @returns 关联加载结果
   */
  private async loadRelationWithResult(
    entities: Array<EntityData>,
    relationName: string
  ): Promise<RelationLoadResult> {
    const startTime = Date.now()

    try {
      // 获取关联关系元数据
      const relation = MetadataStorage.getInstance().getRelation(this.sourceEntityName, relationName)
      if (relation === null) {
        const duration = Date.now() - startTime
        return RelationLoadResult.createFailure(relationName, `关联 '${relationName}' 未注册`, duration)
      }

      // 根据关系类型执行不同的加载策略
      let loadedCount = 0
      if (relation.type === RelationType.ONE_TO_ONE) {
        await this.loadOneToOne(entities, relation)
        // 统计加载的关联数据数量
        for (let i = 0; i < entities.length; i++) {
          const relatedData = entities[i].getRelatedSingle(relationName)
          if (relatedData !== null) {
            loadedCount++
          }
        }
      } else if (relation.type === RelationType.ONE_TO_MANY) {
        await this.loadOneToMany(entities, relation)
        // 统计加载的关联数据数量
        for (let i = 0; i < entities.length; i++) {
          const relatedData = entities[i].getRelatedArray(relationName)
          if (relatedData !== null) {
            loadedCount += relatedData.length
          }
        }
      } else if (relation.type === RelationType.MANY_TO_ONE) {
        await this.loadManyToOne(entities, relation)
        // 统计加载的关联数据数量
        for (let i = 0; i < entities.length; i++) {
          const relatedData = entities[i].getRelatedSingle(relationName)
          if (relatedData !== null) {
            loadedCount++
          }
        }
      } else if (relation.type === RelationType.MANY_TO_MANY) {
        await this.loadManyToMany(entities, relation as ManyToManyMetadata)
        // 统计加载的关联数据数量
        for (let i = 0; i < entities.length; i++) {
          const relatedData = entities[i].getRelatedArray(relationName)
          if (relatedData !== null) {
            loadedCount += relatedData.length
          }
        }
      }

      const duration = Date.now() - startTime
      return RelationLoadResult.createSuccess(relationName, loadedCount, duration)
    } catch (e) {
      const duration = Date.now() - startTime
      const errorMessage = e instanceof Error ? e.message : String(e)
      return RelationLoadResult.createFailure(relationName, errorMessage, duration)
    }
  }

  /**
   * 加载 ONE_TO_MANY 关联数据
   * 根据主实体的主键值查询关联实体列表
   * @param entities 主实体数据数组
   * @param relation 关联关系元数据
   * @returns 带有关联数据的实体数组
   */
  private async loadOneToMany(
    entities: Array<EntityData>,
    relation: RelationMetadata
  ): Promise<Array<EntityData>> {
    // 获取源实体的主键列
    const sourceMetadata = MetadataStorage.getInstance().getEntityMetadata(this.sourceEntityName)
    if (sourceMetadata === null) {
      return entities
    }

    const sourcePkColumn = sourceMetadata.getPrimaryKeyColumn()
    if (sourcePkColumn === null) {
      return entities
    }

    // 收集所有主实体的主键值
    const pkValues: Array<ValueType> = []
    const pkValueToEntities: Map<string, Array<EntityData>> = new Map()

    for (let i = 0; i < entities.length; i++) {
      const entity = entities[i]
      const pkProp = entity.getProperty(sourcePkColumn.propertyName)
      if (pkProp !== null && pkProp.value !== null) {
        const pkKey = String(pkProp.value)
        pkValues.push(pkProp.value)

        // 建立主键值到实体的映射（可能有多个实体有相同主键，虽然不常见）
        let entityList = pkValueToEntities.get(pkKey)
        if (!entityList) {
          entityList = []
          pkValueToEntities.set(pkKey, entityList)
        }
        entityList.push(entity)
      }
    }

    if (pkValues.length === 0) {
      return entities
    }

    // 获取目标实体元数据
    const targetMetadata = MetadataStorage.getInstance().getEntityMetadata(relation.targetEntity)
    if (targetMetadata === null) {
      return entities
    }

    // 查询关联数据：SELECT * FROM target_table WHERE inverseKey IN (pkValues)
    let store: relationalStore.RdbStore
    try {
      store = this.getStore()
    } catch (e) {
      // 数据库未初始化，返回原实体
      return entities
    }

    const targetMapper = new DataMapper(relation.targetEntity)

    // 将关联数据按外键值分组
    const relatedByFk: Map<string, Array<EntityData>> = new Map()

    // 分批处理 IN 条件，避免超出 SQLite 参数限制
    const batches = this.splitIntoBatches(pkValues, RelationLoader.IN_CLAUSE_LIMIT)

    for (let batchIndex = 0; batchIndex < batches.length; batchIndex++) {
      const batch = batches[batchIndex]
      const predicates = new relationalStore.RdbPredicates(targetMetadata.tableName)
      this.applySoftDeleteToPredicates(predicates, targetMetadata)

      // 构建 IN 条件
      const rdbValues: Array<relationalStore.ValueType> = []
      for (let i = 0; i < batch.length; i++) {
        rdbValues.push(this.toRdbValue(batch[i]))
      }
      try {
        predicates.in(relation.inverseKey, rdbValues)
      } catch (e) {
        // 构建条件失败，继续下一批
        continue
      }

      let resultSet: relationalStore.ResultSet
      try {
        resultSet = await store.query(predicates)
      } catch (e) {
        // 查询失败，继续下一批
        continue
      }

      try {
        while (resultSet.goToNextRow()) {
          const row = this.resultSetToRow(resultSet, targetMetadata)
          const relatedEntity = targetMapper.fromResultSetRow(row)

          // 获取外键值
          const fkProp = relatedEntity.getProperty(relation.inverseKey)
          // 如果属性名找不到，尝试通过列名查找
          let fkValue: ValueType = null
          if (fkProp !== null) {
            fkValue = fkProp.value
          } else {
            // 尝试通过列名获取
            const fkColumn = targetMetadata.getColumnByName(relation.inverseKey)
            if (fkColumn !== null) {
              const fkPropByColumn = relatedEntity.getProperty(fkColumn.propertyName)
              if (fkPropByColumn !== null) {
                fkValue = fkPropByColumn.value
              }
            }
          }

          if (fkValue !== null) {
            const fkKey = String(fkValue)
            let relatedList = relatedByFk.get(fkKey)
            if (!relatedList) {
              relatedList = []
              relatedByFk.set(fkKey, relatedList)
            }
            relatedList.push(relatedEntity)
          }
        }
      } catch (e) {
        // 遍历结果集失败，忽略
      }

      try {
        resultSet.close()
      } catch (e) {
        // 关闭失败，忽略
      }
    }

    // 将关联数据设置到主实体
    for (let i = 0; i < entities.length; i++) {
      const entity = entities[i]
      const pkProp = entity.getProperty(sourcePkColumn.propertyName)
      if (pkProp !== null && pkProp.value !== null) {
        const pkKey = String(pkProp.value)
        const relatedEntities = relatedByFk.get(pkKey)
        if (relatedEntities) {
          entity.setRelatedArray(relation.propertyName, relatedEntities)
        } else {
          entity.setRelatedArray(relation.propertyName, [])
        }
      }
    }

    return entities
  }

  /**
   * 加载 MANY_TO_ONE 关联数据
   * 根据外键值查询单个关联实体
   * @param entities 主实体数据数组
   * @param relation 关联关系元数据
   * @returns 带有关联数据的实体数组
   */
  private async loadManyToOne(
    entities: Array<EntityData>,
    relation: RelationMetadata
  ): Promise<Array<EntityData>> {
    // 获取目标实体元数据
    const targetMetadata = MetadataStorage.getInstance().getEntityMetadata(relation.targetEntity)
    if (targetMetadata === null) {
      return entities
    }

    const targetPkColumn = targetMetadata.getPrimaryKeyColumn()
    if (targetPkColumn === null) {
      return entities
    }

    // 获取源实体元数据
    const sourceMetadata = MetadataStorage.getInstance().getEntityMetadata(this.sourceEntityName)
    if (sourceMetadata === null) {
      return entities
    }

    // 收集所有主实体的外键值
    const fkValues: Array<ValueType> = []
    const fkValueSet: Set<string> = new Set()

    for (let i = 0; i < entities.length; i++) {
      const entity = entities[i]
      // 尝试通过属性名获取外键值
      let fkProp = entity.getProperty(relation.inverseKey)
      // 如果属性名找不到，尝试通过列名查找
      if (fkProp === null) {
        const fkColumn = sourceMetadata.getColumnByName(relation.inverseKey)
        if (fkColumn !== null) {
          fkProp = entity.getProperty(fkColumn.propertyName)
        }
      }

      if (fkProp !== null && fkProp.value !== null) {
        const fkKey = String(fkProp.value)
        if (!fkValueSet.has(fkKey)) {
          fkValueSet.add(fkKey)
          fkValues.push(fkProp.value)
        }
      }
    }

    if (fkValues.length === 0) {
      // 没有外键值，设置所有关联为 null
      for (let i = 0; i < entities.length; i++) {
        entities[i].setRelatedSingle(relation.propertyName, null)
      }
      return entities
    }

    // 查询关联数据：SELECT * FROM target_table WHERE pk IN (fkValues)
    let store: relationalStore.RdbStore
    try {
      store = this.getStore()
    } catch (e) {
      // 数据库未初始化，设置所有关联为 null
      for (let i = 0; i < entities.length; i++) {
        entities[i].setRelatedSingle(relation.propertyName, null)
      }
      return entities
    }

    const targetMapper = new DataMapper(relation.targetEntity)

    // 将关联数据按主键值索引
    const relatedByPk: Map<string, EntityData> = new Map()

    // 分批处理 IN 条件，避免超出 SQLite 参数限制
    const fkBatches = this.splitIntoBatches(fkValues, RelationLoader.IN_CLAUSE_LIMIT)

    for (let batchIndex = 0; batchIndex < fkBatches.length; batchIndex++) {
      const batch = fkBatches[batchIndex]
      const predicates = new relationalStore.RdbPredicates(targetMetadata.tableName)
      this.applySoftDeleteToPredicates(predicates, targetMetadata)

      // 构建 IN 条件
      const rdbValues: Array<relationalStore.ValueType> = []
      for (let i = 0; i < batch.length; i++) {
        rdbValues.push(this.toRdbValue(batch[i]))
      }
      try {
        predicates.in(targetPkColumn.columnName, rdbValues)
      } catch (e) {
        // 构建条件失败，继续下一批
        continue
      }

      let resultSet: relationalStore.ResultSet
      try {
        resultSet = await store.query(predicates)
      } catch (e) {
        // 查询失败，继续下一批
        continue
      }

      try {
        while (resultSet.goToNextRow()) {
          const row = this.resultSetToRow(resultSet, targetMetadata)
          const relatedEntity = targetMapper.fromResultSetRow(row)

          // 获取主键值
          const pkProp = relatedEntity.getProperty(targetPkColumn.propertyName)
          if (pkProp !== null && pkProp.value !== null) {
            const pkKey = String(pkProp.value)
            relatedByPk.set(pkKey, relatedEntity)
          }
        }
      } catch (e) {
        // 遍历结果集失败，忽略
      }

      try {
        resultSet.close()
      } catch (e) {
        // 关闭失败，忽略
      }
    }

    // 将关联数据设置到主实体
    for (let i = 0; i < entities.length; i++) {
      const entity = entities[i]
      // 尝试通过属性名获取外键值
      let fkProp = entity.getProperty(relation.inverseKey)
      // 如果属性名找不到，尝试通过列名查找
      if (fkProp === null) {
        const fkColumn = sourceMetadata.getColumnByName(relation.inverseKey)
        if (fkColumn !== null) {
          fkProp = entity.getProperty(fkColumn.propertyName)
        }
      }

      if (fkProp !== null && fkProp.value !== null) {
        const fkKey = String(fkProp.value)
        const relatedEntity = relatedByPk.get(fkKey)
        if (relatedEntity) {
          entity.setRelatedSingle(relation.propertyName, relatedEntity)
        } else {
          entity.setRelatedSingle(relation.propertyName, null)
        }
      } else {
        entity.setRelatedSingle(relation.propertyName, null)
      }
    }

    return entities
  }

  /**
   * 加载 ONE_TO_ONE 关联数据
   * 根据 foreignKeySide 配置选择加载策略：
   * - 'source': 外键在源实体，根据源实体的外键值查询目标实体
   * - 'target': 外键在目标实体，根据目标实体的外键值查询源实体
   * @param entities 主实体数据数组
   * @param relation 关联关系元数据
   * @returns 带有关联数据的实体数组
   */
  private async loadOneToOne(
    entities: Array<EntityData>,
    relation: RelationMetadata
  ): Promise<Array<EntityData>> {
    // 根据 foreignKeySide 选择加载策略
    if (relation.foreignKeySide === 'target') {
      return await this.loadOneToOneTargetSide(entities, relation)
    } else {
      // 默认 'source'：外键在源实体
      return await this.loadOneToOneSourceSide(entities, relation)
    }
  }

  /**
   * 加载 ONE_TO_ONE 关联数据（外键在源实体侧）
   * 根据源实体的外键值查询目标实体
   * @param entities 主实体数据数组
   * @param relation 关联关系元数据
   * @returns 带有关联数据的实体数组
   */
  private async loadOneToOneSourceSide(
    entities: Array<EntityData>,
    relation: RelationMetadata
  ): Promise<Array<EntityData>> {
    // 获取目标实体元数据
    const targetMetadata = MetadataStorage.getInstance().getEntityMetadata(relation.targetEntity)
    if (targetMetadata === null) {
      return entities
    }

    const targetPkColumn = targetMetadata.getPrimaryKeyColumn()
    if (targetPkColumn === null) {
      return entities
    }

    // 获取源实体元数据
    const sourceMetadata = MetadataStorage.getInstance().getEntityMetadata(this.sourceEntityName)
    if (sourceMetadata === null) {
      return entities
    }

    // 收集所有主实体的外键值（去重）
    const fkValues: Array<ValueType> = []
    const fkValueSet: Set<string> = new Set()

    for (let i = 0; i < entities.length; i++) {
      const entity = entities[i]
      // 尝试通过属性名获取外键值
      let fkProp = entity.getProperty(relation.inverseKey)
      // 如果属性名找不到，尝试通过列名查找
      if (fkProp === null) {
        const fkColumn = sourceMetadata.getColumnByName(relation.inverseKey)
        if (fkColumn !== null) {
          fkProp = entity.getProperty(fkColumn.propertyName)
        }
      }

      if (fkProp !== null && fkProp.value !== null) {
        const fkKey = String(fkProp.value)
        if (!fkValueSet.has(fkKey)) {
          fkValueSet.add(fkKey)
          fkValues.push(fkProp.value)
        }
      }
    }

    if (fkValues.length === 0) {
      // 没有外键值，设置所有关联为 null
      for (let i = 0; i < entities.length; i++) {
        entities[i].setRelatedSingle(relation.propertyName, null)
      }
      return entities
    }

    // 查询关联数据：SELECT * FROM target_table WHERE pk IN (fkValues)
    let store: relationalStore.RdbStore
    try {
      store = this.getStore()
    } catch (e) {
      // 数据库未初始化，设置所有关联为 null
      for (let i = 0; i < entities.length; i++) {
        entities[i].setRelatedSingle(relation.propertyName, null)
      }
      return entities
    }

    const predicates = new relationalStore.RdbPredicates(targetMetadata.tableName)
    this.applySoftDeleteToPredicates(predicates, targetMetadata)

    // 构建 IN 条件
    const rdbValues: Array<relationalStore.ValueType> = []
    for (let i = 0; i < fkValues.length; i++) {
      rdbValues.push(this.toRdbValue(fkValues[i]))
    }
    try {
      predicates.in(targetPkColumn.columnName, rdbValues)
    } catch (e) {
      // 构建条件失败，设置所有关联为 null
      for (let i = 0; i < entities.length; i++) {
        entities[i].setRelatedSingle(relation.propertyName, null)
      }
      return entities
    }

    let resultSet: relationalStore.ResultSet
    try {
      resultSet = await store.query(predicates)
    } catch (e) {
      // 查询失败，设置所有关联为 null
      for (let i = 0; i < entities.length; i++) {
        entities[i].setRelatedSingle(relation.propertyName, null)
      }
      return entities
    }

    const targetMapper = new DataMapper(relation.targetEntity)

    // 将关联数据按主键值索引
    const relatedByPk: Map<string, EntityData> = new Map()

    try {
      while (resultSet.goToNextRow()) {
        const row = this.resultSetToRow(resultSet, targetMetadata)
        const relatedEntity = targetMapper.fromResultSetRow(row)

        // 获取主键值
        const pkProp = relatedEntity.getProperty(targetPkColumn.propertyName)
        if (pkProp !== null && pkProp.value !== null) {
          const pkKey = String(pkProp.value)
          relatedByPk.set(pkKey, relatedEntity)
        }
      }
    } catch (e) {
      // 遍历结果集失败，忽略
    }

    try {
      resultSet.close()
    } catch (e) {
      // 关闭失败，忽略
    }

    // 将关联数据设置到主实体
    for (let i = 0; i < entities.length; i++) {
      const entity = entities[i]
      // 尝试通过属性名获取外键值
      let fkProp = entity.getProperty(relation.inverseKey)
      // 如果属性名找不到，尝试通过列名查找
      if (fkProp === null) {
        const fkColumn = sourceMetadata.getColumnByName(relation.inverseKey)
        if (fkColumn !== null) {
          fkProp = entity.getProperty(fkColumn.propertyName)
        }
      }

      if (fkProp !== null && fkProp.value !== null) {
        const fkKey = String(fkProp.value)
        const relatedEntity = relatedByPk.get(fkKey)
        if (relatedEntity) {
          entity.setRelatedSingle(relation.propertyName, relatedEntity)
        } else {
          entity.setRelatedSingle(relation.propertyName, null)
        }
      } else {
        entity.setRelatedSingle(relation.propertyName, null)
      }
    }

    return entities
  }

  /**
   * 加载 ONE_TO_ONE 关联数据（外键在目标实体侧）
   * 根据目标实体的外键值查询源实体
   * @param entities 主实体数据数组
   * @param relation 关联关系元数据
   * @returns 带有关联数据的实体数组
   */
  private async loadOneToOneTargetSide(
    entities: Array<EntityData>,
    relation: RelationMetadata
  ): Promise<Array<EntityData>> {
    // 获取源实体元数据
    const sourceMetadata = MetadataStorage.getInstance().getEntityMetadata(this.sourceEntityName)
    if (sourceMetadata === null) {
      return entities
    }

    const sourcePkColumn = sourceMetadata.getPrimaryKeyColumn()
    if (sourcePkColumn === null) {
      return entities
    }

    // 获取目标实体元数据
    const targetMetadata = MetadataStorage.getInstance().getEntityMetadata(relation.targetEntity)
    if (targetMetadata === null) {
      return entities
    }

    // 收集所有主实体的主键值（去重）
    const pkValues: Array<ValueType> = []
    const pkValueSet: Set<string> = new Set()

    for (let i = 0; i < entities.length; i++) {
      const entity = entities[i]
      const pkProp = entity.getProperty(sourcePkColumn.propertyName)
      if (pkProp !== null && pkProp.value !== null) {
        const pkKey = String(pkProp.value)
        if (!pkValueSet.has(pkKey)) {
          pkValueSet.add(pkKey)
          pkValues.push(pkProp.value)
        }
      }
    }

    if (pkValues.length === 0) {
      // 没有主键值，设置所有关联为 null
      for (let i = 0; i < entities.length; i++) {
        entities[i].setRelatedSingle(relation.propertyName, null)
      }
      return entities
    }

    // 查询关联数据：SELECT * FROM target_table WHERE inverseKey IN (pkValues)
    let store: relationalStore.RdbStore
    try {
      store = this.getStore()
    } catch (e) {
      // 数据库未初始化，设置所有关联为 null
      for (let i = 0; i < entities.length; i++) {
        entities[i].setRelatedSingle(relation.propertyName, null)
      }
      return entities
    }

    const predicates = new relationalStore.RdbPredicates(targetMetadata.tableName)
    this.applySoftDeleteToPredicates(predicates, targetMetadata)

    // 构建 IN 条件：目标表的外键列 IN 源实体的主键值
    const rdbValues: Array<relationalStore.ValueType> = []
    for (let i = 0; i < pkValues.length; i++) {
      rdbValues.push(this.toRdbValue(pkValues[i]))
    }
    try {
      predicates.in(relation.inverseKey, rdbValues)
    } catch (e) {
      // 构建条件失败，设置所有关联为 null
      for (let i = 0; i < entities.length; i++) {
        entities[i].setRelatedSingle(relation.propertyName, null)
      }
      return entities
    }

    let resultSet: relationalStore.ResultSet
    try {
      resultSet = await store.query(predicates)
    } catch (e) {
      // 查询失败，设置所有关联为 null
      for (let i = 0; i < entities.length; i++) {
        entities[i].setRelatedSingle(relation.propertyName, null)
      }
      return entities
    }

    const targetMapper = new DataMapper(relation.targetEntity)

    // 将关联数据按外键值索引
    const relatedByFk: Map<string, EntityData> = new Map()

    try {
      while (resultSet.goToNextRow()) {
        const row = this.resultSetToRow(resultSet, targetMetadata)
        const relatedEntity = targetMapper.fromResultSetRow(row)

        // 获取外键值
        let fkValue: ValueType = null
        const fkProp = relatedEntity.getProperty(relation.inverseKey)
        if (fkProp !== null) {
          fkValue = fkProp.value
        } else {
          // 尝试通过列名获取
          const fkColumn = targetMetadata.getColumnByName(relation.inverseKey)
          if (fkColumn !== null) {
            const fkPropByColumn = relatedEntity.getProperty(fkColumn.propertyName)
            if (fkPropByColumn !== null) {
              fkValue = fkPropByColumn.value
            }
          }
        }

        if (fkValue !== null) {
          const fkKey = String(fkValue)
          // ONE_TO_ONE 关系，每个外键值只对应一个目标实体
          relatedByFk.set(fkKey, relatedEntity)
        }
      }
    } catch (e) {
      // 遍历结果集失败，忽略
    }

    try {
      resultSet.close()
    } catch (e) {
      // 关闭失败，忽略
    }

    // 将关联数据设置到主实体
    for (let i = 0; i < entities.length; i++) {
      const entity = entities[i]
      const pkProp = entity.getProperty(sourcePkColumn.propertyName)
      if (pkProp !== null && pkProp.value !== null) {
        const pkKey = String(pkProp.value)
        const relatedEntity = relatedByFk.get(pkKey)
        if (relatedEntity) {
          entity.setRelatedSingle(relation.propertyName, relatedEntity)
        } else {
          entity.setRelatedSingle(relation.propertyName, null)
        }
      } else {
        entity.setRelatedSingle(relation.propertyName, null)
      }
    }

    return entities
  }

  /**
   * 加载 MANY_TO_MANY 关联数据
   * 使用两次查询策略：
   * 1. 先查询中间表获取目标实体 ID 列表
   * 2. 再根据 ID 列表查询目标实体数据
   * @param entities 主实体数据数组
   * @param relation 多对多关联关系元数据
   * @returns 带有关联数据的实体数组
   */
  private async loadManyToMany(
    entities: Array<EntityData>,
    relation: ManyToManyMetadata
  ): Promise<Array<EntityData>> {
    // 获取源实体元数据
    const sourceMetadata = MetadataStorage.getInstance().getEntityMetadata(this.sourceEntityName)
    if (sourceMetadata === null) {
      return entities
    }

    const sourcePkColumn = sourceMetadata.getPrimaryKeyColumn()
    if (sourcePkColumn === null) {
      return entities
    }

    // 获取目标实体元数据
    const targetMetadata = MetadataStorage.getInstance().getEntityMetadata(relation.targetEntity)
    if (targetMetadata === null) {
      return entities
    }

    const targetPkColumn = targetMetadata.getPrimaryKeyColumn()
    if (targetPkColumn === null) {
      return entities
    }

    // 收集所有主实体的主键值（去重）
    const pkValues: Array<ValueType> = []
    const pkValueSet: Set<string> = new Set()

    for (let i = 0; i < entities.length; i++) {
      const entity = entities[i]
      const pkProp = entity.getProperty(sourcePkColumn.propertyName)
      if (pkProp !== null && pkProp.value !== null) {
        const pkKey = String(pkProp.value)
        if (!pkValueSet.has(pkKey)) {
          pkValueSet.add(pkKey)
          pkValues.push(pkProp.value)
        }
      }
    }

    if (pkValues.length === 0) {
      // 没有主键值，设置所有关联为空数组
      for (let i = 0; i < entities.length; i++) {
        entities[i].setRelatedArray(relation.propertyName, [])
      }
      return entities
    }

    // 获取数据库连接
    let store: relationalStore.RdbStore
    try {
      store = this.getStore()
    } catch (e) {
      // 数据库未初始化，设置所有关联为空数组
      for (let i = 0; i < entities.length; i++) {
        entities[i].setRelatedArray(relation.propertyName, [])
      }
      return entities
    }

    // 第一次查询：从中间表获取关联关系（分批处理）
    // SELECT * FROM join_table WHERE joinSourceKey IN (pkValues)

    // 解析中间表结果，建立源实体主键到目标实体主键的映射
    const sourceToTargetIds: Map<string, Array<ValueType>> = new Map()
    const allTargetIds: Array<ValueType> = []
    const targetIdSet: Set<string> = new Set()

    // 分批查询中间表
    const pkBatches = this.splitIntoBatches(pkValues, RelationLoader.IN_CLAUSE_LIMIT)

    for (let batchIndex = 0; batchIndex < pkBatches.length; batchIndex++) {
      const batch = pkBatches[batchIndex]
      const joinPredicates = new relationalStore.RdbPredicates(relation.joinTable)

      const rdbPkValues: Array<relationalStore.ValueType> = []
      for (let i = 0; i < batch.length; i++) {
        rdbPkValues.push(this.toRdbValue(batch[i]))
      }

      try {
        joinPredicates.in(relation.joinSourceKey, rdbPkValues)
      } catch (e) {
        // 构建条件失败，继续下一批
        continue
      }

      let joinResultSet: relationalStore.ResultSet
      try {
        joinResultSet = await store.query(joinPredicates)
      } catch (e) {
        // 查询失败，继续下一批
        continue
      }

      try {
        while (joinResultSet.goToNextRow()) {
          // 获取源实体外键值
          const sourceKeyIndex = joinResultSet.getColumnIndex(relation.joinSourceKey)
          const targetKeyIndex = joinResultSet.getColumnIndex(relation.joinTargetKey)

          if (sourceKeyIndex >= 0 && targetKeyIndex >= 0) {
            let sourceId: ValueType = null
            let targetId: ValueType = null

            if (!joinResultSet.isColumnNull(sourceKeyIndex)) {
              const rawSourceId = ResultSetUtils.getValueByRuntimeType(joinResultSet, sourceKeyIndex)
              if (rawSourceId !== null && !(rawSourceId instanceof Uint8Array)) {
                sourceId = rawSourceId
              }
            }
            if (!joinResultSet.isColumnNull(targetKeyIndex)) {
              const rawTargetId = ResultSetUtils.getValueByRuntimeType(joinResultSet, targetKeyIndex)
              if (rawTargetId !== null && !(rawTargetId instanceof Uint8Array)) {
                targetId = rawTargetId
              }
            }

            if (sourceId !== null && targetId !== null) {
              const sourceKey = String(sourceId)
              const targetKey = String(targetId)

              // 添加到源实体到目标实体的映射
              let targetIds = sourceToTargetIds.get(sourceKey)
              if (!targetIds) {
                targetIds = []
                sourceToTargetIds.set(sourceKey, targetIds)
              }
              targetIds.push(targetId)

              // 收集所有目标实体 ID（去重）
              if (!targetIdSet.has(targetKey)) {
                targetIdSet.add(targetKey)
                allTargetIds.push(targetId)
              }
            }
          }
        }
      } catch (e) {
        // 遍历结果集失败，忽略
      }

      try {
        joinResultSet.close()
      } catch (e) {
        // 关闭失败，忽略
      }
    }

    // 如果没有关联数据，设置所有关联为空数组
    if (allTargetIds.length === 0) {
      for (let i = 0; i < entities.length; i++) {
        entities[i].setRelatedArray(relation.propertyName, [])
      }
      return entities
    }

    // 第二次查询：根据目标实体 ID 列表查询目标实体数据（分批处理）
    // SELECT * FROM target_table WHERE pk IN (allTargetIds)

    const targetMapper = new DataMapper(relation.targetEntity)

    // 将目标实体按主键值索引
    const targetEntitiesByPk: Map<string, EntityData> = new Map()

    // 分批查询目标表
    const targetIdBatches = this.splitIntoBatches(allTargetIds, RelationLoader.IN_CLAUSE_LIMIT)

    for (let batchIndex = 0; batchIndex < targetIdBatches.length; batchIndex++) {
      const batch = targetIdBatches[batchIndex]
      const targetPredicates = new relationalStore.RdbPredicates(targetMetadata.tableName)
      this.applySoftDeleteToPredicates(targetPredicates, targetMetadata)

      const rdbTargetIds: Array<relationalStore.ValueType> = []
      for (let i = 0; i < batch.length; i++) {
        rdbTargetIds.push(this.toRdbValue(batch[i]))
      }

      try {
        targetPredicates.in(targetPkColumn.columnName, rdbTargetIds)
      } catch (e) {
        // 构建条件失败，继续下一批
        continue
      }

      let targetResultSet: relationalStore.ResultSet
      try {
        targetResultSet = await store.query(targetPredicates)
      } catch (e) {
        // 查询失败，继续下一批
        continue
      }

      try {
        while (targetResultSet.goToNextRow()) {
          const row = this.resultSetToRow(targetResultSet, targetMetadata)
          const targetEntity = targetMapper.fromResultSetRow(row)

          // 获取主键值
          const pkProp = targetEntity.getProperty(targetPkColumn.propertyName)
          if (pkProp !== null && pkProp.value !== null) {
            const pkKey = String(pkProp.value)
            targetEntitiesByPk.set(pkKey, targetEntity)
          }
        }
      } catch (e) {
        // 遍历结果集失败，忽略
      }

      try {
        targetResultSet.close()
      } catch (e) {
        // 关闭失败，忽略
      }
    }

    // 将关联数据设置到主实体
    for (let i = 0; i < entities.length; i++) {
      const entity = entities[i]
      const pkProp = entity.getProperty(sourcePkColumn.propertyName)

      if (pkProp !== null && pkProp.value !== null) {
        const sourceKey = String(pkProp.value)
        const targetIds = sourceToTargetIds.get(sourceKey)

        if (targetIds && targetIds.length > 0) {
          const relatedEntities: Array<EntityData> = []
          for (let j = 0; j < targetIds.length; j++) {
            const targetKey = String(targetIds[j])
            const targetEntity = targetEntitiesByPk.get(targetKey)
            if (targetEntity) {
              relatedEntities.push(targetEntity)
            }
          }
          entity.setRelatedArray(relation.propertyName, relatedEntities)
        } else {
          entity.setRelatedArray(relation.propertyName, [])
        }
      } else {
        entity.setRelatedArray(relation.propertyName, [])
      }
    }

    return entities
  }

  private applySoftDeleteToPredicates(predicates: relationalStore.RdbPredicates, metadata: EntityMetadata): void {
    if (!metadata.isSoftDeleteEnabled()) {
      return
    }
    const deletedAtColumn = metadata.getDeletedAtColumn()
    predicates.isNull(deletedAtColumn)
  }

  /**
   * 将 ValueType 转换为 RdbPredicates 支持的值类型
   */
  private toRdbValue(value: ValueType): relationalStore.ValueType {
    if (value === null) {
      return null
    }
    if (typeof value === 'boolean') {
      return value ? 1 : 0
    }
    if (value instanceof Date) {
      return value.getTime()
    }
    if (value instanceof Uint8Array) {
      return value
    }
    if (typeof value === 'object') {
      try {
        return JSON.stringify(value as object)
      } catch (e) {
        return null
      }
    }
    if (typeof value === 'string' || typeof value === 'number') {
      return value
    }
    return null
  }

  /**
   * 将 ResultSet 当前行转换为 ResultSetRow
   */
  private resultSetToRow(resultSet: relationalStore.ResultSet, metadata: EntityMetadata): ResultSetRow {
    const row = new ResultSetRow()
    const columnNames = resultSet.columnNames

    for (let i = 0; i < columnNames.length; i++) {
      const columnName = columnNames[i]
      try {
        const columnIndex = resultSet.getColumnIndex(columnName)

        if (resultSet.isColumnNull(columnIndex)) {
          row.set(columnName, null)
        } else {
          const columnMetadata = metadata.getColumnByName(columnName)
          if (columnMetadata !== null) {
            switch (columnMetadata.columnType) {
              case ColumnType.INTEGER:
                row.set(columnName, resultSet.getLong(columnIndex))
                break
              case ColumnType.REAL:
                row.set(columnName, resultSet.getDouble(columnIndex))
                break
              case ColumnType.TEXT:
                row.set(columnName, resultSet.getString(columnIndex))
                break
              case ColumnType.BLOB:
                row.set(columnName, resultSet.getBlob(columnIndex))
                break
              default:
                row.set(columnName, resultSet.getString(columnIndex))
            }
          } else {
            row.set(columnName, resultSet.getString(columnIndex))
          }
        }
      } catch (e) {
        row.set(columnName, null)
      }
    }

    return row
  }
}
