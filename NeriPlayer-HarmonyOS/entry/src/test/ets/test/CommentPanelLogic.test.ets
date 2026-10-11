// SPDX-License-Identifier: GPL-3.0

import { describe, it, expect } from '@ohos/hypium';
import { mergeComments, distinctComments, hasMoreComments, toCommentError,
  findComment, applyLikeToComments, applyLikeToReplies,
  buildCommentSegments, formatCommentTime } from '../../../main/ets/view/components/comment/CommentPanelLogic';
import { CommentApiException } from '../../../main/ets/network/comments/CommentRepositoryCore';
import { CommentPlatform, CommentError, CommentEmote, SongComment } from '../../../main/ets/model/CommentModels';

function comment(id: string, likeCount: number, liked: boolean): SongComment {
  const c = new SongComment(id, `user${id}`, `content${id}`, CommentPlatform.BILIBILI);
  c.likeCount = likeCount;
  c.isLiked = liked;
  return c;
}

export default function commentPanelLogicTest(): void {
  describe('CommentPanelLogicTest', () => {
    it('mergeCommentsDeduplicatesById', 0, () => {
      const existing = [comment('1', 0, false), comment('2', 0, false)];
      const incoming = [comment('2', 5, true), comment('3', 0, false)];
      const merged = mergeComments(existing, incoming);
      expect(merged.length).assertEqual(3);
      // 保留既有评论：id=2 的旧值不被新页覆盖。
      expect(merged[1].likeCount).assertEqual(0);
      expect(distinctComments([comment('1', 0, false), comment('1', 0, false)]).length).assertEqual(1);
    });

    it('hasMoreCommentsAccountsForReplyTotals', 0, () => {
      const root = comment('1', 0, false);
      root.replyCount = 3;
      // 总数（含楼中楼）4 = 1 一级 + 3 楼中楼：正好读完，无下一页。
      expect(hasMoreComments(true, [root], 4)).assertFalse();
      // 总数 5：还剩 1 条，有下一页。
      expect(hasMoreComments(true, [root], 5)).assertTrue();
      // hasMore=false 或无总数时直接沿用接口状态。
      expect(hasMoreComments(false, [root], null)).assertFalse();
      expect(hasMoreComments(true, [root], null)).assertTrue();
    });

    it('findCommentSearchesThreeLevels', 0, () => {
      const root = comment('r1', 0, false);
      const preview = comment('p1', 0, false);
      root.previewReplies = [preview];
      const threads = new Map<string, SongComment[]>();
      threads.set('r2', [comment('t1', 0, false)]);
      expect(findComment([root], threads, 'r1') !== null).assertTrue();
      expect(findComment([root], threads, 'p1') !== null).assertTrue();
      expect(findComment([root], threads, 't1') !== null).assertTrue();
      expect(findComment([root], threads, 'missing')).assertNull();
    });

    it('applyLikeWritesBackAllPositions', 0, () => {
      const root = comment('r1', 10, false);
      const preview = comment('p1', 4, false);
      root.previewReplies = [preview];
      const updated = applyLikeToComments([root, comment('r2', 0, false)], 'p1', true);
      expect(updated[0].previewReplies[0].isLiked).assertTrue();
      expect(updated[0].previewReplies[0].likeCount).assertEqual(5);
      // 未命中的评论保持原引用值。
      expect(updated[0].isLiked).assertFalse();

      const unliked = applyLikeToReplies([comment('p1', 3, true)], 'p1', false);
      expect(unliked[0].likeCount).assertEqual(2);
      expect(unliked[0].isLiked).assertFalse();
      // 不降到负数。
      const floor = applyLikeToReplies([comment('p1', 0, true)], 'p1', false);
      expect(floor[0].likeCount).assertEqual(0);
    });

    it('toCommentErrorClassifiesApiAndNetwork', 0, () => {
      expect(toCommentError(new CommentApiException(301, CommentError.PERMISSION, 'x'))).assertEqual(CommentError.PERMISSION);
      expect(toCommentError(new Error('network unreachable'))).assertEqual(CommentError.NETWORK);
      expect(toCommentError(new Error('任意其它错误'))).assertEqual(CommentError.UNKNOWN);
    });

    it('buildSegmentsSplitsOnEmotePlaceholders', 0, () => {
      const emotes = [new CommentEmote('[大笑]', 'https://x/86.png'), new CommentEmote('[doge]', 'https://y.png')];
      const segments = buildCommentSegments('前缀[大笑]中间[doge]尾巴', emotes);
      expect(segments.length).assertEqual(5);
      expect(segments[0].text).assertEqual('前缀');
      expect(segments[0].emoteUrl).assertNull();
      expect(segments[1].emoteUrl).assertEqual('https://x/86.png');
      expect(segments[2].text).assertEqual('中间');
      expect(segments[4].text).assertEqual('尾巴');
      // 无表情：单一文本段。
      expect(buildCommentSegments('纯文本', []).length).assertEqual(1);
    });

    it('formatCommentTimeRelativeBuckets', 0, () => {
      const now = 1700000000000;
      expect(formatCommentTime(null, now)).assertEqual('');
      expect(formatCommentTime(now - 30 * 1000, now)).assertEqual('刚刚');
      expect(formatCommentTime(now - 5 * 60 * 1000, now)).assertEqual('5 分钟前');
      expect(formatCommentTime(now - 3 * 60 * 60 * 1000, now)).assertEqual('3 小时前');
      expect(formatCommentTime(now - 2 * 24 * 60 * 60 * 1000, now)).assertEqual('2 天前');
      const old = formatCommentTime(now - 30 * 24 * 60 * 60 * 1000, now);
      expect(old.indexOf('前')).assertEqual(-1);
      expect(old.length >= 10).assertTrue();
    });
  });

}
