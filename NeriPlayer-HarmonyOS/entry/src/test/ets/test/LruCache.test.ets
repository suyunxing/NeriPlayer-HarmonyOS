import { describe, it, expect } from '@ohos/hypium';
import { LruCache } from '../../../main/ets/util/LruCache';

/**
 * 封面缓存（data/CoverCache）的淘汰底座。封面缓存本身依赖 ImageKit/NetworkKit
 * 只能真机覆盖；这里验证 LRU 的纯逻辑语义：命中提升、超容淘汰最久未用、
 * 覆写不产生重复键。
 */
export default function lruCacheTest(): void {
  describe('LruCache', (): void => {
    it('evicts the least recently used entry beyond capacity', 0, (): void => {
      const cache = new LruCache<string, number>(2);
      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('c', 3);
      expect(cache.size()).assertEqual(2);
      expect(cache.peek('a')).assertUndefined();
      expect(cache.peek('b')).assertEqual(2);
      expect(cache.peek('c')).assertEqual(3);
    });

    it('a hit refreshes recency and protects the entry from eviction', 0, (): void => {
      const cache = new LruCache<string, number>(2);
      cache.put('a', 1);
      cache.put('b', 2);
      // 访问 a 后，最久未用变成 b，再放 c 应淘汰 b 而不是 a。
      expect(cache.get('a')).assertEqual(1);
      cache.put('c', 3);
      expect(cache.peek('a')).assertEqual(1);
      expect(cache.peek('b')).assertUndefined();
      expect(cache.peek('c')).assertEqual(3);
    });

    it('overwriting an existing key updates in place without growing', 0, (): void => {
      const cache = new LruCache<string, number>(2);
      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('a', 10);
      expect(cache.size()).assertEqual(2);
      expect(cache.get('a')).assertEqual(10);
    });

    it('clear drops everything', 0, (): void => {
      const cache = new LruCache<string, number>(4);
      cache.put('a', 1);
      cache.put('b', 2);
      cache.clear();
      expect(cache.size()).assertEqual(0);
      expect(cache.peek('a')).assertUndefined();
    });
  });
}
