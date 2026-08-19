import { describe, it, expect } from '@ohos/hypium';
import {
  BiliAudioOption,
  selectBiliAudioStream,
  prioritizeBiliStreamUrls
} from '../../../main/ets/network/BiliAudioSelector';

/** Realistic playurl shapes: 30216~64k / 30232~128k / 30280~192k / flac ~1M. */
function track(bandwidth: number, path: string, host: string = 'upos-sz-mirror08c.bilivideo.com'): BiliAudioOption {
  const option = new BiliAudioOption();
  option.bandwidth = bandwidth;
  option.baseUrl = `https://${host}${path}`;
  option.backupUrl = [];
  return option;
}

export default function biliAudioSelectorTest(): void {
  describe('BiliAudioSelector', () => {
    it('selectsHighestTrackInsidePreferredBand', 0, () => {
      const options = [
        track(64000, '/low.m4s'),
        track(128000, '/mid.m4s'),
        track(192000, '/high.m4s')
      ];
      // exhigh -> HIGH band [180,500): only the 192k track fits.
      const picked = selectBiliAudioStream(options, 'exhigh');
      expect(picked!.bitrateKbps).assertEqual(192);
      // high -> MEDIUM band [120,180): only the 128k track fits.
      const mid = selectBiliAudioStream(options, 'high');
      expect(mid!.bitrateKbps).assertEqual(128);
      // standard -> LOW band [60,120): the 64k track.
      const low = selectBiliAudioStream(options, 'standard');
      expect(low!.bitrateKbps).assertEqual(64);
    });

    it('degradesWhenPreferredBandIsEmpty', 0, () => {
      // 320k sits inside the HIGH band [180,500): still the in-band pick.
      const wide = [track(192000, '/a.m4s'), track(320000, '/b.m4s')];
      expect(selectBiliAudioStream(wide, 'exhigh')!.bitrateKbps).assertEqual(320);
      // HIGH/MEDIUM bands empty (550k is lossless-band): exhigh degrades to
      // the LOW band and picks the 64k track.
      const sparse = [track(64000, '/low.m4s'), track(550000, '/flac.m4s')];
      expect(selectBiliAudioStream(sparse, 'exhigh')!.bitrateKbps).assertEqual(64);
      // Nothing below 500k at all: the chain is exhausted and falls back to
      // the highest overall (Android sorted.firstOrNull()).
      const highOnly = [track(550000, '/a.m4s'), track(1200000, '/b.m4s')];
      expect(selectBiliAudioStream(highOnly, 'standard')!.bitrateKbps).assertEqual(1200);
    });

    it('losslessBandSkipsRegularTracksDownToHigh', 0, () => {
      // LOSSLESS band [500,1000) empty -> degrade to HIGH -> 320k.
      const options = [track(320000, '/a.m4s'), track(128000, '/b.m4s')];
      expect(selectBiliAudioStream(options, 'lossless')!.bitrateKbps).assertEqual(320);
    });

    it('emptyListReturnsNull', 0, () => {
      expect(selectBiliAudioStream([], 'exhigh')).assertNull();
    });

    it('unknownQualityKeyFallsBackToLowestBand', 0, () => {
      const options = [track(64000, '/low.m4s'), track(192000, '/high.m4s')];
      expect(selectBiliAudioStream(options, 'bogus')!.bitrateKbps).assertEqual(64);
    });

    it('prioritizesUposHostsOverOtherCdnHosts', 0, () => {
      const urls = prioritizeBiliStreamUrls('https://xy12250.bilivideo.com/a.m4s', [
        'https://b-demo.edge.mountaintoys.cn/c.m4s',
        'https://upos-sz-mirror08c.bilivideo.com/b.m4s'
      ]);
      expect(urls.length).assertEqual(3);
      expect(urls[0].startsWith('https://upos-sz-mirror08c.bilivideo.com/')).assertTrue();
      expect(urls[1].startsWith('https://xy12250.bilivideo.com/')).assertTrue();
      expect(urls[2].startsWith('https://b-demo.edge.mountaintoys.cn/')).assertTrue();
    });

    it('keepsRelativeOrderInsideTierAndDedupes', 0, () => {
      const urls = prioritizeBiliStreamUrls('https://xy1.bilivideo.com/a.m4s', [
        'https://xy2.bilivideo.com/b.m4s',
        'https://xy1.bilivideo.com/a.m4s ',
        ''
      ]);
      expect(urls.length).assertEqual(2);
      expect(urls[0]).assertEqual('https://xy1.bilivideo.com/a.m4s');
      expect(urls[1]).assertEqual('https://xy2.bilivideo.com/b.m4s');
    });
  });
}
