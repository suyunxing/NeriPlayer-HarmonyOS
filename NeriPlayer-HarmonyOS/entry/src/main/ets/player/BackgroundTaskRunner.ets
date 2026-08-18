import { common } from '@kit.AbilityKit';
import { Logger } from '../app/Logger';

/**
 * Continuous-task lifecycle for background audio playback.
 *
 * On HarmonyOS the app declares `backgroundModes: ["audioPlayback"]` in
 * module.json5, so AVPlayer playback continues in the background natively
 * without startBackgroundRunning(). This class keeps the PlayerManager
 * contract (start/stop on play/pause) and records the state for diagnostics.
 */
export class BackgroundTaskRunner {
  private static running = false;

  static async start(context: common.Context): Promise<void> {
    if (BackgroundTaskRunner.running) {
      return;
    }
    BackgroundTaskRunner.running = true;
    Logger.info('BackgroundTaskRunner.start: background audio handled by backgroundModes');
  }

  static async stop(context: common.Context): Promise<void> {
    if (!BackgroundTaskRunner.running) {
      return;
    }
    BackgroundTaskRunner.running = false;
    Logger.info('BackgroundTaskRunner.stop');
  }
}
