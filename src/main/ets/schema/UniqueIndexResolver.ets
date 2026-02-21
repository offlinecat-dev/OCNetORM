import { EntityMetadata } from '../core/EntityMetadata'
import { IndexMetadata } from '../core/IndexMetadata'
import { ValidationMetadataStorage, ValidationRule } from '../validation/ValidationMetadataStorage'

function hasUniqueRule(rules: Array<ValidationRule>): boolean {
  for (let i = 0; i < rules.length; i++) {
    if (rules[i].type === 'unique') {
      return true
    }
  }
  return false
}

function normalize(value: string): string {
  return value.trim().toLowerCase()
}

function hasUniqueSingleColumnIndex(indexes: Array<IndexMetadata>, columnName: string): boolean {
  const normalizedColumn = normalize(columnName)
  for (let i = 0; i < indexes.length; i++) {
    const index = indexes[i]
    if (!index.unique || index.columns.length !== 1) {
      continue
    }
    if (normalize(index.columns[0]) === normalizedColumn) {
      return true
    }
  }
  return false
}

function hasIndexName(indexes: Array<IndexMetadata>, indexName: string): boolean {
  const normalizedName = normalize(indexName)
  for (let i = 0; i < indexes.length; i++) {
    if (normalize(indexes[i].name) === normalizedName) {
      return true
    }
  }
  return false
}

function toSafeIdentifierPart(value: string): string {
  return value.replace(/[^a-zA-Z0-9_]/g, '_')
}

function buildUniqueIndexName(tableName: string, columnName: string): string {
  return `uidx_${toSafeIdentifierPart(tableName)}_${toSafeIdentifierPart(columnName)}`
}

function nextAvailableIndexName(indexes: Array<IndexMetadata>, baseName: string): string {
  if (!hasIndexName(indexes, baseName)) {
    return baseName
  }
  let suffix = 1
  while (hasIndexName(indexes, `${baseName}_${suffix}`)) {
    suffix++
  }
  return `${baseName}_${suffix}`
}

function collectUniqueRuleColumns(metadata: EntityMetadata): Array<string> {
  const columns: Array<string> = []
  const ruleMap = ValidationMetadataStorage.getInstance().getRules(metadata.entityName)
  ruleMap.forEach((rules, propertyName) => {
    if (!hasUniqueRule(rules)) {
      return
    }
    const column = metadata.getColumnByProperty(propertyName)
    if (column === null || column.isPrimaryKey || column.isUnique) {
      return
    }
    if (!columns.includes(column.columnName)) {
      columns.push(column.columnName)
    }
  })
  return columns
}

export function resolveEntityIndexes(metadata: EntityMetadata): Array<IndexMetadata> {
  const indexes = metadata.getIndexes()
  const uniqueRuleColumns = collectUniqueRuleColumns(metadata)
  for (let i = 0; i < uniqueRuleColumns.length; i++) {
    const columnName = uniqueRuleColumns[i]
    if (hasUniqueSingleColumnIndex(indexes, columnName)) {
      continue
    }
    const baseName = buildUniqueIndexName(metadata.tableName, columnName)
    const indexName = nextAvailableIndexName(indexes, baseName)
    indexes.push(new IndexMetadata(indexName, [columnName], true))
  }
  return indexes
}
