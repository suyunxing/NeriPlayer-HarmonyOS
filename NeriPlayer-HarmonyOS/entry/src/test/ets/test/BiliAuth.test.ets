import { describe, it, expect } from '@ohos/hypium';
import {
  BiliAuthBundle,
  BiliAuthHealthState,
  evaluateBiliAuthHealth,
  validateAndSanitizeBiliCookies,
  biliMidFromCookies,
  buildBiliCookieHeader,
  biliCookieKeysForLog
} from '../../../main/ets/data/auth/BiliAuth';
import { parseRawCookieText } from '../../../main/ets/data/auth/RawCookieTextParser';
import { parseRawCookieText as parseViaNeteaseReExport } from '../../../main/ets/data/auth/NeteaseAuth';

function mapOf(pairs: string[][]): Map<string, string> {
  const out = new Map<string, string>();
  for (const pair of pairs) {
    out.set(pair[0], pair[1]);
  }
  return out;
}

const MINUTE_MS = 60 * 1000;
const HOUR_MS = 60 * MINUTE_MS;
const DAY_MS = 24 * HOUR_MS;

export default function biliAuthTest(): void {
  describe('BiliAuth', () => {
    it('bundleJsonRoundTripDropsBlankKeysAndKeepsSavedAt', 0, () => {
      const bundle = new BiliAuthBundle();
      bundle.cookies = mapOf([
        ['SESSDATA', 'sess%2Ctoken'],
        ['bili_jct', 'jct123'],
        ['', 'dropped']
      ]);
      bundle.savedAt = 1723800000000;
      const restored = BiliAuthBundle.fromJson(bundle.toJson());
      expect(restored.cookies.size).assertEqual(2);
      expect(restored.cookies.get('SESSDATA')).assertEqual('sess%2Ctoken');
      expect(restored.cookies.get('bili_jct')).assertEqual('jct123');
      expect(restored.savedAt).assertEqual(1723800000000);
    });

    it('bundleFromCorruptJsonFallsBackToEmpty', 0, () => {
      const restored = BiliAuthBundle.fromJson('{"cookies": not json');
      expect(restored.cookies.size).assertEqual(0);
      expect(restored.hasLoginCookies()).assertFalse();
    });

    it('healthMissingWithOnlyBuvid', 0, () => {
      const bundle = new BiliAuthBundle();
      bundle.cookies = mapOf([['buvid3', 'abc'], ['sid', 'x']]);
      const health = evaluateBiliAuthHealth(bundle, Date.now());
      expect(health.state).assertEqual(BiliAuthHealthState.MISSING);
    });

    it('healthMissingWithoutSessdata', 0, () => {
      const bundle = new BiliAuthBundle();
      bundle.cookies = mapOf([['DedeUserID', '42'], ['bili_jct', 'jct']]);
      const health = evaluateBiliAuthHealth(bundle, Date.now());
      expect(health.state).assertEqual(BiliAuthHealthState.MISSING);
    });

    it('healthKeepsSavedCookieValidWithoutExpiryCheck', 0, () => {
      const now = Date.now();
      const bundle = new BiliAuthBundle();
      bundle.cookies = mapOf([['SESSDATA', 'old'], ['DedeUserID', '42'], ['bili_jct', 'jct']]);
      bundle.savedAt = now - 90 * DAY_MS;
      const health = evaluateBiliAuthHealth(bundle, now);
      expect(health.state).assertEqual(BiliAuthHealthState.VALID);
      expect(health.loginCookieKeys.length).assertEqual(3);
      expect(health.ageMs).assertEqual(90 * DAY_MS);
    });

    it('healthValidForRecentCookie', 0, () => {
      const now = Date.now();
      const bundle = new BiliAuthBundle();
      bundle.cookies = mapOf([['SESSDATA', 'fresh']]);
      bundle.savedAt = now - 1000;
      const health = evaluateBiliAuthHealth(bundle, now);
      expect(health.state).assertEqual(BiliAuthHealthState.VALID);
      // hypium assertEqual is strict (===): compare array content as text.
      expect(health.loginCookieKeys.join('|')).assertEqual('SESSDATA');
    });

    it('sanitizeRejectsMalformedEntries', 0, () => {
      const validation = validateAndSanitizeBiliCookies(mapOf([
        ['SESSDATA', 'ok'],
        ['bad;name', 'v'],
        ['with;semi', 'a;b'],
        ['ctrl', 'a\u0007b'],
        ['empty', '']
      ]));
      expect(validation.isAccepted).assertTrue();
      expect(validation.sanitizedCookies.size).assertEqual(1);
      expect(validation.sanitizedCookies.has('SESSDATA')).assertTrue();
      expect(validation.rejectedKeys.length).assertEqual(4);
    });

    it('sanitizeRejectsSetWithoutSessdata', 0, () => {
      const validation = validateAndSanitizeBiliCookies(mapOf([['buvid3', 'x'], ['sid', 'y']]));
      expect(validation.hasLoginCookie).assertFalse();
      expect(validation.isAccepted).assertFalse();
    });

    it('midFromCookiesParsesDedeUserID', 0, () => {
      expect(biliMidFromCookies(mapOf([['DedeUserID', '1234567']]))).assertEqual(1234567);
      expect(biliMidFromCookies(mapOf([['DedeUserID', 'not-a-number']]))).assertEqual(0);
      expect(biliMidFromCookies(new Map<string, string>())).assertEqual(0);
    });

    it('buildCookieHeaderJoinsPairs', 0, () => {
      const header = buildBiliCookieHeader(mapOf([['SESSDATA', 'a'], ['buvid3', 'b']]));
      expect(header).assertEqual('SESSDATA=a; buvid3=b');
    });

    it('cookieKeysForLogMasksValues', 0, () => {
      const keys = biliCookieKeysForLog(mapOf([['SESSDATA', 'secret'], ['buvid3', 'x']]));
      expect(keys.indexOf('secret') < 0).assertTrue();
      expect(keys).assertEqual('SESSDATA,buvid3');
    });

    it('rawCookieTextParserSharedAcrossPlatforms', 0, () => {
      const parsed = parseRawCookieText('SESSDATA=a%2Cb; MUSIC_U=m\ndedi=1');
      expect(parsed.size).assertEqual(3);
      expect(parsed.get('SESSDATA')).assertEqual('a%2Cb');
      // The NetEase module re-exports the same shared implementation.
      const viaReExport = parseViaNeteaseReExport('SESSDATA=a; MUSIC_U=m');
      expect(viaReExport.get('SESSDATA')).assertEqual('a');
    });
  });
}
