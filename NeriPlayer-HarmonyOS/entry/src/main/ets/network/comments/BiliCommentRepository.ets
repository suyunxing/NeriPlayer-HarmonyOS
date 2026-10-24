/**
 * B 站评论仓库（上游 platform/comments/repository/BiliCommentRepository.kt
 * 直译，#476）。B 站评论接口按 avid（oid）定位资源，而鸿蒙侧 B 站歌曲只带
 * bvid：先经 wbi/view 解析出 avid 并校验身份（bvid/cid 一致），解析结果按
 * CommentSource LRU 缓存；成功的评论响应不能作为身份依据（打包 id 也可能
 * 命中另一条视频），校验只在 getVideoInfo 摘要上做。
 */
import { CommentPage, CommentPlatform, CommentSort, CommentSource, CommentError, CommentReplyTarget } from '../../model/CommentModels';
import { commentPlatformName, commentSortsSupportedBy, commentLengthLimit } from '../../model/CommentModels';
import { CommentApiException, CommentMemoryCache, CommentRepository } from './CommentRepositoryCore';
import { parseBiliCommentPage, biliCommentError } from './BiliCommentMapper';
import { BiliApi, BiliVideoInfo, BiliVideoPage } from '../BiliApi';

const MAX_RESOLVED_RESOURCES: number = 32;

/**
 * B 站评论 HTTP 依赖基类：生产环境由 LiveBiliCommentClientDeps 接 BiliApi，
 * 单元测试用 fake 子类注入固定响应（视频摘要 / 评论文本 / 登录态）。
 */
export class BiliCommentClientDeps {
  /** 按 bvid 取视频摘要（avid + 分 P cid 列表）；解析失败返回 null。 */
  async fetchVideoInfo(bvid: string): Promise<BiliVideoInfo | null> {
    return null;
  }

  async fetchCommentsText(aid: number, page: number, pageSize: number,
    sort: number): Promise<string | null> {
    return null;
  }

  async fetchRepliesText(aid: number, rootId: string, page: number,
    pageSize: number): Promise<string | null> {
    return null;
  }

  async likeText(aid: number, commentId: string, liked: boolean): Promise<string | null> {
    return null;
  }

  async sendText(aid: number, content: string, rootId: string | null,
    parentId: string | null): Promise<string | null> {
    return null;
  }

  sessionKey(): string | null {
    return null;
  }
}

/** 接 BiliApi 的生产依赖。 */
export class LiveBiliCommentClientDeps extends BiliCommentClientDeps {
  async fetchVideoInfo(bvid: string): Promise<BiliVideoInfo | null> {
    try {
      return await BiliApi.getVideoInfo(bvid);
    } catch (error) {
      return null;
    }
  }

  async fetchCommentsText(aid: number, page: number, pageSize: number,
    sort: number): Promise<string | null> {
    return BiliApi.getVideoComments(aid, page, pageSize, sort);
  }

  async fetchRepliesText(aid: number, rootId: string, page: number,
    pageSize: number): Promise<string | null> {
    return BiliApi.getVideoCommentReplies(aid, rootId, page, pageSize);
  }

  async likeText(aid: number, commentId: string, liked: boolean): Promise<string | null> {
    return BiliApi.setVideoCommentLiked(aid, commentId, liked);
  }

  async sendText(aid: number, content: string, rootId: string | null,
    parentId: string | null): Promise<string | null> {
    return BiliApi.sendVideoComment(aid, content, rootId, parentId);
  }

  sessionKey(): string | null {
    return BiliApi.biliCommentSessionKey();
  }
}

export class BiliCommentRepository implements CommentRepository {
  readonly platform: CommentPlatform = CommentPlatform.BILIBILI;
  private cache: CommentMemoryCache;
  private deps: BiliCommentClientDeps;
  /** CommentSource -> 已确认的 avid，LRU（Map 插入序 + 重插置尾）。 */
  private resolvedResourceIds: Map<CommentSource, number> = new Map();

  constructor(cache: CommentMemoryCache, deps: BiliCommentClientDeps) {
    this.cache = cache;
    this.deps = deps;
  }

  async cachedComments(source: CommentSource, pageSize: number,
    sort: CommentSort): Promise<CommentPage | null> {
    const resourceId = this.resolvedResourceIds.get(source);
    if (resourceId === undefined) {
      return null;
    }
    return this.cache.get(commentPlatformName(this.platform), resourceId, 1,
      sort, pageSize, null, this.deps.sessionKey());
  }

