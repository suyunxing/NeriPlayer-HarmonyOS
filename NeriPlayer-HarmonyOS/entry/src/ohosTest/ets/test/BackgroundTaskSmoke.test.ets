import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BackgroundTaskRunner } from '../../../main/ets/player/BackgroundTaskRunner';

const TAG = 'backgroundTaskSmoke';
const POLL_TIMEOUT_MS = 10000;

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve) => setTimeout(resolve, ms));
}

async function hasAudioPlaybackTask(context: common.UIAbilityContext): Promise<boolean> {
  const tasks: Array<backgroundTaskManager.ContinuousTaskInfo> =
    await backgroundTaskManager.getAllContinuousTasks(context);
  return tasks.some((task: backgroundTaskManager.ContinuousTaskInfo) =>
    task.backgroundModes.indexOf('audioPlayback') >= 0);
}

/**
 * Registers/unregisters the AUDIO_PLAYBACK continuous task through the real
 * BackgroundTaskRunner and verifies registration via getAllContinuousTasks.
 * A wantAgent whose bundleName drifted from app.json5 (the bug that let the
 * system kill background playback within minutes) fails here at the
 * "task registered" assertion, not only on a locked-screen long run.
 */
export default function backgroundTaskSmokeTest(): void {
  describe('ActsBackgroundTaskSmokeTest', () => {
    it('audioPlaybackTaskRegistersAndReleases', 0, async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      const ability = await delegator.getCurrentTopAbility();
      const context = ability.context as common.UIAbilityContext;
      expect(context.abilityInfo.bundleName.indexOf('neriplayer') >= 0).assertTrue();

      BackgroundTaskRunner.init(context);
      BackgroundTaskRunner.start(context);

      let registered = false;
      const deadline = Date.now() + POLL_TIMEOUT_MS;
      while (Date.now() < deadline) {
        registered = await hasAudioPlaybackTask(context);
        if (registered) {
          break;
        }
        await sleep(500);
      }
      hilog.info(0x0000, TAG, 'continuous task registered=%{public}d', registered ? 1 : 0);
      expect(registered).assertTrue();

      BackgroundTaskRunner.stop(context);
      let stillPresent = true;
      const stopDeadline = Date.now() + POLL_TIMEOUT_MS;
      while (Date.now() < stopDeadline) {
        stillPresent = await hasAudioPlaybackTask(context);
        if (!stillPresent) {
          break;
        }
        await sleep(500);
      }
      hilog.info(0x0000, TAG, 'continuous task present after stop=%{public}d', stillPresent ? 1 : 0);
      expect(stillPresent).assertFalse();
    });
  });
}
