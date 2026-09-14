// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

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
 * the system kills the process a few minutes after backgrounding), and
 * cancel it on pause/stop. Failures degrade to a log line and never block
 * playback, but `running` is only latched on success so the next 'playing'
 * transition retries instead of being short-circuited forever.
 */
export class BackgroundTaskRunner {
  private static running = false;
  private static cachedAgent: WantAgent | null = null;
  // start/stop arrive from AVPlayer state transitions that can overtake an
  // in-flight request; serializing through one chain keeps a later stop from
  // racing past an earlier start at the system service.
  private static chain: Promise<void> = Promise.resolve();
  private static listenersBound = false;

  /**
   * Subscribes to the system-side cancel/suspend notifications. They are the
   * only signal for "the task is gone although we never stopped it" (user
   * dismissed the notification, load-audit reclaim, AVSession compliance
   * suspend), so bind them once at player initialization for diagnostics.
   */
  static init(context: common.UIAbilityContext): void {
    if (BackgroundTaskRunner.listenersBound) {
      return;
    }
    BackgroundTaskRunner.listenersBound = true;
    try {
      backgroundTaskManager.on('continuousTaskCancel', (info: backgroundTaskManager.ContinuousTaskCancelInfo) => {
        // detailedReason (@since 26) narrows the coarse reason into the exact
        // trigger — user dismissing the notification vs. playback-compliance
        // audit — and is absent on older runtimes.
        const detail = info.detailedReason === undefined
          ? ''
          : ` detailedReason=${info.detailedReason}`;
        Logger.warn(`BackgroundTaskRunner: system canceled continuous task id=${info.id} reason=${info.reason}${detail}`);
        BackgroundTaskRunner.running = false;
      });
      backgroundTaskManager.on('continuousTaskSuspend', (info: backgroundTaskManager.ContinuousTaskSuspendInfo) => {
        Logger.warn(`BackgroundTaskRunner: continuous task id=${info.continuousTaskId} suspendState=${info.suspendState}` +
          ` reason=${info.suspendReason}`);
      });
    } catch (error) {
      const e = error as BusinessError;
      Logger.warn(`BackgroundTaskRunner.init on() failed: code=${e.code} message=${e.message}`);
    }
  }

  static start(context: common.UIAbilityContext): void {
    BackgroundTaskRunner.chain = BackgroundTaskRunner.chain
      .then(() => BackgroundTaskRunner.startLocked(context))
      .catch(() => {
        // startLocked already logs; swallow so the chain never rejects.
      });
  }

  static stop(context: common.UIAbilityContext): void {
    BackgroundTaskRunner.chain = BackgroundTaskRunner.chain
      .then(() => BackgroundTaskRunner.stopLocked(context))
      .catch(() => {
        // stopLocked already logs; swallow so the chain never rejects.
      });
  }

  private static async startLocked(context: common.UIAbilityContext): Promise<void> {
    if (BackgroundTaskRunner.running) {
      return;
    }
    try {
      const agent = await BackgroundTaskRunner.getAgent(context);
      await backgroundTaskManager.startBackgroundRunning(
        context,
        backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK,
        agent
      );
      BackgroundTaskRunner.running = true;
      Logger.info('BackgroundTaskRunner: AUDIO_PLAYBACK continuous task started');
    } catch (error) {
      const e = error as BusinessError;
      Logger.warn(`BackgroundTaskRunner.start failed: code=${e.code} message=${e.message}`);
    }
  }

  private static async stopLocked(context: common.UIAbilityContext): Promise<void> {
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

  private static async getAgent(context: common.UIAbilityContext): Promise<WantAgent> {
    if (BackgroundTaskRunner.cachedAgent !== null) {
      return BackgroundTaskRunner.cachedAgent;
    }
    // bundleName/abilityName must come from the runtime context; a hardcoded
    // bundle once drifted from AppScope/app.json5 and silently invalidated
    // the continuous task (background playback was killed within minutes).
    const target: Want = {
      bundleName: context.abilityInfo.bundleName,
      abilityName: context.abilityInfo.name
    };
    const info: wantAgent.WantAgentInfo = {
      wants: [target],
      operationType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    const agent: WantAgent = await wantAgent.getWantAgent(info);
    BackgroundTaskRunner.cachedAgent = agent;
    return agent;
  }
}
