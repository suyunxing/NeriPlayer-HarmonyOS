import { describe, it, expect } from '@ohos/hypium';
import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BiliApi } from '../../../main/ets/network/BiliApi';
import { isBiliStreamUrl, streamHeadersFor } from '../../../main/ets/network/StreamHeaders';

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
 * Real-network Bilibili playback smoke: search -> resolveAudioUrl -> AVPlayer
 * fetches the DASH stream itself with Referer/UA headers attached (without
 * them the bilivideo CDN answers 403 and prepare fails). This closes the gap
 * that Bilibili stream URLs were never actually played back on-device.
 */
export default function biliPlaybackSmokeTest(): void {
  describe('ActsBiliPlaybackSmokeTest', () => {
    it('searchesResolvesAndPlaysWithBiliHeaders', 0, async () => {
      const songs = await BiliApi.search('周杰伦 晴天', 5);
      expect(songs.length > 0).assertTrue();
      const bvid = songs[0].audioId;
      expect(bvid.length > 0).assertTrue();
      hilog.info(0x0000, 'biliSmoke', 'candidate bvid=%{public}s', bvid);

      const url = await BiliApi.resolveAudioUrl(bvid);
      expect(url.length > 0).assertTrue();
      hilog.info(0x0000, 'biliSmoke', 'stream host check urlLen=%{public}d', url.length);
      // Resolved DASH audio URLs must live on a Bilibili CDN host so the
      // header injection path below is the one real playback uses.
      expect(isBiliStreamUrl(url)).assertTrue();

      const headers = streamHeadersFor(url, '');
      expect(headers['Referer']).assertEqual('https://www.bilibili.com');
      expect(headers['User-Agent'].length > 0).assertTrue();

      const player = await media.createAVPlayer();
      try {
        await player.setMediaSource(media.createMediaSourceWithUrl(url, headers));
        await waitState(player, ['initialized'], 20000);
        await player.prepare();
        await waitState(player, ['prepared'], 20000);
        player.audioInterruptMode = audio.InterruptMode.SHARE_MODE;
        await player.play();
        await waitState(player, ['playing'], 10000);
        expect(player.state).assertEqual('playing');
        await player.pause();
        await waitState(player, ['paused'], 10000);
        expect(player.state).assertEqual('paused');
      } finally {
        await player.release();
      }
    });
  });
}
