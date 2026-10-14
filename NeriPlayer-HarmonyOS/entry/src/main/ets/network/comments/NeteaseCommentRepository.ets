/**
 * 网易云评论仓库（上游 platform/comments/repository/NeteaseCommentRepository.kt
 * 直译，#476）。读路径（列表/楼中楼）完整支持；点赞与发评依赖上游的网页端
 * 易盾设备校验（checkToken），鸿蒙侧无该设施，以 PERMISSION 错误明确拒绝
 * 而不是发出注定失败的请求。
 */
import { CommentPage, CommentPlatform, CommentSort, CommentSource, CommentError, CommentReplyTarget } from '../../model/CommentModels';
import { commentPlatformName } from '../../model/CommentModels';
import { CommentApiException, CommentMemoryCache, CommentRepository, requireNeteaseCommentProgress } from './CommentRepositoryCore';
import { parseNeteaseCommentPage, parseNeteaseReplyPage } from './NeteaseCommentMapper';
import { NeteaseApi } from '../NeteaseApi';

/**
 * 网易云评论 HTTP 依赖基类：生产环境由 LiveNeteaseCommentClientDeps 接
 * NeteaseApi，单元测试用 fake 子类注入固定响应。
 */
export class NeteaseCommentClientDeps {
  async fetchCommentsText(songId: number, page: number, pageSize: number,
    sortType: number, cursor: string | null): Promise<string | null> {
    return null;
  }

  async fetchRepliesText(songId: number, rootId: string, pageSize: number,
    cursor: string | null): Promise<string | null> {
    return null;
  }

  sessionKey(): string | null {
    return null;
  }
}

/** 接 NeteaseApi 的生产依赖。 */
export class LiveNeteaseCommentClientDeps extends NeteaseCommentClientDeps {
  async fetchCommentsText(songId: number, page: number, pageSize: number,
    sortType: number, cursor: string | null): Promise<string | null> {
    return NeteaseApi.getSongComments(songId, page, pageSize, sortType, cursor);
  }

  async fetchRepliesText(songId: number, rootId: string, pageSize: number,
    cursor: string | null): Promise<string | null> {
    return NeteaseApi.getSongCommentReplies(songId, rootId, pageSize, cursor);
  }

  sessionKey(): string | null {
    return NeteaseApi.commentCacheSessionKey();
  }
}

export class NeteaseCommentRepository implements CommentRepository {
  readonly platform: CommentPlatform = CommentPlatform.NETEASE;
  private cache: CommentMemoryCache;
  private deps: NeteaseCommentClientDeps;

  constructor(cache: CommentMemoryCache, deps: NeteaseCommentClientDeps) {
    this.cache = cache;
    this.deps = deps;
  }

  async cachedComments(source: CommentSource, pageSize: number,
    sort: CommentSort): Promise<CommentPage | null> {
    return this.cache.get(commentPlatformName(this.platform), source.resourceId, 1,
      sort, pageSize, null, this.deps.sessionKey());
  }

  async loadComments(source: CommentSource, page: number, pageSize: number,
    forceRefresh: boolean, sort: CommentSort, cursor: string | null): Promise<CommentPage> {
    const resourceId = source.resourceId;
    const sessionKey = this.deps.sessionKey();
    if (!forceRefresh) {
      const cached = this.cache.get(commentPlatformName(this.platform), resourceId,
        page, sort, pageSize, cursor, sessionKey);
      if (cached !== null) {
        return cached;
      }
    }

    const sortType = sort === CommentSort.HOT ? 2 : (sort === CommentSort.NEWEST ? 3 : 99);
    const raw = await this.deps.fetchCommentsText(resourceId, page, pageSize, sortType, cursor);
    if (raw === null) {
      throw new CommentApiException(-1, CommentError.NETWORK, 'NetEase comments unavailable');
    }
    const result = parseNeteaseCommentPage(raw, page, pageSize);
    requireNeteaseCommentProgress(result, sort, cursor);
    if (sessionKey === this.deps.sessionKey()) {
      if (forceRefresh && page === 1) {
        this.cache.invalidate(commentPlatformName(this.platform), resourceId);
      }
      this.cache.put(commentPlatformName(this.platform), resourceId, page, result,
        sort, pageSize, cursor, sessionKey);
    }
    return result;
  }

  async setLiked(source: CommentSource, commentId: string, liked: boolean): Promise<void> {
    throw new CommentApiException(301, CommentError.PERMISSION,
      '网易评论点赞需要网页端设备校验，暂不支持');
  }

  async loadReplies(source: CommentSource, rootId: string, page: number,
    pageSize: number, cursor: string | null): Promise<CommentPage> {
    if (page !== 1 && (cursor === null || cursor.length === 0)) {
      throw new CommentApiException(-1, CommentError.API, 'NetEase replies require a cursor');
    }
    const raw = await this.deps.fetchRepliesText(source.resourceId, rootId, pageSize, cursor);
    if (raw === null) {
      throw new CommentApiException(-1, CommentError.NETWORK, 'NetEase replies unavailable');
    }
    const result = parseNeteaseReplyPage(raw, page, pageSize);
    if (result.hasMore && (result.comments.length === 0 || result.nextCursor === null ||
      result.nextCursor === cursor)) {
      throw new CommentApiException(200, CommentError.API, 'NetEase replies did not advance');
    }
    return result;
  }

  async sendComment(source: CommentSource, content: string,
    target: CommentReplyTarget | null): Promise<void> {
    throw new CommentApiException(301, CommentError.PERMISSION,
      '网易发表评论需要网页端设备校验，暂不支持');
  }
}
