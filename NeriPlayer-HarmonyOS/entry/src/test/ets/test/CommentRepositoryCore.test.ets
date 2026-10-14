// SPDX-License-Identifier: GPL-3.0

import { describe, it, expect } from '@ohos/hypium';
import { CommentMemoryCache, requireNeteaseCommentProgress, CommentApiException } from '../../../main/ets/network/comments/CommentRepositoryCore';
import { CommentSort, CommentError, CommentPage, SongComment, CommentPlatform } from '../../../main/ets/model/CommentModels';

function pageOf(comments: SongComment[], page: number, hasMore: boolean, cursor: string | null): CommentPage {
  return new CommentPage(comments, page, 20, 100, hasMore, cursor);
}

function fakeComment(id: string): SongComment {
  return new SongComment(id, `user${id}`, `content${id}`, CommentPlatform.NETEASE);
}

export default function commentRepositoryCoreTest(): void {
  describe('CommentRepositoryCoreTest', () => {
    it('isolatesCacheByKeyDimensions', 0, () => {
      let now = 1000;
      const cache = new CommentMemoryCache((): number => now);
      const p = pageOf([fakeComment('1')], 1, true, 'c1');
      cache.put('NETEASE', 5, 1, p);
      cache.put('NETEASE', 5, 1, p, CommentSort.NEWEST);
      cache.put('NETEASE', 5, 1, p, CommentSort.HOT, 20, null, 'session-a');
      cache.put('BILIBILI', 5, 1, p);
      cache.put('NETEASE', 5, 2, pageOf([], 2, false, null));

      expect(cache.get('NETEASE', 5, 1) !== null).assertTrue();
      expect(cache.get('NETEASE', 5, 1, CommentSort.NEWEST) !== null).assertTrue();
      expect(cache.get('NETEASE', 5, 1, CommentSort.HOT, 20, null, 'session-a') !== null).assertTrue();
      expect(cache.get('NETEASE', 5, 1, CommentSort.HOT, 20, null, 'session-b')).assertNull();
      expect(cache.get('BILIBILI', 5, 1) !== null).assertTrue();
      expect(cache.get('NETEASE', 6, 1)).assertNull();
      expect(cache.get('NETEASE', 5, 2) !== null).assertTrue();
    });

    it('expiresEntriesAfterTtl', 0, () => {
      let now = 1000;
      const cache = new CommentMemoryCache((): number => now);
      cache.put('NETEASE', 7, 1, pageOf([fakeComment('1')], 1, false, null));
      now += 5 * 60 * 1000 - 1;
      expect(cache.get('NETEASE', 7, 1) !== null).assertTrue();
      now += 2;
      expect(cache.get('NETEASE', 7, 1)).assertNull();
      // 过期条目被顺手删除。
      now = 0;
      expect(cache.get('NETEASE', 7, 1)).assertNull();
    });

    it('invalidatesByResourcePrefix', 0, () => {
      const cache = new CommentMemoryCache();
      cache.put('NETEASE', 8, 1, pageOf([], 1, false, null));
      cache.put('NETEASE', 8, 2, pageOf([], 2, false, null), CommentSort.NEWEST);
      cache.put('NETEASE', 9, 1, pageOf([], 1, false, null));
      cache.invalidate('NETEASE', 8);
      expect(cache.get('NETEASE', 8, 1)).assertNull();
      expect(cache.get('NETEASE', 8, 2, CommentSort.NEWEST)).assertNull();
      expect(cache.get('NETEASE', 9, 1) !== null).assertTrue();
    });

    it('evictsLeastRecentlyUsedBeyondLimit', 0, () => {
      const cache = new CommentMemoryCache();
      // 写满 49 条（上限 48）：第 1 条应被淘汰。
      for (let id = 1; id <= 49; id++) {
        cache.put('NETEASE', id, 1, pageOf([], 1, false, null));
      }
      expect(cache.get('NETEASE', 1, 1)).assertNull();
      expect(cache.get('NETEASE', 49, 1) !== null).assertTrue();
      // 访问第 5 条后继续写入：被淘汰的是第 2 条而不是第 5 条。
      expect(cache.get('NETEASE', 5, 1) !== null).assertTrue();
      cache.put('NETEASE', 50, 1, pageOf([], 1, false, null));
      expect(cache.get('NETEASE', 2, 1)).assertNull();
      expect(cache.get('NETEASE', 5, 1) !== null).assertTrue();
    });

    it('requiresNeteaseProgress', 0, () => {
      // hasMore 且空页：停滞。
      try {
        requireNeteaseCommentProgress(pageOf([], 2, true, 'x'), CommentSort.HOT, 'x');
        expect().assertFail();
      } catch (error) {
        expect((error as CommentApiException).reason).assertEqual(CommentError.API);
      }
      // 最新排序游标未前进：停滞。
      try {
        requireNeteaseCommentProgress(pageOf([fakeComment('1')], 2, true, 'same'), CommentSort.NEWEST, 'same');
        expect().assertFail();
      } catch (error) {
        expect((error as CommentApiException).reason).assertEqual(CommentError.API);
      }
      // 正常推进不抛。
      requireNeteaseCommentProgress(pageOf([fakeComment('1')], 2, true, 'next'), CommentSort.NEWEST, 'prev');
      requireNeteaseCommentProgress(pageOf([], 3, false, null), CommentSort.HOT, null);
    });
  });

}
