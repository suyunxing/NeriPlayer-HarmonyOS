import { describe, it, expect } from '@ohos/hypium';
import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { YouTubeMusicApi } from '../../../main/ets/network/YouTubeMusicApi';
import { YtmStreamResolver } from '../../../main/ets/network/ytm/YtmStreamResolver';
import { SettingsRepository } from '../../../main/ets/data/SettingsRepository';
import { HttpClient } from '../../../main/ets/network/HttpClient';
import { YtmLoopbackStreamBridge } from '../../../main/ets/network/ytm/YtmLoopbackStreamBridge';

const LOG_TAG = 'ytmSmoke';
const MAX_RESOLVE_CANDIDATES = 3;
// QEMU NAT host alias (same as the Android emulator); the host runs a Clash
// proxy on 7897. Only used when no explicit proxy is configured already.
const EMULATOR_PROXY_HOST = '10.0.2.2';
const EMULATOR_PROXY_PORT = 7897;

function ensureProxyConfigured(): void {
  const host = SettingsRepository.getString(SettingsRepository.KEY_PROXY_HOST, '');
  const port = SettingsRepository.getNumber(SettingsRepository.KEY_PROXY_PORT, 0);
  if (host.length > 0 && port > 0) {
    HttpClient.applyConfiguredProxy();
    hilog.info(0x0000, LOG_TAG, 'using configured proxy %{public}s:%{public}d', host, port);
    return;
  }
  SettingsRepository.setString(SettingsRepository.KEY_PROXY_HOST, EMULATOR_PROXY_HOST);
  SettingsRepository.setNumber(SettingsRepository.KEY_PROXY_PORT, EMULATOR_PROXY_PORT);
  HttpClient.applyConfiguredProxy();
  hilog.info(
    0x0000, LOG_TAG,
    'no proxy configured, defaulted to emulator NAT host %{public}s:%{public}d',
    EMULATOR_PROXY_HOST, EMULATOR_PROXY_PORT
  );
}

function waitState(player: media.AVPlayer, targets: string[], timeoutMs: number): Promise<void> {
  return new Promise<void>((resolve, reject) => {
    const timer = setTimeout(() => {
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

/**
 * Real-network YouTube Music playback smoke (M6.5): innertube search ->
 * IOS direct stream resolution (D2 primary path, no JS runtime) -> AVPlayer
 * plays the googlevideo URL without custom headers. Requires a network that
 * can reach youtube.com/googlevideo.com (mainland China needs a proxy).
 */
export default function ytmPlaybackSmokeTest(): void {
  describe('ActsYtmPlaybackSmokeTest', () => {
    it('searchesResolvesAndPlaysIosDirectStream', 0, async () => {
      YtmStreamResolver.resetForTest();
      ensureProxyConfigured();

      const songs = await YouTubeMusicApi.search('Linkin Park Numb', 8);
      expect(songs.length > 0).assertTrue();
      hilog.info(0x0000, LOG_TAG, 'search returned %{public}d songs', songs.length);

      let url = '';
      let playedVideoId = '';
      const failures: string[] = [];
      const candidates = Math.min(songs.length, MAX_RESOLVE_CANDIDATES);
      for (let i = 0; i < candidates; i++) {
        const videoId = songs[i].audioId;
        try {
          url = await YtmStreamResolver.resolveStreamUrl(videoId, 'high');
          playedVideoId = videoId;
          break;
        } catch (error) {
          const e = error as Error;
          failures.push(`${videoId}: ${e.message}`);
          hilog.warn(0x0000, LOG_TAG, 'resolve failed for candidate %{public}s', videoId);
        }
      }
      if (url.length === 0) {
        throw new Error(`all ${candidates} resolve candidates failed (${failures.join(' ; ')})`);
      }
      // Never log the URL itself: googlevideo links carry auth tokens.
      expect(url.includes('googlevideo.com')).assertTrue();
      hilog.info(
        0x0000, LOG_TAG,
        'resolved direct url for %{public}s (len=%{public}d)', playedVideoId, url.length
      );

      const player = await media.createAVPlayer();
      const bridge = new YtmLoopbackStreamBridge();
      player.on('error', (error) => {
        hilog.error(
          0x0000, LOG_TAG,
          'AVPlayer error code=%{public}d message=%{public}s', error.code, error.message
        );
      });
      try {
        const loopbackUrl = await bridge.start(url);
        await player.setMediaSource(media.createMediaSourceWithUrl(loopbackUrl));
        await waitState(player, ['initialized'], 30000);
        await player.prepare();
        await waitState(player, ['prepared'], 30000);
        expect(player.duration > 0).assertTrue();
        hilog.info(0x0000, LOG_TAG, 'prepared, duration=%{public}d', player.duration);
        player.audioInterruptMode = audio.InterruptMode.SHARE_MODE;
        await player.play();
        await waitState(player, ['playing'], 15000);
        expect(player.state).assertEqual('playing');
        await player.pause();
        await waitState(player, ['paused'], 15000);
        expect(player.state).assertEqual('paused');
      } finally {
        await bridge.stop();
        await player.release();
      }
    });
  });
}
