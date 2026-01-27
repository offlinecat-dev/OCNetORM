import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { Context } from '@kit.AbilityKit';
import { OrmContext, OrmContextConfig } from '../../main/ets/core/OrmContext';
import { OCORMInit, OCORMInitOptions } from '../../main/ets/core/OrmInit';
import { MetadataStorage } from '../../main/ets/core/MetadataStorage';
import { DatabaseManager, DatabaseManagerAdapter } from '../../main/ets/database/DatabaseManager';
import { DatabaseConfig } from '../../main/ets/database/DatabaseConfig';
import { Logger } from '../../main/ets/logging/Logger';
import { LogLevel } from '../../main/ets/logging/LogLevel';
import { SchemaBuilder, CreateAllTablesResult } from '../../main/ets/schema/SchemaBuilder';
import { MigrationManager, SchemaMigrationExecutionResult, AutoMigrationOptions } from '../../main/ets/schema/MigrationManager';

class TestContext {
}

class ContextConfig implements OrmContextConfig {
  metadataStorage?: MetadataStorage;
  databaseManager?: DatabaseManager;
  logger?: Logger;
  enableLogging?: boolean;
  logLevel?: LogLevel;
}

class InitOptions implements OCORMInitOptions {
  config: DatabaseConfig;
  databaseManager?: DatabaseManagerAdapter;
  autoCreateTables?: boolean;
  autoMigrate?: boolean;
  autoMigrationOptions?: AutoMigrationOptions;
  migrationManager?: MigrationManager;
  enableLogger?: boolean;
  logLevel?: LogLevel;
  schemaBuilder?: SchemaBuilder;

  constructor(config: DatabaseConfig) {
    this.config = config;
  }
}

class TestAutoMigrationOptions implements AutoMigrationOptions {
  includeJoinTables: boolean = true;
}

class TestDatabaseManager implements DatabaseManagerAdapter {
  initCount: number = 0;
  lastConfig: DatabaseConfig | null = null;

  async initialize(context: Context, config: DatabaseConfig): Promise<void> {
    this.initCount++;
    this.lastConfig = config;
  }
}

class TestSchemaBuilder extends SchemaBuilder {
  called: boolean = false;
  includeJoinTables: boolean = true;
  result: CreateAllTablesResult;

  constructor(result: CreateAllTablesResult) {
    super();
    this.result = result;
  }

  async createAllTablesWithManager(includeJoinTables: boolean = true): Promise<CreateAllTablesResult> {
    this.called = true;
    this.includeJoinTables = includeJoinTables;
    return this.result;
  }
}

class TestMigrationManager extends MigrationManager {
  called: boolean = false;
  options: AutoMigrationOptions | null = null;
  result: SchemaMigrationExecutionResult;

  constructor(result: SchemaMigrationExecutionResult) {
    super();
    this.result = result;
  }

  async autoMigrateWithManager(options?: AutoMigrationOptions): Promise<SchemaMigrationExecutionResult> {
    this.called = true;
    this.options = options !== undefined ? options : null;
    return this.result;
  }
}

const resetCoreSingletons = (): void => {
  OrmContext.resetInstance();
  MetadataStorage.resetInstance();
  DatabaseManager.resetInstance();
  Logger.resetInstance();
};

const createContext = (): Context => {
  const context = new TestContext();
  return context as Context;
};

const createCreateAllTablesResult = (): CreateAllTablesResult => {
  const result = new CreateAllTablesResult();
  result.success = true;
  result.successCount = 1;
  return result;
};

const createMigrationResult = (): SchemaMigrationExecutionResult => {
  const result = new SchemaMigrationExecutionResult();
  result.success = true;
  result.executedCount = 1;
  return result;
};

