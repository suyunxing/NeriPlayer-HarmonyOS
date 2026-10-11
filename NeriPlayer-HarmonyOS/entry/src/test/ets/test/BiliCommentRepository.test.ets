// SPDX-License-Identifier: GPL-3.0

import { describe, it, expect } from '@ohos/hypium';
import { BiliCommentRepository, BiliCommentClientDeps } from '../../../main/ets/network/comments/BiliCommentRepository';
import { NeteaseCommentRepository, NeteaseCommentClientDeps } from '../../../main/ets/network/comments/NeteaseCommentRepository';
import { CommentMemoryCache, CommentApiException } from '../../../main/ets/network/comments/CommentRepositoryCore';
import { CommentPlatform, CommentSort, CommentError, CommentSource } from '../../../main/ets/model/CommentModels';
import { BiliVideoInfo, BiliVideoPage } from '../../../main/ets/network/BiliApi';

function videoInfo(bvid: string, aid: number, cids: number[]): BiliVideoInfo {
  const info = new BiliVideoInfo();
  info.bvid = bvid;
  info.aid = aid;
  for (const cid of cids) {
    const page = new BiliVideoPage();
    page.cid = cid;
    info.pages.push(page);
  }
  return info;
}

function biliCommentsJson(count: number, total: number, num: number): string {
  const replies: Object[] = [];
  for (let i = 1; i <= count; i++) {
    const member: Record<string, Object> = {};
    member['mid'] = `${i}`;
    member['uname'] = `用户${i}`;
    member['avatar'] = `//i0.hdslb.com/bfs/face/${i}.jpg`;
    const content: Record<string, Object> = {};
    content['message'] = `评论${i}`;
    const reply: Record<string, Object> = {};
    reply['rpid'] = i;
    reply['ctime'] = 1700000000 + i;
    reply['like'] = i;
    reply['rcount'] = 0;
    reply['member'] = member;
    reply['content'] = content;
    replies.push(reply);
  }
  const pageObj: Record<string, Object> = {};
  pageObj['num'] = num;
  pageObj['size'] = 20;
  pageObj['count'] = total;
  pageObj['acount'] = total;
  const data: Record<string, Object> = {};
  data['page'] = pageObj;
  data['replies'] = replies;
  const root: Record<string, Object> = {};
  root['code'] = 0;
  root['data'] = data;
  return JSON.stringify(root);
}

class FakeBiliDeps extends BiliCommentClientDeps {
  info: BiliVideoInfo | null = null;
  commentsText: string | null = null;
  repliesText: string | null = null;
  likeResult: string = '{"code":0}';
  sendResult: string = '{"code":0}';
  sessionKeyValue: string | null = null;
  commentCalls: string[] = [];

  async fetchVideoInfo(bvid: string): Promise<BiliVideoInfo | null> {
    return this.info;
  }

  async fetchCommentsText(aid: number, page: number, pageSize: number, sort: number): Promise<string | null> {
    this.commentCalls.push(`${aid}:${page}:${sort}`);
    return this.commentsText;
  }

  async fetchRepliesText(aid: number, rootId: string, page: number, pageSize: number): Promise<string | null> {
    return this.repliesText;
  }

  async likeText(aid: number, commentId: string, liked: boolean): Promise<string | null> {
    return this.likeResult;
  }

  async sendText(aid: number, content: string, rootId: string | null, parentId: string | null): Promise<string | null> {
    return this.sendResult;
  }

  sessionKey(): string | null {
    return this.sessionKeyValue;
  }
}

function biliSource(bvid: string, cid: number | null): CommentSource {
  return new CommentSource(CommentPlatform.BILIBILI, 0, bvid, cid);
}

