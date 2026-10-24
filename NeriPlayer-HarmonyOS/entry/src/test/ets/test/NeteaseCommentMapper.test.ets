// SPDX-License-Identifier: GPL-3.0

import { describe, it, expect } from '@ohos/hypium';
import { parseNeteaseCommentPage, parseNeteaseReplyPage, neteaseCommentError } from '../../../main/ets/network/comments/NeteaseCommentMapper';
import { CommentApiException } from '../../../main/ets/network/comments/CommentRepositoryCore';
import { neteaseEmoteUrl, neteaseEmoteUrlMap } from '../../../main/ets/network/comments/NeteaseEmoteCatalog';
import { CommentPlatform, CommentError } from '../../../main/ets/model/CommentModels';

function neteaseUser(id: number, name: string): Record<string, Object> {
  const user: Record<string, Object> = {};
  user['userId'] = id;
  user['nickname'] = name;
  user['avatarUrl'] = 'http://p3.music.126.net/a.jpg';
  user['level'] = 6;
  return user;
}

function neteaseComment(id: number, name: string, content: string): Record<string, Object> {
  const comment: Record<string, Object> = {};
  comment['commentId'] = id;
  comment['content'] = content;
  comment['time'] = 1700000000000;
  comment['likedCount'] = 12;
  comment['liked'] = false;
  comment['user'] = neteaseUser(id + 1, name);
  return comment;
}

function wrapNeteasePage(comments: Object[], extra: Record<string, Object>): string {
  const data: Record<string, Object> = {};
  data['comments'] = comments;
  for (const key of Object.keys(extra)) {
    data[key] = extra[key];
  }
  const root: Record<string, Object> = {};
  root['code'] = 200;
  root['data'] = data;
  return JSON.stringify(root);
}