export default function coreContextInitTest() {
  describe('coreContextInitTest', () => {
    beforeAll(() => {
    });
    beforeEach(() => {
      resetCoreSingletons();
    });
    afterEach(() => {
    });
    afterAll(() => {
    });

    describe('OrmContext', () => {
      it('configure should inject dependencies and mark configured', 0, () => {
        const storageA = MetadataStorage.getInstance();
        const dbA = DatabaseManager.getInstance();
        const loggerA = Logger.getInstance();
        const context = OrmContext.getInstance();
        expect(context.getMetadataStorage() === storageA).assertEqual(true);
        expect(context.getDatabaseManager() === dbA).assertEqual(true);
        expect(context.getLogger() === loggerA).assertEqual(true);

        MetadataStorage.resetInstance();
        DatabaseManager.resetInstance();
        Logger.resetInstance();
        const storageB = MetadataStorage.getInstance();
        const dbB = DatabaseManager.getInstance();
        const loggerB = Logger.getInstance();

        const config = new ContextConfig();
        config.metadataStorage = storageB;
        config.databaseManager = dbB;
        config.logger = loggerB;
        OrmContext.configure(config);

        expect(context.getMetadataStorage() === storageB).assertEqual(true);
        expect(context.getDatabaseManager() === dbB).assertEqual(true);
        expect(context.getLogger() === loggerB).assertEqual(true);
        expect(context.isConfigured()).assertEqual(true);
      });

      it('configure should override logging settings', 0, () => {
        const context = OrmContext.getInstance();
        const config = new ContextConfig();
        config.enableLogging = true;
        config.logLevel = LogLevel.DEBUG;
        OrmContext.configure(config);

        const logger = context.getLogger();
        expect(logger.isEnabled()).assertEqual(true);
        expect(logger.getLevel()).assertEqual(LogLevel.DEBUG);
      });

      it('reset and resetInstance should restore defaults', 0, () => {
        const context = OrmContext.getInstance();
        const config = new ContextConfig();
        config.enableLogging = true;
        OrmContext.configure(config);
        expect(context.isConfigured()).assertEqual(true);

        context.reset();
        expect(context.isConfigured()).assertEqual(false);
        expect(context.getMetadataStorage() === MetadataStorage.getInstance()).assertEqual(true);
        expect(context.getDatabaseManager() === DatabaseManager.getInstance()).assertEqual(true);
        expect(context.getLogger() === Logger.getInstance()).assertEqual(true);

        OrmContext.resetInstance();
        const newContext = OrmContext.getInstance();
        expect(newContext === context).assertEqual(false);
        expect(newContext.isConfigured()).assertEqual(false);
      });
    });

    describe('OCORMInit', () => {
      it('autoCreateTables false should return null', 0, async () => {
        Logger.resetInstance();
        const manager = new TestDatabaseManager();
        const builderResult = createCreateAllTablesResult();
        const builder = new TestSchemaBuilder(builderResult);
        const config = new DatabaseConfig('test.db');

        const options = new InitOptions(config);
        options.databaseManager = manager;
        options.autoCreateTables = false;
        options.schemaBuilder = builder;

        const result = await OCORMInit(createContext(), options);
        expect(result === null).assertEqual(true);
        expect(builder.called).assertEqual(false);
        expect(manager.initCount).assertEqual(1);
      });

      it('autoMigrate true should use migration manager', 0, async () => {
        Logger.resetInstance();
        const manager = new TestDatabaseManager();
        const migrateResult = createMigrationResult();
        const migrationManager = new TestMigrationManager(migrateResult);
        const builder = new TestSchemaBuilder(createCreateAllTablesResult());
        const config = new DatabaseConfig('test.db');
        const migrationOptions = new TestAutoMigrationOptions();
        migrationOptions.includeJoinTables = false;

        const options = new InitOptions(config);
        options.databaseManager = manager;
        options.autoMigrate = true;
        options.autoMigrationOptions = migrationOptions;
        options.migrationManager = migrationManager;
        options.schemaBuilder = builder;

        const result = await OCORMInit(createContext(), options);
        expect(result === migrateResult).assertEqual(true);
        expect(migrationManager.called).assertEqual(true);
        expect(builder.called).assertEqual(false);
        expect(migrationManager.options !== null).assertEqual(true);
        if (migrationManager.options) {
          expect(migrationManager.options.includeJoinTables).assertEqual(false);
        }
      });

      it('schemaBuilder injection should be used when autoCreateTables is true', 0, async () => {
        Logger.resetInstance();
        const manager = new TestDatabaseManager();
        const builderResult = createCreateAllTablesResult();
        const builder = new TestSchemaBuilder(builderResult);
        const config = new DatabaseConfig('test.db');

        const options = new InitOptions(config);
        options.databaseManager = manager;
        options.schemaBuilder = builder;

        const result = await OCORMInit(createContext(), options);
        expect(result === builderResult).assertEqual(true);
        expect(builder.called).assertEqual(true);
        expect(builder.includeJoinTables).assertEqual(true);
      });

      it('logger config should follow config and override options', 0, async () => {
        const manager = new TestDatabaseManager();
        const config = new DatabaseConfig('test.db');
        config.enableLogger = true;
        config.loggerLevel = LogLevel.DEBUG;

        const options = new InitOptions(config);
        options.databaseManager = manager;
        options.autoCreateTables = false;

        await OCORMInit(createContext(), options);
        const logger = Logger.getInstance();
        expect(logger.isEnabled()).assertEqual(true);
        expect(logger.getLevel()).assertEqual(LogLevel.DEBUG);

        const overrideConfig = new DatabaseConfig('test.db');
        overrideConfig.enableLogger = true;
        overrideConfig.loggerLevel = LogLevel.DEBUG;
        const overrideOptions = new InitOptions(overrideConfig);
        overrideOptions.databaseManager = manager;
        overrideOptions.autoCreateTables = false;
        overrideOptions.enableLogger = false;
        overrideOptions.logLevel = LogLevel.ERROR;

        await OCORMInit(createContext(), overrideOptions);
        expect(logger.isEnabled()).assertEqual(false);
        expect(logger.getLevel()).assertEqual(LogLevel.ERROR);
      });
    });
  });
}