  async loadComments(source: CommentSource, page: number, pageSize: number,
    forceRefresh: boolean, sort: CommentSort, cursor: string | null): Promise<CommentPage> {
    if (!commentSortsSupportedBy(this.platform).includes(sort)) {
      throw new CommentApiException(-1, CommentError.API, 'Unsupported Bili comment sort');
    }
    const resourceId = await this.resolveResourceId(source);
    const sessionKey = this.deps.sessionKey();
    if (!forceRefresh) {
      const cached = this.cache.get(commentPlatformName(this.platform), resourceId,
        page, sort, pageSize, cursor, sessionKey);
      if (cached !== null) {
        return cached;
      }
    }

    const raw = await this.deps.fetchCommentsText(resourceId, page, pageSize,
      sort === CommentSort.NEWEST ? 0 : 1);
    if (raw === null) {
      throw new CommentApiException(-1, CommentError.NETWORK, 'Bili comments unavailable');
    }
    const result = parseBiliCommentPage(raw, page, pageSize, true);
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
    const resourceId = await this.resolveResourceId(source);
    try {
      const raw = await this.deps.likeText(resourceId, commentId, liked);
      if (raw === null) {
        throw new CommentApiException(-1, CommentError.NETWORK, 'Bili comment like unavailable');
      }
      const code = BiliCommentRepository.codeOf(raw);
      if (code !== 0) {
        throw new CommentApiException(code, biliCommentError(code),
          `Bili comment like failed: ${code}`);
      }
    } finally {
      this.cache.invalidate(commentPlatformName(this.platform), resourceId);
    }
  }

  async loadReplies(source: CommentSource, rootId: string, page: number,
    pageSize: number, cursor: string | null): Promise<CommentPage> {
    const resourceId = await this.resolveResourceId(source);
    const raw = await this.deps.fetchRepliesText(resourceId, rootId, page, pageSize);
    if (raw === null) {
      throw new CommentApiException(-1, CommentError.NETWORK, 'Bili comment replies unavailable');
    }
    return parseBiliCommentPage(raw, page, pageSize);
  }

  async sendComment(source: CommentSource, content: string,
    target: CommentReplyTarget | null): Promise<void> {
    if (content.trim().length === 0 || content.length > commentLengthLimit(this.platform)) {
      throw new CommentApiException(-1, CommentError.API, 'Invalid Bili comment content');
    }
    const resourceId = await this.resolveResourceId(source);
    try {
      const rootId = target !== null ? target.rootId : null;
      const parentId = target !== null ? target.commentId : null;
      const raw = await this.deps.sendText(resourceId, content, rootId, parentId);
      if (raw === null) {
        throw new CommentApiException(-1, CommentError.NETWORK, 'Bili comment send unavailable');
      }
      const code = BiliCommentRepository.codeOf(raw);
      if (code !== 0) {
        throw new CommentApiException(code, biliCommentError(code),
          `Bili comment send failed: ${code}`);
      }
    } finally {
      this.cache.invalidate(commentPlatformName(this.platform), resourceId);
    }
  }

  /**
   * 把 CommentSource 解析为已确认的 avid。校验：bvid 必须能解析出视频且
   * avid > 0；显式数字 id（历史打包形态）必须与解析结果一致；subResourceId
   *（cid）必须在视频分 P 列表中。校验不过按 API 错误抛出——宁可报错也不把
   * 评论发到另一条视频下。
   */
  private async resolveResourceId(source: CommentSource): Promise<number> {
    const cached = this.resolvedResourceIds.get(source);
    if (cached !== undefined) {
      this.resolvedResourceIds.delete(source);
      this.resolvedResourceIds.set(source, cached);
      return cached;
    }

    const bvid = source.secondaryId ?? '';
    if (bvid.length === 0 && !(source.resourceId > 0)) {
      throw new CommentApiException(-1, CommentError.API,
        `Unable to verify Bili comment resource: ${source.resourceId}`);
    }
    let info: BiliVideoInfo | null = null;
    if (bvid.length > 0) {
      info = await this.deps.fetchVideoInfo(bvid);
    }
    if (info === null || info.aid <= 0 ||
      (source.hasExplicitResourceId && info.aid !== source.resourceId) ||
      (source.secondaryId !== null && info.bvid !== source.secondaryId)) {
      throw new CommentApiException(-1, CommentError.API,
        `Unable to verify Bili comment resource: ${source.resourceId}`);
    }
    if (source.subResourceId !== null) {
      const cidKnown = info.pages.some((page: BiliVideoPage): boolean => page.cid === source.subResourceId);
      if (!cidKnown) {
        throw new CommentApiException(-1, CommentError.API,
          `Bili comment resource cid mismatch: ${source.subResourceId}`);
      }
    }

    const avid = info.aid;
    this.resolvedResourceIds.set(source, avid);
    while (this.resolvedResourceIds.size > MAX_RESOLVED_RESOURCES) {
      const eldest = this.resolvedResourceIds.keys().next();
      if (eldest.done) {
        break;
      }
      this.resolvedResourceIds.delete(eldest.value);
    }
    return avid;
  }

  /** 业务 code 判定：响应缺 code 字段时按上游 optInt 默认 -1 处理。 */
  private static codeOf(raw: string): number {
    const code = (JSON.parse(raw) as Record<string, Object>)['code'];
    return code === undefined ? -1 : Number(code);
  }
}
