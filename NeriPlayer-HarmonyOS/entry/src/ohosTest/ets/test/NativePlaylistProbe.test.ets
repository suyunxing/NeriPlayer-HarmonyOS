import { describe, it, expect } from '@ohos/hypium';
import { media } from '@kit.MediaKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '../../../main/ets/app/Logger';

const SAMPLE_URL: string = 'https://www.w3schools.com/html/horse.mp3';

function waitState(player: media.AVPlayer, targets: string[], timeoutMs: number): Promise<void> {
  return new Promise<void>((resolve, reject): void => {
    const timer = setTimeout((): void => {
      reject(new Error(`state wait timeout (${targets.join(',')})`));
    }, timeoutMs);
    const check = (): void => {
      const current = player.state;
      if (current !== undefined && targets.indexOf(current) >= 0) {
        clearTimeout(timer);
        player.off('stateChange', check);
        resolve();
      }
    };
    player.on('stateChange', check);
    check();
  });
}

function codeOf(error: BusinessError): string {
  return `err(${error.code}:${error.message ?? ''})`;
}

/** Bounds a call that may never settle; resolves 'hung(>Nms)' instead of pinning hypium. */
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
    Logger.info(`NativePlaylistProbe ${label} issued`);
  });
}

/**
 * API 26 native-playlist probe (AvPlaylistBridge).
 *
 * The bridge ships behind a runtime fallback, so these questions only tune
 * expectations rather than gate the merge — but they are exactly what the
 * SDK text cannot settle:
 *
 * 1. Are addPlaybackMediaSource / advanceToNextMediaSource /
 *    onPlaybackContentChanged / playlistLoopMode implemented at all on this
 *    device class (the setLoudnessGain lesson: @since is not an implementation)?
 * 2. Does a source set via url/setMediaSource coexist with playlist entries —
 *    i.e. does advanceToNextMediaSource land on the pre-added item while the
 *    base source keeps playing?
 * 3. Does the id passed to addPlaybackMediaSource come back as the assigned id,
 *    and is that id what onPlaybackContentChanged delivers?
 *
 * Observe with: hdc shell hilog | grep NativePlaylistProbe
 */
export default function nativePlaylistProbeTest(): void {
  describe('ActsNativePlaylistProbeTest', () => {
    it('playlistSurfaceReachableAndAdvanceMovesContent', 0, async () => {
      const player = await media.createAVPlayer();
      const contentChanges: string[] = [];
      try {
        let loopModeStep: string = 'ok';
        try {
          player.playlistLoopMode = media.PlaylistLoopMode.PLAYLIST_LOOP_MODE_NONE;
        } catch (error) {
          loopModeStep = codeOf(error as BusinessError);
        }
        Logger.info(`NativePlaylistProbe playlistLoopMode=NONE -> ${loopModeStep}`);
        expect(loopModeStep).assertEqual('ok');

        player.onPlaybackContentChanged((id: string): void => {
          contentChanges.push(id);
          Logger.info(`NativePlaylistProbe onPlaybackContentChanged id=${id}`);
        });

        player.url = SAMPLE_URL;
        await waitState(player, ['initialized'], 20000);
        await player.prepare();
        await waitState(player, ['prepared'], 20000);
        await player.play();
        await waitState(player, ['playing'], 10000);
        Logger.info('NativePlaylistProbe base source playing; adding playlist entry');

        const added = await withTimeout<string>(
          'addPlaybackMediaSource',
          player.addPlaybackMediaSource(media.createMediaSourceWithUrl(SAMPLE_URL), 'probe:1'),
          10000
        );
        const addedText: string = added as string;
        Logger.info(`NativePlaylistProbe addPlaybackMediaSource -> ${addedText}`);
        // The call must settle, and when it succeeds the assigned id must be
        // usable for remove/onPlaybackContentChanged matching.
        expect(addedText === 'hung(>10000ms)').assertFalse();

        const before = contentChanges.length;
        const advance = await withTimeout<void>(
          'advanceToNextMediaSource',
          player.advanceToNextMediaSource(),
          10000
        );
        const advanceText: string = advance as string;
        Logger.info(`NativePlaylistProbe advanceToNextMediaSource -> ${advanceText} `
          + `contentChanges=${contentChanges.length - before}`);
        expect(advanceText === 'hung(>10000ms)').assertFalse();

        const remove = await withTimeout<void>(
          'removePlaybackMediaSource',
          player.removePlaybackMediaSource(addedText.length > 0 && addedText.indexOf('err(') < 0
            ? addedText : 'probe:1'),
          10000
        );
        Logger.info(`NativePlaylistProbe removePlaybackMediaSource -> ${remove as string}`);

        const clear = await withTimeout<void>('clearPlaybackList', player.clearPlaybackList(), 10000);
        Logger.info(`NativePlaylistProbe clearPlaybackList -> ${clear as string}`);
      } finally {
        await player.release();
      }
    });

    /**
     * With looping pinned to NONE the list must never move on its own: after
     * one manual advance, a second advance against an empty/removed list has
     * to fail or no-op rather than replay something — the sleep-timer and
     * listen-together arbitration in PlayerManager depends on that.
     */
    it('loopModeNoneNeverAdvancesByItself', 0, async () => {
      const player = await media.createAVPlayer();
      const contentChanges: string[] = [];
      try {
        player.playlistLoopMode = media.PlaylistLoopMode.PLAYLIST_LOOP_MODE_NONE;
        player.onPlaybackContentChanged((id: string): void => {
          contentChanges.push(id);
        });
        player.url = SAMPLE_URL;
        await waitState(player, ['initialized'], 20000);
        await player.addPlaybackMediaSource(media.createMediaSourceWithUrl(SAMPLE_URL), 'probe:2');
        await player.prepare();
        await waitState(player, ['prepared'], 20000);
        await player.play();
        await waitState(player, ['playing'], 10000);

        // No interaction for 5s: an unsolicited content change would mean the
        // kernel auto-advances even under NONE — a blocker for the bridge.
        await new Promise<void>((resolve): void => {
          setTimeout((): void => {
            resolve();
          }, 5000);
        });
        Logger.info(`NativePlaylistProbe idleWindow contentChanges=${contentChanges.length}`);
        expect(contentChanges.length).assertEqual(0);
      } finally {
        await player.release();
      }
    });
  });
}
