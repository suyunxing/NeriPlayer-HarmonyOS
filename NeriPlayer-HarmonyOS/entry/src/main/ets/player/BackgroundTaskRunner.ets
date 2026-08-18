import { common, Want, WantAgent, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '../app/Logger';

/**
 * Continuous-task lifecycle for background audio playback.
 *
 * The `backgroundModes: ["audioPlayback"]` declaration in module.json5 is
 * only the prerequisite: per the AVSession background guide the app must
 * also request the AUDIO_PLAYBACK continuous task while playing (otherwise
 * audio is muted/frozen once backgrounded), and cancel it on pause/stop.
 * Failures degrade to a log line and never block playback.
 */
export class BackgroundTaskRunner {
  private static running = false;
  private static cachedAgent: WantAgent | null = null;

  static async start(context: common.Context): Promise<void> {
    if (BackgroundTaskRunner.running) {
      return;
    }
    BackgroundTaskRunner.running = true;
    try {
      const agent = await BackgroundTaskRunner.getAgent();
      await backgroundTaskManager.startBackgroundRunning(
        context,
        backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK,
        agent
      );
      Logger.info('BackgroundTaskRunner: AUDIO_PLAYBACK continuous task started');
    } catch (error) {
      const e = error as BusinessError;
      Logger.warn(`BackgroundTaskRunner.start failed: code=${e.code} message=${e.message}`);
    }
  }

  static async stop(context: common.Context): Promise<void> {
    if (!BackgroundTaskRunner.running) {
      return;
    }
    BackgroundTaskRunner.running = false;
    try {
      await backgroundTaskManager.stopBackgroundRunning(context);
      Logger.info('BackgroundTaskRunner: AUDIO_PLAYBACK continuous task stopped');
    } catch (error) {
      const e = error as BusinessError;
      Logger.warn(`BackgroundTaskRunner.stop failed: code=${e.code} message=${e.message}`);
    }
  }

  private static async getAgent(): Promise<WantAgent> {
    if (BackgroundTaskRunner.cachedAgent !== null) {
      return BackgroundTaskRunner.cachedAgent;
    }
    const target: Want = {
      bundleName: 'moe.ouom.neriplayer',
      abilityName: 'EntryAbility'
    };
    const info: wantAgent.WantAgentInfo = {
      wants: [target],
      operationType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0
    };
    const agent: WantAgent = await wantAgent.getWantAgent(info);
    BackgroundTaskRunner.cachedAgent = agent;
    return agent;
  }
}
