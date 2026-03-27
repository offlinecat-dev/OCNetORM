import { DatabaseConfig } from '../DatabaseConfig'
import { DatabaseManager, DatabaseManagerTestingState } from '../DatabaseManager'

export type DatabaseManagerTestState = DatabaseManagerTestingState

/**
 * DatabaseManager 测试钩子（测试专用可见面）
 */
export class DatabaseManagerTestHooks {
  static getState(manager: DatabaseManager = DatabaseManager.getInstance()): DatabaseManagerTestState {
    const internal: DatabaseManagerTestingState = manager.getTestingState()
    return internal
  }

  static setState(
    manager: DatabaseManager,
    state: DatabaseManagerTestState
  ): void {
    manager.setTestingState(state)
  }

  static applyRuntimeConfig(manager: DatabaseManager, config: DatabaseConfig): void {
    manager.applyRuntimeConfigForTesting(config)
  }

  static resetInstance(): void {
    DatabaseManager.resetInstanceForTesting()
  }
}
