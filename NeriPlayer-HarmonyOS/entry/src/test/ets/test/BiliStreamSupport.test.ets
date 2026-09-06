import { describe, it, expect } from '@ohos/hypium';
import { BiliStreamSupport } from '../../../main/ets/network/BiliStreamSupport';

/**
 * Regression tests for the "logged-in Bilibili playback is silent" bug: the
 * CDN stream fetch went out with no Referer/UA (and the playurl candidates
 * were used without host preference), so prepare() failed and the position
 * stayed at 0. These tests pin the pure host/header/candidate logic.
 */
export default function biliStreamSupportTest(): void {
  describe('BiliStreamSupport', () => {
    it('recognizesBilibiliCdnHostsOnly', 0, () => {
      expect(BiliStreamSupport.isBiliStreamUrl(
        'https://upos-sz-mirror08h.bilivideo.com/audio.m4s?e=1')).assertTrue();
      expect(BiliStreamSupport.isBiliStreamUrl(
        'https://mn404-404.bilivideo.com/audio.m4s')).assertTrue();
      expect(BiliStreamSupport.isBiliStreamUrl(
        'http://xy-cdn.mountaintoys.cn/audio.m4s')).assertTrue();
      // Real-world mountaintoys mirrors carry an explicit :4483 port.
      expect(BiliStreamSupport.isBiliStreamUrl(
        'https://b-baaa9i31dolg49uwpj3u2qiz4d.edge.mountaintoys.cn:4483/audio.m4s')).assertTrue();
      expect(BiliStreamSupport.isBiliStreamUrl(
        'https://api.bilibili.com/x/player/playurl')).assertFalse();
      expect(BiliStreamSupport.isBiliStreamUrl(
        'https://music.126.net/song.mp3')).assertFalse();
      expect(BiliStreamSupport.isBiliStreamUrl('')).assertFalse();
    });

    it('buildsRefererAndUaHeadersForCdnUrls', 0, () => {
      const headers = BiliStreamSupport.buildStreamHeaders(
        'https://upos-sz-mirror08h.bilivideo.com/audio.m4s', '');
      expect(headers !== null).assertTrue();
      expect(headers!['Referer']).assertEqual('https://www.bilibili.com');
      expect(headers!['User-Agent']).assertEqual(BiliStreamSupport.BILI_WEB_UA);
      expect(headers!['User-Agent'].indexOf('Chrome/124')).assertLargerOrEqual(0);
      // No cookie header when the jar entry is empty.
      expect(headers!['Cookie']).assertUndefined();
    });

    it('appendsCookieHeaderWhenPresent', 0, () => {
      const headers = BiliStreamSupport.buildStreamHeaders(
        'https://upos-sz-mirror08h.bilivideo.com/audio.m4s',
        'SESSDATA=abc; buvid3=fp1');
      expect(headers !== null).assertTrue();
      expect(headers!['Cookie']).assertEqual('SESSDATA=abc; buvid3=fp1');
    });

    it('returnsNullForNonBilibiliUrls', 0, () => {
      expect(BiliStreamSupport.buildStreamHeaders(
        'https://music.126.net/song.mp3', 'MUSIC_U=x')).assertNull();
      expect(BiliStreamSupport.buildStreamHeaders(
        'file:///data/storage/el2/base/haps/entry/files/a.mp3', '')).assertNull();
    });

    it('prefersUposMirrorAndForcesHttps', 0, () => {
      // Real-world shape: mountaintoys baseUrl with a port, upos backups.
      const picked = BiliStreamSupport.pickBestStreamUrl([
        'https://b-baaa9i31dolg49uwpj3u2qiz4d.edge.mountaintoys.cn:4483/audio.m4s',
        'https://upos-sz-mirrorcoso1.bilivideo.com/audio.m4s',
        'http://mn404-404.bilivideo.com/audio.m4s'
      ]);
      expect(picked).assertEqual('https://upos-sz-mirrorcoso1.bilivideo.com/audio.m4s');
    });

    it('buildsHeadersForPortedMountaintoysUrl', 0, () => {
      const headers = BiliStreamSupport.buildStreamHeaders(
        'https://b-baaa9i31dolg49uwpj3u2qiz4d.edge.mountaintoys.cn:4483/audio.m4s', '');
      expect(headers !== null).assertTrue();
      expect(headers!['Referer']).assertEqual('https://www.bilibili.com');
    });

    it('fallsBackToFirstChoiceWithoutUposHost', 0, () => {
      const picked = BiliStreamSupport.pickBestStreamUrl([
        'http://xy-cdn.mountaintoys.cn/audio.m4s',
        'http://mn404-404.bilivideo.com/audio.m4s'
      ]);
      expect(picked).assertEqual('https://mn404-404.bilivideo.com/audio.m4s');
    });

    it('returnsEmptyStringWithoutCandidates', 0, () => {
      expect(BiliStreamSupport.pickBestStreamUrl([])).assertEqual('');
    });
  });
}
