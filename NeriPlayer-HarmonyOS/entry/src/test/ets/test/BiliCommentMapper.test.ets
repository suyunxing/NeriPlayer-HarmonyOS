// SPDX-License-Identifier: GPL-3.0

import { describe, it, expect } from '@ohos/hypium';
import { parseBiliCommentPage, biliCommentError } from '../../../main/ets/network/comments/BiliCommentMapper';
import { CommentApiException } from '../../../main/ets/network/comments/CommentRepositoryCore';
import { CommentPlatform, CommentError } from '../../../main/ets/model/CommentModels';

function biliMember(mid: string, name: string): Record<string, Object> {
  const levelInfo: Record<string, Object> = {};
  levelInfo['current_level'] = 5;
  const member: Record<string, Object> = {};
  member['mid'] = mid;
  member['uname'] = name;
  member['avatar'] = '//i0.hdslb.com/bfs/face/xxx.jpg';
  member['level_info'] = levelInfo;
  return member;
}

function biliContent(message: string): Record<string, Object> {
  const emoteEntry: Record<string, Object> = {};
  emoteEntry['id'] = 26;
  emoteEntry['url'] = '//i0.hdslb.com/bfs/emote/doge.png';
  const emote: Record<string, Object> = {};
  emote['[doge]'] = emoteEntry;
  const picture: Record<string, Object> = {};
  picture['img_src'] = '//i0.hdslb.com/bfs/activity/2022/xxx.jpg';
  picture['img_width'] = 2400;
  picture['img_height'] = 1080;
  const content: Record<string, Object> = {};
  content['message'] = message;
  content['emote'] = emote;
  content['pictures'] = [picture];
  return content;
}

function biliReply(rpid: number, name: string, message: string): Record<string, Object> {
  const reply: Record<string, Object> = {};
  reply['rpid'] = rpid;
  reply['ctime'] = 1700000000;
  reply['like'] = 88;
  reply['action'] = 0;
  reply['rcount'] = 3;
  reply['root'] = 0;
  reply['member'] = biliMember(`${rpid}`, name);
  reply['content'] = biliContent(message);
  return reply;
}

function wrapBiliPage(replies: Object[], num: number, size: number,
  count: number, acount: number): string {
  const page: Record<string, Object> = {};
  page['num'] = num;
  page['size'] = size;
  page['count'] = count;
  page['acount'] = acount;
  const data: Record<string, Object> = {};
  data['page'] = page;
  data['replies'] = replies;
  const root: Record<string, Object> = {};
  root['code'] = 0;
  root['data'] = data;
  return JSON.stringify(root);
}

