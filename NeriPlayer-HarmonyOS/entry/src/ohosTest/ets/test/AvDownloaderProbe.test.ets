import { describe, it, expect } from '@ohos/hypium';
import { media } from '@kit.MediaKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '../../../main/ets/app/Logger';

const SAMPLE_URL: string = 'https://www.w3schools.com/html/horse.mp3';
const DOWNLOAD_WINDOW_MS = 90000;

function codeOf(error: BusinessError): string {
  return `err(${error.code}:${error.message ?? ''})`;
}

function withTimeout<T>(label: string, work: Promise<T>, ms: number): Promise<T | string> {
  return new Promise<T | string>((resolve): void => {
    let settled: boolean = false;
    const timer = setTimeout((): void => {
      if (!settled) {
        settled = true;
        resolve(`hung(>${ms}ms)`);
      }
    }, ms);
    work.then((value: T): void => {
      if (!settled) {
        settled = true;
        clearTimeout(timer);
        resolve(value);
      }
    }).catch((error: BusinessError): void => {
      if (!settled) {
        settled = true;
        clearTimeout(timer);
        resolve(codeOf(error) as T | string);
      }
    });
    Logger.info(`AvDownloaderProbe ${label} issued`);
  });
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve): void => {
    setTimeout((): void => {
      resolve();
    }, ms);
  });
}

/**
 * API 26 AVDownloaderManager probe (PlaybackCacheManager).
 *
 * The cache ships opt-in (np.playback_cache) with a runtime fallback, so this
 * probe decides whether the feature is real on a device class rather than
 * whether the code compiles:
 *
 * 1. Does createAVDownloaderManager resolve at all (the setLoudnessGain
 *    lesson: a @since tag is not an implementation — watch for hung)?
 * 2. Does addAVDownloadTask actually download a small public MP3 to
 *    completion, and does onStatusChange report the transition?
 * 3. Is the completed task's cache directory readable, and does
 *    createMediaSourceWithDirectory produce a source AVPlayer can prepare —
 *    i.e. is the whole cache-hit path of loadSong viable offline?
 *
 * Observe with: hdc shell hilog | grep AvDownloaderProbe
 */
export default function avDownloaderProbeTest(): void {
  describe('ActsAvDownloaderProbeTest', () => {
    it('downloadsCachesAndPlaysFromDirectory', 0, async () => {
      const created = await withTimeout<media.AVDownloaderManager>(
        'createAVDownloaderManager',
        media.createAVDownloaderManager(),
        10000
      );
      if (typeof created === 'string') {
        // A hang or a documented error is the finding itself; record and stop
        // (the product keeps its fallback either way).
        Logger.info(`AvDownloaderProbe createAVDownloaderManager -> ${created}`);
        return;
      }
      const manager: media.AVDownloaderManager = created;
      Logger.info('AvDownloaderProbe manager created');
      try {
        // System default is Wi-Fi only; make the policy explicit so the log
        // shows which path a device actually takes.
        manager.allowsCellularAccess(false);
        manager.setRequestTimeout(15000);
        Logger.info('AvDownloaderProbe policy calls ok (allowsCellularAccess/setRequestTimeout)');
      } catch (error) {
        Logger.info(`AvDownloaderProbe policy calls ${codeOf(error as BusinessError)}`);
      }

      const states: string[] = [];
      manager.onStatusChange((taskId: string, state: media.AVDownloadTaskState): void => {
        states.push(`${taskId}:${state}`);
        Logger.info(`AvDownloaderProbe onStatusChange ${taskId} -> ${state}`);
      });

      let taskId = '';
      try {
        taskId = manager.addAVDownloadTask(media.createMediaSourceWithUrl(SAMPLE_URL));
        Logger.info(`AvDownloaderProbe addAVDownloadTask -> ${taskId}`);
      } catch (error) {
        Logger.info(`AvDownloaderProbe addAVDownloadTask threw ${codeOf(error as BusinessError)}`);
      }
      expect(taskId.length > 0).assertTrue();

      // Poll to a terminal state within the window; states[] also gets the
      // event-driven history for cross-checking.
      let terminal = '';
      const deadline = Date.now() + DOWNLOAD_WINDOW_MS;
      while (Date.now() < deadline) {
        const state = manager.getTaskStatus(taskId);
        if (state === 'completed' || state === 'error' || state === 'removing') {
          terminal = state;
          break;
        }
        await sleep(1000);
      }
      Logger.info(`AvDownloaderProbe terminal=${terminal.length > 0 ? terminal : 'window-expired'} `
        + `progress=${manager.getTaskProgress(taskId)} events=[${states.join(',')}]`);

      if (terminal !== 'completed') {
        // The finding itself; assert only that the task reported *something*
        // documented rather than silently vanishing.
        expect(terminal.length > 0 || states.length > 0).assertTrue();
        return;
      }

      const cacheDir = manager.getTaskCacheDirectory(taskId);
      Logger.info(`AvDownloaderProbe cacheDir=${cacheDir}`);
      expect(cacheDir.length > 0).assertTrue();

      // The cache-hit path loadSong relies on: directory -> MediaSource ->
      // prepare. If this step fails on device, hits must be dropped (the
      // manager already does) and the finding recorded here.
      const player = await media.createAVPlayer();
      try {
        const source = await withTimeout<media.MediaSource | undefined>(
          'createMediaSourceWithDirectory',
          media.createMediaSourceWithDirectory(cacheDir),
          10000
        );
        if (typeof source === 'string') {
          Logger.info(`AvDownloaderProbe createMediaSourceWithDirectory -> ${source}`);
          expect(false).assertTrue();
          return;
        }
        const typed = source;
        await player.setMediaSource(typed);
        await new Promise<void>((resolve, reject): void => {
          const timer = setTimeout((): void => {
            reject(new Error('state wait timeout (initialized)'));
          }, 20000);
          const check = (): void => {
            if (player.state === 'initialized') {
              clearTimeout(timer);
              player.off('stateChange', check);
              resolve();
            }
          };
          player.on('stateChange', check);
          check();
        });
        await player.prepare();
        Logger.info(`AvDownloaderProbe offline prepare ok state=${player.state} `
          + `duration=${player.duration}`);
        expect(player.state).assertEqual('prepared');
      } finally {
        await player.release();
      }
    });
  });
}
