import { describe, it, expect } from '@ohos/hypium';
import {
  isBiliStreamUrl,
  buildBiliStreamHeaders,
  streamHeadersFor,
  BILI_STREAM_REFERER,
  BILI_STREAM_USER_AGENT
} from '../../../main/ets/network/StreamHeaders';

export default function streamHeadersTest(): void {
  describe('StreamHeaders', () => {
    it('isBiliStreamUrlMatchesCdnHosts', 0, () => {
      // Real shapes: upos mirrors, plain bilivideo hosts, mountaintoys edge.
      expect(isBiliStreamUrl('https://upos-sz-mirror08c.bilivideo.com/xxx.m4s')).assertTrue();
      expect(isBiliStreamUrl('https://xy12250.bilivideo.com/audio.m4s?e=1')).assertTrue();
      expect(isBiliStreamUrl('https://xy.example.bilivideo.cn/audio.m4s')).assertTrue();
      expect(isBiliStreamUrl('https://xy.example.mcdn.bilivideo.cn/audio.m4s')).assertTrue();
      expect(isBiliStreamUrl('http://b-demo.edge.mountaintoys.cn/a.m4s')).assertTrue();
      expect(isBiliStreamUrl('https://upos-sz-mirror08c.bilivideo.com:4483/a.m4s')).assertTrue();
      // Non-bili hosts stay header-less.
      expect(isBiliStreamUrl('https://music.163.com/stream.mp3')).assertFalse();
      expect(isBiliStreamUrl('http://localhost/audio.mp3')).assertFalse();
      expect(isBiliStreamUrl('fd://12')).assertFalse();
      expect(isBiliStreamUrl('')).assertFalse();
      // Look-alike hosts without the bilivideo label must not match.
      expect(isBiliStreamUrl('https://notbilivideo.com/a.m4s')).assertFalse();
    });

    it('buildBiliStreamHeadersForcesRefererAndUa', 0, () => {
      const headers = buildBiliStreamHeaders('');
      expect(headers['Referer']).assertEqual(BILI_STREAM_REFERER);
      expect(headers['User-Agent']).assertEqual(BILI_STREAM_USER_AGENT);
      expect(headers['Cookie']).assertUndefined();
    });

    it('buildBiliStreamHeadersAppendsCookieWhenPresent', 0, () => {
      const headers = buildBiliStreamHeaders('  SESSDATA=abc; buvid3=xyz  ');
      expect(headers['Referer']).assertEqual(BILI_STREAM_REFERER);
      expect(headers['Cookie']).assertEqual('SESSDATA=abc; buvid3=xyz');
    });

    it('streamHeadersForKeepsOtherSourcesHeaderLess', 0, () => {
      const netease = streamHeadersFor('https://music.163.com/a.mp3', 'SESSDATA=x');
      expect(Object.keys(netease).length).assertEqual(0);
      const local = streamHeadersFor('fd://3', 'SESSDATA=x');
      expect(Object.keys(local).length).assertEqual(0);
    });

    it('streamHeadersForBuildsFullBiliSet', 0, () => {
      const headers = streamHeadersFor('https://upos-sz-mirror08c.bilivideo.com/a.m4s', 'SESSDATA=x');
      expect(Object.keys(headers).length).assertEqual(3);
      expect(headers['Referer']).assertEqual('https://www.bilibili.com');
      expect(headers['User-Agent'].startsWith('Mozilla/5.0 (Windows NT 10.0; Win64; x64)')).assertTrue();
      expect(headers['Cookie']).assertEqual('SESSDATA=x');
    });
  });
}