export default function neteaseCommentMapperTest(): void {
  describe('NeteaseCommentMapperTest', () => {
    it('parsesCommentsFromDataWrapper', 0, () => {
      const text = wrapNeteasePage([neteaseComment(11, '小明', '好听得哭了'), neteaseComment(12, '小红', '[大笑]经典')], {});
      const page = parseNeteaseCommentPage(text, 1, 20);
      expect(page.comments.length).assertEqual(2);
      expect(page.comments[0].id).assertEqual('11');
      expect(page.comments[0].username).assertEqual('小明');
      expect(page.comments[0].userId).assertEqual('12');
      expect(page.comments[0].avatarUrl !== null).assertTrue();
      expect(page.comments[0].likeCount).assertEqual(12);
      expect(page.comments[0].createTime).assertEqual(1700000000000);
      expect(page.comments[0].platform).assertEqual(CommentPlatform.NETEASE);
      expect(page.comments[0].userLevel).assertEqual(6);
      // 未命中表情表的正文不产生 emote，命中 [大笑] 产生一条。
      expect(page.comments[0].emotes.length).assertEqual(0);
      expect(page.comments[1].emotes.length).assertEqual(1);
      expect(page.comments[1].emotes[0].placeholder).assertEqual('[大笑]');
      expect(page.comments[1].emotes[0].url.startsWith('https://s1.music.126.net/')).assertTrue();
    });

    it('parsesCommentsFromRootObject', 0, () => {
      const root: Record<string, Object> = {};
      root['code'] = 200;
      root['comments'] = [neteaseComment(21, '老形状', 'x')];
      root['total'] = 1;
      const page = parseNeteaseCommentPage(JSON.stringify(root), 1, 20);
      expect(page.comments.length).assertEqual(1);
      expect(page.total).assertEqual(1);
      expect(page.hasMore).assertFalse();
    });

    it('fallsBackHasMoreAndCursor', 0, () => {
      // hasMore 字段缺失时按 total 推算：1*20 < 45。
      const page = parseNeteaseCommentPage(wrapNeteasePage([neteaseComment(1, 'a', 'x')], { 'totalCount': 45 }), 1, 20);
      expect(page.hasMore).assertTrue();
      expect(page.total).assertEqual(45);
      expect(page.nextCursor).assertNull();
      // total 也没有时按本页条数推算。
      const fallback = parseNeteaseCommentPage(wrapNeteasePage(
        new Array<Object>(20).fill(neteaseComment(2, 'b', 'y')), {}), 1, 20);
      expect(fallback.hasMore).assertTrue();
      // cursor "null" 字符串视为缺失。
      const cursorNull = parseNeteaseCommentPage(wrapNeteasePage([], { 'cursor': 'null' }), 1, 20);
      expect(cursorNull.nextCursor).assertNull();
    });

    it('parsesReplyCountAndPreviewAndQuotes', 0, () => {
      const preview: Record<string, Object> = neteaseComment(31, '楼中楼', '回复内容');
      const floor: Record<string, Object> = {};
      floor['replyCount'] = 7;
      floor['comments'] = [preview];
      const deletedQuote: Record<string, Object> = {};
      deletedQuote['user'] = neteaseUser(99, '被删用户');
      deletedQuote['status'] = -5;
      const normalQuote: Record<string, Object> = {};
      normalQuote['user'] = neteaseUser(98, '引用用户');
      normalQuote['content'] = '引用的原文';
      const comment: Record<string, Object> = neteaseComment(30, '楼主', '主楼');
      comment['showFloorComment'] = floor;
      comment['beReplied'] = [deletedQuote, normalQuote];
      comment['parentCommentId'] = 5;
      const page = parseNeteaseCommentPage(wrapNeteasePage([comment], {}), 1, 20);
      const parsed = page.comments[0];
      // 顶层无 replyCount 时回退 showFloorComment.replyCount。
      expect(parsed.replyCount).assertEqual(7);
      expect(parsed.previewReplies.length).assertEqual(1);
      expect(parsed.previewReplies[0].previewReplies.length).assertEqual(0);
      expect(parsed.rootId).assertEqual('5');
      expect(parsed.quotedComments.length).assertEqual(2);
      expect(parsed.quotedComments[0].content).assertNull();
      expect(parsed.quotedComments[1].content).assertEqual('引用的原文');
    });

    it('throwsForBusinessErrorAndInvalidData', 0, () => {
      const err: Record<string, Object> = {};
      err['code'] = 301;
      try {
        parseNeteaseCommentPage(JSON.stringify(err), 1, 20);
        expect().assertFail();
      } catch (error) {
        const api = error as CommentApiException;
        expect(api.code).assertEqual(301);
        expect(api.reason).assertEqual(CommentError.PERMISSION);
      }
      const invalid: Record<string, Object> = {};
      invalid['code'] = 200;
      const emptyData: Record<string, Object> = {};
      invalid['data'] = emptyData;
      try {
        parseNeteaseCommentPage(JSON.stringify(invalid), 1, 20);
        expect().assertFail();
      } catch (error) {
        expect((error as CommentApiException).reason).assertEqual(CommentError.API);
      }
    });

    it('replyPageCursorFromDataTimeWithFallback', 0, () => {
      const withTime = wrapNeteasePage([neteaseComment(41, 'a', 'x')], { 'time': 1700000009999 });
      const page = parseNeteaseReplyPage(withTime, 2, 20);
      expect(page.nextCursor).assertEqual('1700000009999');
      // data.time 缺失时回退最后一条回复的 createTime。
      const noTime = wrapNeteasePage([neteaseComment(42, 'b', 'y')], {});
      const fallback = parseNeteaseReplyPage(noTime, 1, 20);
      expect(fallback.nextCursor).assertEqual('1700000000000');
    });

    it('classifiesBusinessCodes', 0, () => {
      expect(neteaseCommentError(301)).assertEqual(CommentError.PERMISSION);
      expect(neteaseCommentError(315)).assertEqual(CommentError.PERMISSION);
      expect(neteaseCommentError(-460)).assertEqual(CommentError.PERMISSION);
      expect(neteaseCommentError(404)).assertEqual(CommentError.NOT_FOUND);
      expect(neteaseCommentError(503)).assertEqual(CommentError.SERVER);
      expect(neteaseCommentError(400)).assertEqual(CommentError.API);
    });

    it('emoteCatalogMatchesUpstreamShape', 0, () => {
      expect(neteaseEmoteUrlMap().size).assertEqual(59);
      expect(neteaseEmoteUrl('大笑')).assertEqual('https://s1.music.126.net/style/web2/emt/emoji_86.png');
      expect(neteaseEmoteUrl('不存在')).assertNull();
    });

    it('emoteScanSkipsUnknownNestedAndDuplicates', 0, () => {
      const content = '[未知标记] 前缀 [大笑] 中间 [大笑] [含[嵌套]] 尾巴 [强';
      const comment: Record<string, Object> = neteaseComment(1, 'a', content);
      const page = parseNeteaseCommentPage(wrapNeteasePage([comment], {}), 1, 20);
      const emotes = page.comments[0].emotes;
      // 只产出命中的 [大笑] 一条；未知、嵌套、未闭合都不产出。
      expect(emotes.length).assertEqual(1);
      expect(emotes[0].placeholder).assertEqual('[大笑]');
      // 正文原样保留，切段交给 UI。
      expect(page.comments[0].content).assertEqual(content);
    });
  });

}