export default function biliCommentMapperTest(): void {
  describe('BiliCommentMapperTest', () => {
    it('parsesCommentsWithEmotesImagesAndPreview', 0, () => {
      const child: Record<string, Object> = biliReply(2, '楼中楼', '子回复');
      child['root'] = 1;
      const parent: Record<string, Object> = biliReply(1, '老王', '好活 [doge]');
      parent['replies'] = [child];
      const page = parseBiliCommentPage(wrapBiliPage([parent], 1, 20, 60, 90), 1, 20, true);
      expect(page.comments.length).assertEqual(1);
      const comment = page.comments[0];
      expect(comment.id).assertEqual('1');
      expect(comment.username).assertEqual('老王');
      expect(comment.userId).assertEqual('1');
      expect(comment.platform).assertEqual(CommentPlatform.BILIBILI);
      // ctime 秒 -> 毫秒。
      expect(comment.createTime).assertEqual(1700000000000);
      expect(comment.likeCount).assertEqual(88);
      expect(comment.replyCount).assertEqual(3);
      expect(comment.userLevel).assertEqual(5);
      expect(comment.previewReplies.length).assertEqual(1);
      expect(comment.previewReplies[0].rootId).assertEqual('1');
      expect(comment.previewReplies[0].images.length).assertEqual(0);
      // 表情与配图：协议补 https，宽高入模型。
      expect(comment.emotes.length).assertEqual(1);
      expect(comment.emotes[0].placeholder).assertEqual('[doge]');
      expect(comment.emotes[0].url).assertEqual('https://i0.hdslb.com/bfs/emote/doge.png');
      expect(comment.images.length).assertEqual(1);
      expect(comment.images[0].url).assertEqual('https://i0.hdslb.com/bfs/activity/2022/xxx.jpg');
      expect(comment.images[0].aspectRatio()).assertClose(2400 / 1080, 0.001);
      // hasMore 按实际条数推算（1 条 < 60），totalIncludingReplies 取 acount。
      expect(page.total).assertEqual(60);
      expect(page.hasMore).assertTrue();
      expect(page.totalIncludingReplies).assertEqual(90);
    });

    it('replyCountFallsBackToCount', 0, () => {
      const reply: Record<string, Object> = biliReply(1, 'a', 'x');
      // rcount 缺失语义用 -1 表达（mapper 按 >=0 判存在）。
      reply['rcount'] = -1;
      reply['count'] = 9;
      const page = parseBiliCommentPage(wrapBiliPage([reply], 1, 20, 9, 9), 1, 20);
      expect(page.comments[0].replyCount).assertEqual(9);
    });

    it('rejectsInvalidPagination', 0, () => {
      // 分页对象全零（匿名受限响应）必须按 API 错误抛出，不能当作读完。
      try {
        parseBiliCommentPage(wrapBiliPage([], 0, 0, 0, 0), 1, 20);
        expect().assertFail();
      } catch (error) {
        expect((error as CommentApiException).reason).assertEqual(CommentError.API);
      }
      try {
        parseBiliCommentPage(wrapBiliPage([], 3, 20, 100, 100), 2, 20);
        expect().assertFail();
      } catch (error) {
        expect((error as CommentApiException).reason).assertEqual(CommentError.API);
      }
    });

    it('rejectsIncompleteEmptyPage', 0, () => {
      // #487：空页但按总数还有剩余，是接口截断而不是读完。
      try {
        parseBiliCommentPage(wrapBiliPage([], 2, 20, 45, 45), 2, 20);
        expect().assertFail();
      } catch (error) {
        expect((error as CommentApiException).reason).assertEqual(CommentError.API);
      }
      // 最后一页空且无剩余：正常返回（hasMore=false）。
      const lastEmpty = parseBiliCommentPage(wrapBiliPage([], 2, 20, 20, 20), 2, 20);
      expect(lastEmpty.hasMore).assertFalse();
    });

    it('classifiesBusinessCodes', 0, () => {
      expect(biliCommentError(-101)).assertEqual(CommentError.PERMISSION);
      expect(biliCommentError(-412)).assertEqual(CommentError.PERMISSION);
      expect(biliCommentError(-404)).assertEqual(CommentError.NOT_FOUND);
      expect(biliCommentError(12061)).assertEqual(CommentError.CLOSED);
      expect(biliCommentError(12002)).assertEqual(CommentError.CLOSED);
      expect(biliCommentError(500)).assertEqual(CommentError.SERVER);
      expect(biliCommentError(12009)).assertEqual(CommentError.API);
    });

    it('throwsForBusinessError', 0, () => {
      const err: Record<string, Object> = {};
      err['code'] = 12061;
      try {
        parseBiliCommentPage(JSON.stringify(err), 1, 20);
        expect().assertFail();
      } catch (error) {
        const api = error as CommentApiException;
        expect(api.code).assertEqual(12061);
        expect(api.reason).assertEqual(CommentError.CLOSED);
      }
    });

    it('hasMoreWhenExactlyReadThrough', 0, () => {
      // loadedThrough == total 时结束。
      const replies: Object[] = [biliReply(1, 'a', 'x'), biliReply(2, 'b', 'y')];
      const page = parseBiliCommentPage(wrapBiliPage(replies, 1, 20, 2, 2), 1, 20);
      expect(page.hasMore).assertFalse();
    });
  });

}
