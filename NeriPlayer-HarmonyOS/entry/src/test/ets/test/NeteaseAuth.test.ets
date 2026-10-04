import { describe, it, expect } from '@ohos/hypium';
import {
  NeteaseAuthBundle,
  NeteaseAuthHealthState,
  validateAndSanitizeNeteaseCookies,
  evaluateNeteaseAuthHealth,
  parseRawCookieText,
  buildNeteaseCookieHeader,
  cookieKeysForLog
} from '../../../main/ets/data/auth/NeteaseAuth';
import {
  AssetErrorKind,
  classifyAssetError,
  ASSET_ERR_NOT_FOUND,
  ASSET_ERR_SERVICE_UNAVAILABLE,
  ASSET_ERR_DUPLICATED,
  ASSET_ERR_DATABASE_ERROR,
  ASSET_ERR_ACCESS_DENIED
} from '../../../main/ets/data/auth/AssetErrors';

function mapOf(pairs: string[][]): Map<string, string> {
  const out = new Map<string, string>();
  for (const pair of pairs) {
    out.set(pair[0], pair[1]);
  }
  return out;
}

export default function neteaseAuthTest(): void {
  describe('NeteaseAuth', () => {
    it('sanitizeAddsFallbackCookiesAndKeepsValid', 0, () => {
      const result = validateAndSanitizeNeteaseCookies(mapOf([['MUSIC_U', 'token-value'], ['__csrf', 'abc']]));
      expect(result.isAccepted).assertTrue();
      expect(result.sanitizedCookies.size).assertEqual(4);
      expect(result.sanitizedCookies.get('os')).assertEqual('pc');
      expect(result.sanitizedCookies.get('appver')).assertEqual('3.1.17.204416');
      expect(result.hasLoginCookie).assertTrue();
      expect(result.rejectedKeys.length).assertEqual(0);
    });

    it('sanitizeRejectsInvalidNamesValuesAndSemicolons', 0, () => {
      const result = validateAndSanitizeNeteaseCookies(mapOf([
        ['bad name', 'v'],
        ['MUSIC_U', 'a;b'],
        ['empty', ''],
        ['ctrl\u0001', 'v'],
        ['__csrf', 'ok']
      ]));
      expect(result.rejectedKeys.length).assertEqual(4);
      expect(result.rejectedKeys[0]).assertEqual('bad name');
      // __csrf plus the os/appver fallback cookies.
      expect(result.sanitizedCookies.size).assertEqual(3);
      // No MUSIC_U survived: not accepted even though something is left.
      expect(result.isAccepted).assertFalse();
      expect(result.hasLoginCookie).assertFalse();
    });

    it('bundleJsonRoundTripsPreservingOrder', 0, () => {
      const bundle = new NeteaseAuthBundle();
      bundle.cookies = mapOf([['MUSIC_U', 'm1'], ['__csrf', 'c1'], ['os', 'pc']]);
      bundle.savedAt = 1755300000000;
      const json = bundle.toJson();
      const restored = NeteaseAuthBundle.fromJson(json);
      expect(restored.savedAt).assertEqual(1755300000000);
      expect(restored.cookies.size).assertEqual(3);
      expect(restored.cookies.get('MUSIC_U')).assertEqual('m1');
      expect(restored.hasLoginCookies()).assertTrue();
      // Insertion order preserved (MUSIC_U first).
      const keys: string[] = [];
      restored.cookies.forEach((_v: string, k: string) => keys.push(k));
      expect(keys[0]).assertEqual('MUSIC_U');
    });

    it('bundleFromCorruptJsonReturnsEmpty', 0, () => {
      const restored = NeteaseAuthBundle.fromJson('{"cookies": [broken');
      expect(restored.cookies.size).assertEqual(0);
      expect(restored.hasLoginCookies()).assertFalse();
      const missing = NeteaseAuthBundle.fromJson('{}');
      expect(missing.cookies.size).assertEqual(0);
    });

    it('healthMissingWithoutMusicUAndValidWithAge', 0, () => {
      const now = 1755300100000;
      const empty = evaluateNeteaseAuthHealth(new NeteaseAuthBundle(), now);
      expect(empty.state).assertEqual(NeteaseAuthHealthState.MISSING);

      const bundle = new NeteaseAuthBundle();
      bundle.cookies = mapOf([['MUSIC_U', 'm1']]);
      bundle.savedAt = now - 5000;
      const health = evaluateNeteaseAuthHealth(bundle, now);
      expect(health.state).assertEqual(NeteaseAuthHealthState.VALID);
      expect(health.ageMs).assertEqual(5000);
      expect(health.loginCookieKeys.length).assertEqual(1);
      expect(health.loginCookieKeys[0]).assertEqual('MUSIC_U');
    });

    it('parseRawCookieTextSplitsAndDeduplicates', 0, () => {
      const parsed = parseRawCookieText('MUSIC_U=abc; __csrf=def\r\nos=pc;\n;broken\nMUSIC_U=abc2');
      expect(parsed.size).assertEqual(3);
      expect(parsed.get('MUSIC_U')).assertEqual('abc2'); // later occurrence overrides
      expect(parsed.get('__csrf')).assertEqual('def');
      expect(parsed.get('os')).assertEqual('pc');
    });

    it('cookieHeaderBuildsWithFallbacks', 0, () => {
      const header = buildNeteaseCookieHeader(mapOf([['MUSIC_U', 'm1']]));
      expect(header).assertEqual('MUSIC_U=m1; os=pc; appver=3.1.17.204416');
      expect(buildNeteaseCookieHeader(new Map())).assertEqual('');
      expect(cookieKeysForLog(mapOf([['MUSIC_U', 'm1'], ['__csrf', 'c']]))).assertEqual('MUSIC_U,__csrf');
    });

    it('assetErrorClassification', 0, () => {
      expect(classifyAssetError(ASSET_ERR_NOT_FOUND)).assertEqual(AssetErrorKind.NOT_FOUND);
      expect(classifyAssetError(ASSET_ERR_DUPLICATED)).assertEqual(AssetErrorKind.DUPLICATED);
      expect(classifyAssetError(ASSET_ERR_SERVICE_UNAVAILABLE)).assertEqual(AssetErrorKind.FALLBACK);
      expect(classifyAssetError(ASSET_ERR_DATABASE_ERROR)).assertEqual(AssetErrorKind.RETRY);
      expect(classifyAssetError(ASSET_ERR_ACCESS_DENIED)).assertEqual(AssetErrorKind.FATAL);
    });
  });
}
