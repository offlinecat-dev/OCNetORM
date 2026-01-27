import { describe, beforeEach, it, expect } from '@ohos/hypium';
import { Logger } from '../../main/ets/logging/Logger';
import { LogLevel } from '../../main/ets/logging/LogLevel';

export default function loggerTest() {
  describe('loggerTest', () => {
    beforeEach(() => {
      Logger.resetInstance();
    });

    // ==================== 单例模式测试 ====================
    it('Logger should be singleton', 0, () => {
      const logger1 = Logger.getInstance();
      const logger2 = Logger.getInstance();
      expect(logger1 === logger2).assertEqual(true);
    });

    it('resetInstance should create new instance', 0, () => {
      const logger1 = Logger.getInstance();
      logger1.configure(true, LogLevel.DEBUG);
      Logger.resetInstance();
      const logger2 = Logger.getInstance();
      expect(logger2.isEnabled()).assertEqual(false);
    });

    // ==================== configure 测试 ====================
    it('configure should set enabled to true', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.INFO);
      expect(logger.isEnabled()).assertEqual(true);
    });

    it('configure should set enabled to false', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(false, LogLevel.INFO);
      expect(logger.isEnabled()).assertEqual(false);
    });

    it('configure should set level to ERROR', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.ERROR);
      expect(logger.getLevel()).assertEqual(LogLevel.ERROR);
    });

    it('configure should set level to INFO', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.INFO);
      expect(logger.getLevel()).assertEqual(LogLevel.INFO);
    });

    it('configure should set level to DEBUG', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      expect(logger.getLevel()).assertEqual(LogLevel.DEBUG);
    });

    it('configure can be called multiple times', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.ERROR);
      expect(logger.getLevel()).assertEqual(LogLevel.ERROR);
      logger.configure(true, LogLevel.DEBUG);
      expect(logger.getLevel()).assertEqual(LogLevel.DEBUG);
    });

    // ==================== recordHistory on/off 测试 ====================
    it('setRecordHistory should enable history recording', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logDebug('test message');
      const history = logger.getLogHistory();
      expect(history.length).assertEqual(1);
    });

    it('setRecordHistory should disable history recording', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logDebug('test message 1');
      logger.setRecordHistory(false);
      logger.logDebug('test message 2');
      const history = logger.getLogHistory();
      expect(history.length).assertEqual(0);
    });

    it('setRecordHistory false should clear existing history', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logDebug('test message');
      expect(logger.getLogHistory().length).assertEqual(1);
      logger.setRecordHistory(false);
      expect(logger.getLogHistory().length).assertEqual(0);
    });

    it('getLogHistory should return copy of history', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logDebug('test message');
      const history1 = logger.getLogHistory();
      const history2 = logger.getLogHistory();
      expect(history1 !== history2).assertEqual(true);
      expect(history1.length).assertEqual(history2.length);
    });

    it('clearLogHistory should clear all history', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logDebug('test message 1');
      logger.logDebug('test message 2');
      expect(logger.getLogHistory().length).assertEqual(2);
      logger.clearLogHistory();
      expect(logger.getLogHistory().length).assertEqual(0);
    });

    it('history should have max limit', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      for (let i = 0; i < 250; i++) {
        logger.logDebug(`message ${i}`);
      }
      const history = logger.getLogHistory();
      expect(history.length).assertEqual(200);
    });

    // ==================== logQuery 测试 ====================
    it('logQuery should record when DEBUG level', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logQuery('SELECT * FROM users', 15);
      const history = logger.getLogHistory();
      expect(history.length).assertEqual(1);
      expect(history[0].indexOf('QUERY') >= 0).assertEqual(true);
      expect(history[0].indexOf('15ms') >= 0).assertEqual(true);
    });

    it('logQuery should not record when INFO level', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.INFO);
      logger.setRecordHistory(true);
      logger.logQuery('SELECT * FROM users', 15);
      const history = logger.getLogHistory();
      expect(history.length).assertEqual(0);
    });

    it('logQuery should not record when ERROR level', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.ERROR);
      logger.setRecordHistory(true);
      logger.logQuery('SELECT * FROM users', 15);
      const history = logger.getLogHistory();
      expect(history.length).assertEqual(0);
    });

    it('logQuery should not record when disabled', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(false, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logQuery('SELECT * FROM users', 15);
      const history = logger.getLogHistory();
      expect(history.length).assertEqual(0);
    });

    it('logQuery should sanitize SQL string values', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logQuery("SELECT * FROM users WHERE name = 'John'", 10);
      const history = logger.getLogHistory();
      expect(history[0].indexOf("'[***]'") >= 0).assertEqual(true);
      expect(history[0].indexOf("'John'") < 0).assertEqual(true);
    });

    it('logQuery should sanitize long numbers', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logQuery('SELECT * FROM users WHERE phone = 13812345678', 10);
      const history = logger.getLogHistory();
      expect(history[0].indexOf('[***]') >= 0).assertEqual(true);
      expect(history[0].indexOf('13812345678') < 0).assertEqual(true);
    });

    it('logQuery should not sanitize short numbers', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logQuery('SELECT * FROM users WHERE id = 123456', 10);
      const history = logger.getLogHistory();
      expect(history[0].indexOf('123456') >= 0).assertEqual(true);
    });

    // ==================== logTransaction 测试 ====================
    it('logTransaction should record when INFO level', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.INFO);
      logger.setRecordHistory(true);
      logger.logTransaction('BEGIN');
      const history = logger.getLogHistory();
      expect(history.length).assertEqual(1);
      expect(history[0].indexOf('TRANSACTION') >= 0).assertEqual(true);
      expect(history[0].indexOf('BEGIN') >= 0).assertEqual(true);
    });

    it('logTransaction should record when DEBUG level', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logTransaction('COMMIT');
      const history = logger.getLogHistory();
      expect(history.length).assertEqual(1);
      expect(history[0].indexOf('COMMIT') >= 0).assertEqual(true);
    });

    it('logTransaction should not record when ERROR level', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.ERROR);
      logger.setRecordHistory(true);
      logger.logTransaction('BEGIN');
      const history = logger.getLogHistory();
      expect(history.length).assertEqual(0);
    });

    it('logTransaction should not record when disabled', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(false, LogLevel.INFO);
      logger.setRecordHistory(true);
      logger.logTransaction('BEGIN');
      const history = logger.getLogHistory();
      expect(history.length).assertEqual(0);
    });

    it('logTransaction should record ROLLBACK action', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.INFO);
      logger.setRecordHistory(true);
      logger.logTransaction('ROLLBACK');
      const history = logger.getLogHistory();
      expect(history[0].indexOf('ROLLBACK') >= 0).assertEqual(true);
    });

    // ==================== logError 测试 ====================
    it('logError should record when ERROR level', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.ERROR);
      logger.setRecordHistory(true);
      logger.logError('Database connection failed');
      const history = logger.getLogHistory();
      expect(history.length).assertEqual(1);
      expect(history[0].indexOf('ERROR') >= 0).assertEqual(true);
    });

    it('logError should record when INFO level', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.INFO);
      logger.setRecordHistory(true);
      logger.logError('Some error');
      const history = logger.getLogHistory();
      expect(history.length).assertEqual(1);
    });

    it('logError should record when DEBUG level', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logError('Some error');
      const history = logger.getLogHistory();
      expect(history.length).assertEqual(1);
    });

    it('logError should not record when disabled', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(false, LogLevel.ERROR);
      logger.setRecordHistory(true);
      logger.logError('Some error');
      const history = logger.getLogHistory();
      expect(history.length).assertEqual(0);
    });

    it('logError should sanitize sensitive data', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.ERROR);
      logger.setRecordHistory(true);
      logger.logError("Failed to insert user 'admin' with phone 13812345678");
      const history = logger.getLogHistory();
      expect(history[0].indexOf("'[***]'") >= 0).assertEqual(true);
      expect(history[0].indexOf('[***]') >= 0).assertEqual(true);
    });

    // ==================== logDebug 测试 ====================
    it('logDebug should record when DEBUG level', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logDebug('Debug information');
      const history = logger.getLogHistory();
      expect(history.length).assertEqual(1);
      expect(history[0].indexOf('DEBUG') >= 0).assertEqual(true);
    });

    it('logDebug should not record when INFO level', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.INFO);
      logger.setRecordHistory(true);
      logger.logDebug('Debug information');
      const history = logger.getLogHistory();
      expect(history.length).assertEqual(0);
    });

    it('logDebug should not record when ERROR level', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.ERROR);
      logger.setRecordHistory(true);
      logger.logDebug('Debug information');
      const history = logger.getLogHistory();
      expect(history.length).assertEqual(0);
    });

    it('logDebug should not record when disabled', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(false, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logDebug('Debug information');
      const history = logger.getLogHistory();
      expect(history.length).assertEqual(0);
    });

    // ==================== logInfo 测试 ====================
    it('logInfo should record when INFO level', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.INFO);
      logger.setRecordHistory(true);
      logger.logInfo('Info message');
      const history = logger.getLogHistory();
      expect(history.length).assertEqual(1);
      expect(history[0].indexOf('INFO') >= 0).assertEqual(true);
    });

    it('logInfo should record when DEBUG level', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logInfo('Info message');
      const history = logger.getLogHistory();
      expect(history.length).assertEqual(1);
    });

    it('logInfo should not record when ERROR level', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.ERROR);
      logger.setRecordHistory(true);
      logger.logInfo('Info message');
      const history = logger.getLogHistory();
      expect(history.length).assertEqual(0);
    });

    // ==================== sanitizeSql 测试 (通过 logQuery 间接测试) ====================
    it('sanitizeSql should handle multiple string values', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logQuery("INSERT INTO users (name, email) VALUES ('John', 'john@example.com')", 5);
      const history = logger.getLogHistory();
      const logEntry = history[0];
      expect((logEntry.match(/\[\*\*\*\]/g) || []).length >= 2).assertEqual(true);
    });

    it('sanitizeSql should handle empty string values', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logQuery("SELECT * FROM users WHERE name = ''", 5);
      const history = logger.getLogHistory();
      expect(history[0].indexOf("'[***]'") >= 0).assertEqual(true);
    });

    it('sanitizeSql should preserve SQL structure', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logQuery('SELECT * FROM users WHERE id = 1', 5);
      const history = logger.getLogHistory();
      expect(history[0].indexOf('SELECT') >= 0).assertEqual(true);
      expect(history[0].indexOf('FROM') >= 0).assertEqual(true);
      expect(history[0].indexOf('WHERE') >= 0).assertEqual(true);
    });

    // ==================== sanitizeLogMessage 测试 (通过 formatMessage 间接测试) ====================
    it('sanitizeLogMessage should remove control characters', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logDebug('Test\x00message\x1Fwith\x7Fcontrol');
      const history = logger.getLogHistory();
      expect(history[0].indexOf('\x00') < 0).assertEqual(true);
      expect(history[0].indexOf('\x1F') < 0).assertEqual(true);
      expect(history[0].indexOf('\x7F') < 0).assertEqual(true);
    });

    it('sanitizeLogMessage should truncate long messages', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      const longMessage = 'A'.repeat(600);
      logger.logDebug(longMessage);
      const history = logger.getLogHistory();
      expect(history[0].indexOf('...') >= 0).assertEqual(true);
    });

    it('sanitizeLogMessage should not truncate short messages', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logDebug('Short message');
      const history = logger.getLogHistory();
      expect(history[0].indexOf('...') < 0).assertEqual(true);
    });

    // ==================== logPagination 测试 ====================
    it('logPagination should record when DEBUG level', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logPagination(1, 10, 100, 25);
      const history = logger.getLogHistory();
      expect(history.length).assertEqual(1);
      expect(history[0].indexOf('PAGINATION') >= 0).assertEqual(true);
    });

    it('logPagination should not record when INFO level', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.INFO);
      logger.setRecordHistory(true);
      logger.logPagination(1, 10, 100, 25);
      const history = logger.getLogHistory();
      expect(history.length).assertEqual(0);
    });

    it('logPagination should include page info', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logPagination(2, 20, 50, 30);
      const history = logger.getLogHistory();
      expect(history[0].indexOf('页码') >= 0).assertEqual(true);
      expect(history[0].indexOf('每页') >= 0).assertEqual(true);
      expect(history[0].indexOf('总数') >= 0).assertEqual(true);
    });

    it('logPagination should include duration', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logPagination(1, 10, 100, 45);
      const history = logger.getLogHistory();
      expect(history[0].indexOf('45ms') >= 0).assertEqual(true);
    });

    it('logPagination should calculate total pages', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logPagination(1, 10, 95, 20);
      const history = logger.getLogHistory();
      expect(history[0].indexOf('1/10') >= 0).assertEqual(true);
    });

    it('logPagination should handle zero pageSize', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logPagination(1, 0, 100, 20);
      const history = logger.getLogHistory();
      expect(history[0].indexOf('1/0') >= 0).assertEqual(true);
    });

    // ==================== logTaskPool 测试 ====================
    it('logTaskPool should record when DEBUG level', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logTaskPool('QueryTask', 100, 1000, true);
      const history = logger.getLogHistory();
      expect(history.length).assertEqual(1);
      expect(history[0].indexOf('TASKPOOL') >= 0).assertEqual(true);
    });

    it('logTaskPool should not record when INFO level', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.INFO);
      logger.setRecordHistory(true);
      logger.logTaskPool('QueryTask', 100, 1000, true);
      const history = logger.getLogHistory();
      expect(history.length).assertEqual(0);
    });

    it('logTaskPool should show TaskPool when usedTaskPool is true', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logTaskPool('QueryTask', 100, 500, true);
      const history = logger.getLogHistory();
      expect(history[0].indexOf('TaskPool') >= 0).assertEqual(true);
    });

    it('logTaskPool should show fallback when usedTaskPool is false', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logTaskPool('QueryTask', 50, 100, false);
      const history = logger.getLogHistory();
      expect(history[0].indexOf('主线程(降级)') >= 0).assertEqual(true);
    });

    it('logTaskPool should include task name', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logTaskPool('MyCustomTask', 100, 500, true);
      const history = logger.getLogHistory();
      expect(history[0].indexOf('MyCustomTask') >= 0).assertEqual(true);
    });

    it('logTaskPool should include data count', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logTaskPool('QueryTask', 100, 12345, true);
      const history = logger.getLogHistory();
      expect(history[0].indexOf('12345') >= 0).assertEqual(true);
    });

    it('logTaskPool should include duration', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logTaskPool('QueryTask', 256, 1000, true);
      const history = logger.getLogHistory();
      expect(history[0].indexOf('256ms') >= 0).assertEqual(true);
    });

    // ==================== logParallelRelation 测试 ====================
    it('logParallelRelation should record when DEBUG level', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logParallelRelation(['posts', 'comments'], 50, 2);
      const history = logger.getLogHistory();
      expect(history.length).assertEqual(1);
      expect(history[0].indexOf('PARALLEL_RELATION') >= 0).assertEqual(true);
    });

    it('logParallelRelation should not record when INFO level', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.INFO);
      logger.setRecordHistory(true);
      logger.logParallelRelation(['posts'], 50, 1);
      const history = logger.getLogHistory();
      expect(history.length).assertEqual(0);
    });

    it('logParallelRelation should include relation names', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logParallelRelation(['profile', 'posts', 'tags'], 100, 3);
      const history = logger.getLogHistory();
      expect(history[0].indexOf('profile') >= 0).assertEqual(true);
      expect(history[0].indexOf('posts') >= 0).assertEqual(true);
      expect(history[0].indexOf('tags') >= 0).assertEqual(true);
    });

    it('logParallelRelation should include success count', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logParallelRelation(['posts', 'comments', 'tags'], 100, 2);
      const history = logger.getLogHistory();
      expect(history[0].indexOf('2/3') >= 0).assertEqual(true);
    });

    it('logParallelRelation should include duration', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logParallelRelation(['posts'], 123, 1);
      const history = logger.getLogHistory();
      expect(history[0].indexOf('123ms') >= 0).assertEqual(true);
    });

    it('logParallelRelation should handle empty relations array', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logParallelRelation([], 10, 0);
      const history = logger.getLogHistory();
      expect(history.length).assertEqual(1);
      expect(history[0].indexOf('0/0') >= 0).assertEqual(true);
    });

    // ==================== logBatchInsert 测试 ====================
    it('logBatchInsert should record when DEBUG level', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logBatchInsert('users', 100, 100, 200, true);
      const history = logger.getLogHistory();
      expect(history.length).assertEqual(1);
      expect(history[0].indexOf('BATCH_INSERT') >= 0).assertEqual(true);
    });

    it('logBatchInsert should not record when INFO level', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.INFO);
      logger.setRecordHistory(true);
      logger.logBatchInsert('users', 100, 100, 200, true);
      const history = logger.getLogHistory();
      expect(history.length).assertEqual(0);
    });

    it('logBatchInsert should include table name', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logBatchInsert('my_table', 50, 50, 100, true);
      const history = logger.getLogHistory();
      expect(history[0].indexOf('my_table') >= 0).assertEqual(true);
    });

    it('logBatchInsert should include insert count', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logBatchInsert('users', 100, 95, 200, true);
      const history = logger.getLogHistory();
      expect(history[0].indexOf('95/100') >= 0).assertEqual(true);
    });

    it('logBatchInsert should show transaction mode when useTransaction is true', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logBatchInsert('users', 100, 100, 200, true);
      const history = logger.getLogHistory();
      expect(history[0].indexOf('事务模式') >= 0).assertEqual(true);
    });

    it('logBatchInsert should show non-transaction mode when useTransaction is false', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logBatchInsert('users', 100, 100, 200, false);
      const history = logger.getLogHistory();
      expect(history[0].indexOf('非事务模式') >= 0).assertEqual(true);
    });

    it('logBatchInsert should include duration', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logBatchInsert('users', 100, 100, 567, true);
      const history = logger.getLogHistory();
      expect(history[0].indexOf('567ms') >= 0).assertEqual(true);
    });

    // ==================== formatMessage 测试 ====================
    it('formatMessage should include OCORM prefix', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logDebug('test');
      const history = logger.getLogHistory();
      expect(history[0].indexOf('[OCORM]') >= 0).assertEqual(true);
    });

    it('formatMessage should include log type', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logDebug('test');
      const history = logger.getLogHistory();
      expect(history[0].indexOf('[DEBUG]') >= 0).assertEqual(true);
    });

    // ==================== 边界条件测试 ====================
    it('should handle empty message', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logDebug('');
      const history = logger.getLogHistory();
      expect(history.length).assertEqual(1);
    });

    it('should handle special characters in message', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logDebug('测试消息 with special chars: @#$%^&*()');
      const history = logger.getLogHistory();
      expect(history.length).assertEqual(1);
    });

    it('should handle unicode in message', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logDebug('Unicode: 你好世界 🎉 日本語');
      const history = logger.getLogHistory();
      expect(history.length).assertEqual(1);
      expect(history[0].indexOf('你好世界') >= 0).assertEqual(true);
    });

    it('should handle newlines in message', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logDebug('Line1\nLine2\nLine3');
      const history = logger.getLogHistory();
      expect(history.length).assertEqual(1);
    });

    it('isEnabled should return correct state', 0, () => {
      const logger = Logger.getInstance();
      expect(logger.isEnabled()).assertEqual(false);
      logger.configure(true, LogLevel.DEBUG);
      expect(logger.isEnabled()).assertEqual(true);
      logger.configure(false, LogLevel.DEBUG);
      expect(logger.isEnabled()).assertEqual(false);
    });

    it('getLevel should return correct level', 0, () => {
      const logger = Logger.getInstance();
      expect(logger.getLevel()).assertEqual(LogLevel.INFO);
      logger.configure(true, LogLevel.DEBUG);
      expect(logger.getLevel()).assertEqual(LogLevel.DEBUG);
      logger.configure(true, LogLevel.ERROR);
      expect(logger.getLevel()).assertEqual(LogLevel.ERROR);
    });

    // ==================== 日志级别优先级测试 ====================
    it('DEBUG level should allow all log types', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logError('error');
      logger.logTransaction('BEGIN');
      logger.logDebug('debug');
      logger.logQuery('SELECT 1', 1);
      const history = logger.getLogHistory();
      expect(history.length).assertEqual(4);
    });

    it('INFO level should allow error and transaction logs', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.INFO);
      logger.setRecordHistory(true);
      logger.logError('error');
      logger.logTransaction('BEGIN');
      logger.logDebug('debug');
      logger.logQuery('SELECT 1', 1);
      const history = logger.getLogHistory();
      expect(history.length).assertEqual(2);
    });

    it('ERROR level should only allow error logs', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.ERROR);
      logger.setRecordHistory(true);
      logger.logError('error');
      logger.logTransaction('BEGIN');
      logger.logDebug('debug');
      logger.logQuery('SELECT 1', 1);
      const history = logger.getLogHistory();
      expect(history.length).assertEqual(1);
    });

    // ==================== 多次调用测试 ====================
    it('multiple log calls should accumulate in history', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logDebug('message 1');
      logger.logDebug('message 2');
      logger.logDebug('message 3');
      const history = logger.getLogHistory();
      expect(history.length).assertEqual(3);
    });

    it('history should maintain order', 0, () => {
      const logger = Logger.getInstance();
      logger.configure(true, LogLevel.DEBUG);
      logger.setRecordHistory(true);
      logger.logDebug('first');
      logger.logDebug('second');
      logger.logDebug('third');
      const history = logger.getLogHistory();
      expect(history[0].indexOf('first') >= 0).assertEqual(true);
      expect(history[1].indexOf('second') >= 0).assertEqual(true);
      expect(history[2].indexOf('third') >= 0).assertEqual(true);
    });
  });
}