export default function biliCommentRepositoryTest(): void {
  describe('BiliCommentRepositoryTest', () => {

    it('resolvesAvidAndCachesAcrossCalls', 0, async () => {
      const deps = new FakeBiliDeps();
      deps.info = videoInfo('BV1x', 170001, [11]);
      deps.commentsText = biliCommentsJson(2, 2, 1);
      const repo = new BiliCommentRepository(new CommentMemoryCache(), deps);
      const first = await repo.loadComments(biliSource('BV1x', 11), 1, 20, false, CommentSort.HOT, null);
      expect(first.comments.length).assertEqual(2);
      expect(deps.commentCalls.length).assertEqual(1);
      // 同源第二次走缓存（avid 解析与分页缓存都复用）。
      await repo.loadComments(biliSource('BV1x', 11), 1, 20, false, CommentSort.HOT, null);
      expect(deps.commentCalls.length).assertEqual(1);
    });

    it('rejectsWhenCidNotInVideoPages', 0, async () => {
      const deps = new FakeBiliDeps();
      deps.info = videoInfo('BV1x', 170001, [11]);
      const repo = new BiliCommentRepository(new CommentMemoryCache(), deps);
      try {
        await repo.loadComments(biliSource('BV1x', 999), 1, 20, false, CommentSort.HOT, null);
        expect().assertFail();
      } catch (error) {
        expect((error as CommentApiException).reason).assertEqual(CommentError.API);
      }
    });

    it('rejectsWhenVideoUnresolvable', 0, async () => {
      const deps = new FakeBiliDeps();
      deps.info = null;
      const repo = new BiliCommentRepository(new CommentMemoryCache(), deps);
      try {
        await repo.loadComments(biliSource('BV1missing', null), 1, 20, false, CommentSort.HOT, null);
        expect().assertFail();
      } catch (error) {
        expect((error as CommentApiException).reason).assertEqual(CommentError.API);
      }
    });

    it('rejectsUnsupportedSort', 0, async () => {
      const deps = new FakeBiliDeps();
      deps.info = videoInfo('BV1x', 1, [11]);
      const repo = new BiliCommentRepository(new CommentMemoryCache(), deps);
      try {
        await repo.loadComments(biliSource('BV1x', 11), 1, 20, false, CommentSort.RECOMMENDED, null);
        expect().assertFail();
      } catch (error) {
        expect((error as CommentApiException).reason).assertEqual(CommentError.API);
      }
    });

    it('likeFailureSurfacesBusinessCodeAndInvalidatesCache', 0, async () => {
      const deps = new FakeBiliDeps();
      deps.info = videoInfo('BV1x', 170001, [11]);
      deps.commentsText = biliCommentsJson(2, 2, 1);
      deps.likeResult = '{"code":-101}';
      const cache = new CommentMemoryCache();
      const repo = new BiliCommentRepository(cache, deps);
      await repo.loadComments(biliSource('BV1x', 11), 1, 20, false, CommentSort.HOT, null);
      try {
        await repo.setLiked(biliSource('BV1x', 11), '1', true);
        expect().assertFail();
      } catch (error) {
        const api = error as CommentApiException;
        expect(api.code).assertEqual(-101);
        expect(api.reason).assertEqual(CommentError.PERMISSION);
      }
      // 点赞后缓存被失效：下次重新拉取。
      await repo.loadComments(biliSource('BV1x', 11), 1, 20, false, CommentSort.HOT, null);
      expect(deps.commentCalls.length).assertEqual(2);
    });

    it('sendCommentValidatesContentAndUsesAvid', 0, async () => {
      const deps = new FakeBiliDeps();
      deps.info = videoInfo('BV1x', 170001, [11]);
      deps.commentsText = biliCommentsJson(1, 1, 1);
      const repo = new BiliCommentRepository(new CommentMemoryCache(), deps);
      // 空白内容在本地拦下。
      try {
        await repo.sendComment(biliSource('BV1x', 11), '   ', null);
        expect().assertFail();
      } catch (error) {
        expect((error as CommentApiException).reason).assertEqual(CommentError.API);
      }
      await repo.sendComment(biliSource('BV1x', 11), '好听', null);
      expect(deps.commentCalls.length).assertEqual(0);
    });

    it('neteaseWriteOperationsRejectedWithPermission', 0, async () => {
      const repo = new NeteaseCommentRepository(new CommentMemoryCache(), new NeteaseCommentClientDeps());
      const source = new CommentSource(CommentPlatform.NETEASE, 123);
      try {
        await repo.setLiked(source, '1', true);
        expect().assertFail();
      } catch (error) {
        expect((error as CommentApiException).reason).assertEqual(CommentError.PERMISSION);
      }
      try {
        await repo.sendComment(source, 'hi', null);
        expect().assertFail();
      } catch (error) {
        expect((error as CommentApiException).reason).assertEqual(CommentError.PERMISSION);
      }
    });
  });

}
