import { describe, it, expect } from '@ohos/hypium';
import { media } from '@kit.MediaKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BiliApi } from '../../../main/ets/network/BiliApi';
import { BiliStreamSupport } from '../../../main/ets/network/BiliStreamSupport';
import { HttpClient } from '../../../main/ets/network/HttpClient';
import { Constants } from '../../../main/ets/app/Constants';

interface PopularItem {
  bvid: string;
}

interface PopularData {
  list?: PopularItem[];
}

interface PopularResponse {
  code: number;
  data?: PopularData;
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
 * End-to-end bilibili playback smoke (needs network): playurl cid flow ->
 * stream headers -> AVPlayer prepare over the real CDN. Regression test for
 * the "logged-in bilibili playback stays silent at 0:00" bug where playurl
 * answered -400 (missing cid) and the CDN rejected header-less fetches.
 */
export default function biliPlaybackSmokeTest(): void {
  describe('ActsBiliPlaybackSmokeTest', () => {
    it('resolvesAndPreparesBiliAudioWithStreamHeaders', 0, async () => {
      // Pick a currently valid video instead of a hard-coded bvid.
      const popularText = await HttpClient.getText(
        `${Constants.BILI_BASE}/x/web-interface/popular?ps=5`,
        { 'Referer': 'https://www.bilibili.com' },
        15000,
        true
      );
      const popular = JSON.parse(popularText) as PopularResponse;
      expect(popular.code).assertEqual(0);
      const list = popular.data?.list ?? [];
      expect(list.length > 0).assertTrue();
      const bvid = list[0].bvid;
      hilog.info(0x4E50, 'biliSmoke', 'bvid=%{public}s', bvid);

      // Full resolution chain: view cid -> playurl -> best CDN candidate.
      const url = await BiliApi.resolveAudioUrl(bvid);
      expect(url.length > 0).assertTrue();
      expect(BiliStreamSupport.isBiliStreamUrl(url)).assertTrue();

      // The CDN requires Referer/UA on the media fetch (403 otherwise).
      const headers = BiliApi.streamHeadersFor(url);
      expect(headers !== null).assertTrue();
      expect(headers!['Referer']).assertEqual('https://www.bilibili.com');
      expect(headers!['User-Agent'] !== undefined).assertTrue();

      const player = await media.createAVPlayer();
      try {
        await player.setMediaSource(media.createMediaSourceWithUrl(url, headers!));
        await waitState(player, ['initialized'], 20000);
        await player.prepare();
        await waitState(player, ['prepared'], 30000);
        expect(player.state).assertEqual('prepared');
        expect(player.duration > 0).assertTrue();
      } finally {
        await player.release();
      }
    });
  });
}
