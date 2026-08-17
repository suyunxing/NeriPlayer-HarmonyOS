import { describe, it, expect } from '@ohos/hypium';
import { HttpHeaderParser } from '../../../main/ets/network/HttpHeaderParser';

/**
 * Regression tests for the NetEase QR login cookie bug: HarmonyOS
 * HttpResponse.header is an Object with set-cookie as an array, and the old
 * regex-over-JSON.stringify text never matched, so MUSIC_U was lost.
 */
export default function httpHeaderParserTest(): void {
  describe('HttpHeaderParser', () => {
    it('normalizesHarmonyObjectHeaderWithSetCookieArray', 0, () => {
      const header: Record<string, Object> = {};
      header['content-type'] = 'application/json';
      header['x-refresh-token'] = 'rt456';
      const setCookies: Object[] = [
        'MUSIC_U=tok123; Max-Age=31536000; Path=/; HttpOnly',
        '__csrf=abc456; Path=/'
      ];
      header['set-cookie'] = setCookies;
      const text = HttpHeaderParser.toHeaderText(header as Object);
      expect(text.includes('set-cookie: MUSIC_U=tok123; Max-Age=31536000; Path=/; HttpOnly')).assertTrue();
      expect(text.includes('x-refresh-token: rt456')).assertTrue();
      // NeteaseQrLogin.readRefreshToken contract on normalized text.
      const match = /x-refresh-token:\s*([^\r\n;]+)/i.exec(text);
      expect(match !== null).assertTrue();
      expect(match![1]).assertEqual('rt456');
      const pairs = HttpHeaderParser.extractCookiePairs(text);
      expect(pairs.size).assertEqual(2);
      expect(pairs.get('MUSIC_U')).assertEqual('tok123');
      expect(pairs.get('__csrf')).assertEqual('abc456');
    });

    it('parsesRawHeaderTextLines', 0, () => {
      const text = 'Content-Type: application/json\r\n'
        + 'Set-Cookie: MUSIC_U=raw; Path=/\r\n'
        + 'Set-Cookie: NMTID=n1\r\n';
      const pairs = HttpHeaderParser.extractCookiePairs(text);
      expect(pairs.size).assertEqual(2);
      expect(pairs.get('MUSIC_U')).assertEqual('raw');
      expect(pairs.get('NMTID')).assertEqual('n1');
    });

    it('splitsCommaJoinedSetCookieValues', 0, () => {
      const text = 'set-cookie: MUSIC_U=tok; Max-Age=1; Path=/, __csrf=abc; Path=/';
      const pairs = HttpHeaderParser.extractCookiePairs(text);
      expect(pairs.size).assertEqual(2);
      expect(pairs.get('MUSIC_U')).assertEqual('tok');
      expect(pairs.get('__csrf')).assertEqual('abc');
    });

    it('dropsExpiresDateDebrisFromCommaSplit', 0, () => {
      const text = 'Set-Cookie: v=1; Expires=Wed, 21 Oct 2015 07:28:00 GMT; Path=/';
      const pairs = HttpHeaderParser.extractCookiePairs(text);
      expect(pairs.size).assertEqual(1);
      expect(pairs.get('v')).assertEqual('1');
      expect(pairs.get('Expires')).assertUndefined();
    });

    it('keepsLastValueOnDuplicateCookieNames', 0, () => {
      const text = 'Set-Cookie: MUSIC_U=old; Path=/\r\nSet-Cookie: MUSIC_U=new; Path=/';
      const pairs = HttpHeaderParser.extractCookiePairs(text);
      expect(pairs.size).assertEqual(1);
      expect(pairs.get('MUSIC_U')).assertEqual('new');
    });

    it('returnsEmptyForPlainStringHeader', 0, () => {
      expect(HttpHeaderParser.toHeaderText('raw')).assertEqual('raw');
      expect(HttpHeaderParser.extractCookiePairs('content-type: text/html').size).assertEqual(0);
    });
  });
}
