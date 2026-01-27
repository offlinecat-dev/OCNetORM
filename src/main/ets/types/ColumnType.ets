/**
 * 数据库列类型枚举
 * 定义 SQLite 支持的基本数据类型
 */

export enum ColumnType {
  /** 文本类型，对应 SQLite TEXT */
  TEXT = 'TEXT',
  /** 整数类型，对应 SQLite INTEGER */
  INTEGER = 'INTEGER',
  /** 浮点数类型，对应 SQLite REAL */
  REAL = 'REAL',
  /** 二进制类型，对应 SQLite BLOB */
  BLOB = 'BLOB'
}
