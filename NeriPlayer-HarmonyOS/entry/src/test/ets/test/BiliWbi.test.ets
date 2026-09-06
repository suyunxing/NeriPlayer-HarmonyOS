import { describe, it, expect } from '@ohos/hypium';
import {
  md5Hex,
  mixinKeyFrom,
  wbiKeyFromUrl,
  wbiFilterValue,
  buildWbiSignedQuery,
  WBI_MIXIN_INDEX
} from '../../../main/ets/network/BiliWbi';

function mapOf(pairs: string[][]): Map<string, string> {
  const out = new Map<string, string>();
  for (const pair of pairs) {
    out.set(pair[0], pair[1]);
  }
  return out;
}

/**
 * Fixtures:
 * - The official bilibili-API-collect wbi.md example keys and signature
 *   (img 7cd084941338484aae1ad9425b84077c / sub 4932caff0ff746eab6f01bf08b70ac45,
 *   mixin ea1db124af3c7062474693fa704f4ff8, {foo,bar,zab} wts=1702204169 ->
 *   w_rid 8f6f2b5b3d485fe1886cec6a0be8c5d4).
 * - Cross-checked values produced by an independent Python implementation
 *   over the same keys (search/playurl parameter shapes, wts=1702204800).
 */
const OFFICIAL_MIXIN_KEY = 'ea1db124af3c7062474693fa704f4ff8';

export default function biliWbiTest(): void {
  describe('BiliWbi', () => {
    it('md5MatchesRfc1321Vectors', 0, () => {
      expect(md5Hex('')).assertEqual('d41d8cd98f00b204e9800998ecf8427e');
      expect(md5Hex('abc')).assertEqual('900150983cd24fb0d6963f7d28e17f72');
      expect(md5Hex('The quick brown fox jumps over the lazy dog'))
        .assertEqual('9e107d9d372bb6826bd81d3542a419d6');
      // Multi-block input (96 bytes) crossing the 64-byte boundary.
      expect(md5Hex('bar=514&foo=114&wts=1702204169&zab=1919810' + OFFICIAL_MIXIN_KEY))
        .assertEqual('8f6f2b5b3d485fe1886cec6a0be8c5d4');
    });

    it('mixinIndexTableHas64Entries', 0, () => {
      expect(WBI_MIXIN_INDEX.length).assertEqual(64);
      expect(WBI_MIXIN_INDEX[0]).assertEqual(46);
      expect(WBI_MIXIN_INDEX[63]).assertEqual(44);
    });

    it('keyFromUrlStripsDirectoryAndExtension', 0, () => {
      expect(wbiKeyFromUrl('https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png'))
        .assertEqual('7cd084941338484aae1ad9425b84077c');
      expect(wbiKeyFromUrl('4932caff0ff746eab6f01bf08b70ac45.png'))
        .assertEqual('4932caff0ff746eab6f01bf08b70ac45');
    });

    it('mixinKeyMatchesOfficialExample', 0, () => {
      const mixin = mixinKeyFrom('7cd084941338484aae1ad9425b84077c', '4932caff0ff746eab6f01bf08b70ac45');
      expect(mixin).assertEqual(OFFICIAL_MIXIN_KEY);
    });

    it('filterValueStripsSpecials', 0, () => {
      expect(wbiFilterValue("a!(b)*c'd")).assertEqual('abcd');
      expect(wbiFilterValue('plain-1_2.3~4')).assertEqual('plain-1_2.3~4');
    });

    it('signedQueryMatchesOfficialExample', 0, () => {
      const query = buildWbiSignedQuery(
        mapOf([['foo', '114'], ['bar', '514'], ['zab', '1919810']]),
        OFFICIAL_MIXIN_KEY,
        1702204169
      );
      expect(query).assertEqual('bar=514&foo=114&wts=1702204169&zab=1919810&w_rid=8f6f2b5b3d485fe1886cec6a0be8c5d4');
    });

    it('signedQueryMatchesCrossCheckedSearchShape', 0, () => {
      const query = buildWbiSignedQuery(
        mapOf([['search_type', 'video'], ['keyword', '晴天']]),
        OFFICIAL_MIXIN_KEY,
        1702204800
      );
      // CJK keyword is UTF-8 percent-encoded, keys sorted, w_rid appended.
      expect(query)
        .assertEqual('keyword=%E6%99%B4%E5%A4%A9&search_type=video&wts=1702204800&w_rid=9032bc7f43581e905efe5bf0de05d32f');
    });

    it('signedQueryMatchesCrossCheckedPlayurlShape', 0, () => {
      const query = buildWbiSignedQuery(
        mapOf([
          ['bvid', 'BV1wrba6iE56'],
          ['fnval', '272'],
          ['fnver', '0'],
          ['fourk', '0'],
          ['otype', 'json'],
          ['platform', 'pc']
        ]),
        OFFICIAL_MIXIN_KEY,
        1702204800
      );
      expect(query)
        .assertEqual('bvid=BV1wrba6iE56&fnval=272&fnver=0&fourk=0&otype=json&platform=pc&wts=1702204800&w_rid=f377b04404cc128b8880a4501e1836a1');
    });
  });
}
