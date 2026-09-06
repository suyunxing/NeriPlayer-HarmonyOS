import { describe, it, expect } from '@ohos/hypium';
import {
  YTM_URL_CACHE_MAX_SIZE,
  YTM_URL_CACHE_TTL_MS,
  YtmUrlCache,
  computeYtmUrlExpiresAtMs,
  ytmUrlExpireSeconds
} from '../../../main/ets/network/ytm/YtmUrlCache';

function fakeUrl(extraQuery: string = ''): string {
  // Sanitized googlevideo-like shape; only the expire parameter matters.
  return `https://rr1---sn-example.googlevideo.com/videoplayback?itag=251${extraQuery}`;
}

const T0 = 1_800_000_000_000;

export default function ytmUrlCacheTest(): void {
  describe('YtmUrlCache', () => {
    it('expireParserReadsQueryAndRejectsSuffixKeys', 0, () => {
      expect(ytmUrlExpireSeconds(fakeUrl('&expire=21540'))).assertEqual(21540);
      expect(ytmUrlExpireSeconds(fakeUrl())).assertEqual(0);
      expect(ytmUrlExpireSeconds(fakeUrl('&xexpire=999'))).assertEqual(0);
      expect(ytmUrlExpireSeconds(fakeUrl('&expire=abc'))).assertEqual(0);
    });

    it('distantExpireFallsBackToDefaultTtl', 0, () => {
      // expire 6h out (the spike-observed URL lifetime) is capped at 8min.
      const url = fakeUrl(`&expire=${Math.floor(T0 / 1000) + 21540}`);
      const expires = computeYtmUrlExpiresAtMs(url, T0);
      expect(expires).assertEqual(T0 + YTM_URL_CACHE_TTL_MS);
      const cache = new YtmUrlCache();
      cache.put('v1', 'exhigh', url, T0);
      expect(cache.get('v1', 'exhigh', T0 + YTM_URL_CACHE_TTL_MS - 1)).assertEqual(url);
      expect(cache.get('v1', 'exhigh', T0 + YTM_URL_CACHE_TTL_MS + 1)).assertNull();
    });

    it('nearExpireShortensTtlWithSafetyMargin', 0, () => {
      // expire = T0 + 120s -> TTL = 120s - 90s margin = 30s.
      const url = fakeUrl(`&expire=${Math.floor(T0 / 1000) + 120}`);
      expect(computeYtmUrlExpiresAtMs(url, T0)).assertEqual(T0 + 30_000);
      const cache = new YtmUrlCache();
      cache.put('v1', 'high', url, T0);
      expect(cache.get('v1', 'high', T0 + 29_000)).assertEqual(url);
      expect(cache.get('v1', 'high', T0 + 31_000)).assertNull();
    });

    it('alreadyExpiredUrlIsClampedToCachedAt', 0, () => {
      // expire seconds already in the past: clamp to cachedAt -> immediate miss.
      const url = fakeUrl(`&expire=${Math.floor(T0 / 1000) - 10}`);
      expect(computeYtmUrlExpiresAtMs(url, T0)).assertEqual(T0);
      const cache = new YtmUrlCache();
      cache.put('v1', 'standard', url, T0);
      expect(cache.get('v1', 'standard', T0)).assertNull();
    });

    it('keysAreScopedByVideoIdAndQuality', 0, () => {
      const cache = new YtmUrlCache();
      const urlA = fakeUrl('&expire=99999999999');
      const urlB = fakeUrl('&x=1');
      cache.put('v1', 'standard', urlA, T0);
      cache.put('v1', 'exhigh', urlB, T0);
      cache.put('v2', 'standard', urlA, T0);
      expect(cache.size()).assertEqual(3);
      expect(cache.get('v1', 'standard', T0 + 1000)).assertEqual(urlA);
      expect(cache.get('v1', 'exhigh', T0 + 1000)).assertEqual(urlB);
      expect(cache.get('v2', 'standard', T0 + 1000)).assertEqual(urlA);
    });

    it('evictsOldestBeyond64AndHitRefreshesOrder', 0, () => {
      const cache = new YtmUrlCache();
      for (let i = 0; i < YTM_URL_CACHE_MAX_SIZE; i++) {
        cache.put(`v${i}`, 'standard', fakeUrl(`&i=${i}`), T0);
      }
      expect(cache.size()).assertEqual(YTM_URL_CACHE_MAX_SIZE);
      // Touch the oldest entry, then push one more: v1 becomes the victim.
      expect(cache.get('v0', 'standard', T0 + 1000) !== null).assertTrue();
      cache.put('v-new', 'standard', fakeUrl('&new=1'), T0);
      expect(cache.size()).assertEqual(YTM_URL_CACHE_MAX_SIZE);
      expect(cache.get('v0', 'standard', T0 + 1000) !== null).assertTrue();
      expect(cache.get('v1', 'standard', T0 + 1000)).assertNull();
      expect(cache.get('v-new', 'standard', T0 + 1000) !== null).assertTrue();
    });
  });
}
