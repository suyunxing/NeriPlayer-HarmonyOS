/**
 * 评论仓库域核心（上游 platform/comments 域直译，#476/7588e073）：
 * 业务异常、五分钟 TTL + LRU 内存缓存、仓库接口与网易分页推进校验。
 *
 * 仓库接口面向 UI 只暴露统一模型；HTTP 细节由 NeteaseApi/BiliApi 端点
 * 经 client deps 基类注入（Live 子类接真实 API，单测用 fake 子类）。
 */
import { CommentPage, CommentPlatform, CommentSort, COMMENT_PAGE_SIZE, CommentSource, CommentError, CommentReplyTarget } from '../../model/CommentModels';
import { commentPlatformName } from '../../model/CommentModels';

/** 平台评论接口返回的业务错误（HTTP 成功但业务 code 异常）。 */
export class CommentApiException extends Error {
  readonly code: number;
  readonly reason: CommentError;

  constructor(code: number, reason: CommentError, message: string) {
    super(message);
    this.code = code;
    this.reason = reason;
  }
}

interface CommentCacheEntry {
  page: CommentPage;
  savedAtMs: number;
}

const COMMENT_CACHE_TTL_MS: number = 5 * 60 * 1000;
const COMMENT_CACHE_MAX_ENTRIES: number = 48;

/**
 * 按平台、资源、排序、页码、游标与会话隔离的评论分页内存缓存。
 * 五分钟 TTL + LRU 上限 48 条；宿主切换账号（sessionKey 变化）自动隔离。
 */
export class CommentMemoryCache {
  private entries: Map<string, CommentCacheEntry> = new Map();
  private nowMs: () => number;

  constructor(nowMs: () => number = (): number => Date.now()) {
    this.nowMs = nowMs;
  }

  private static buildKey(platform: string, resourceId: number, sort: CommentSort,
    pageSize: number, page: number, cursor: string | null, sessionKey: string | null): string {
    return `${platform}:${resourceId}:${sort}:${pageSize}:${page}:` +
      `${cursor ?? ''}:${sessionKey ?? ''}`;
  }

  /** 读取指定页缓存；超过 TTL 的条目顺手删除并返回 null。 */
  get(platform: string, resourceId: number, page: number,
    sort: CommentSort = CommentSort.HOT, pageSize: number = COMMENT_PAGE_SIZE,
    cursor: string | null = null, sessionKey: string | null = null): CommentPage | null {
    const key = CommentMemoryCache.buildKey(platform, resourceId, sort, pageSize, page, cursor, sessionKey);
    const entry = this.entries.get(key);
    if (entry === undefined) {
      return null;
    }
    // 重新插入维护 LRU 访问序（Map 迭代按插入序，删除重插即「最近访问置尾」）。
    this.entries.delete(key);
    if (this.nowMs() - entry.savedAtMs > COMMENT_CACHE_TTL_MS) {
      return null;
    }
    this.entries.set(key, entry);
    return entry.page;
  }

  /** 写入指定页缓存，同键覆盖并刷新 TTL 起点。 */
  put(platform: string, resourceId: number, page: number, pageData: CommentPage,
    sort: CommentSort = CommentSort.HOT, pageSize: number = COMMENT_PAGE_SIZE,
    cursor: string | null = null, sessionKey: string | null = null): void {
    const key = CommentMemoryCache.buildKey(platform, resourceId, sort, pageSize, page, cursor, sessionKey);
    this.entries.delete(key);
    this.entries.set(key, { page: pageData, savedAtMs: this.nowMs() });
    while (this.entries.size > COMMENT_CACHE_MAX_ENTRIES) {
      const eldest = this.entries.keys().next();
      if (eldest.done) {
        break;
      }
      this.entries.delete(eldest.value);
    }
  }

  /** 失效某资源的全部分页（点赞/发评后调用）。 */
  invalidate(platform: string, resourceId: number): void {
    const prefix = `${platform}:${resourceId}:`;
    const stale: string[] = [];
    this.entries.forEach((_, key: string) => {
      if (key.startsWith(prefix)) {
        stale.push(key);
      }
    });
    for (const key of stale) {
      this.entries.delete(key);
    }
  }

  /** 清空全部评论分页缓存。 */
  clear(): void {
    this.entries.clear();
  }
}

/**
 * 网易云评论分页推进校验：hasMore 但本页为空，或最新排序的时间游标未前进，
 * 都说明服务端分页停滞，按 API 错误抛出而不是让 UI 无限加载同一页。
 */
export function requireNeteaseCommentProgress(result: CommentPage, sort: CommentSort, cursor: string | null): void {
  const stalledTimeCursor = sort === CommentSort.NEWEST &&
    (result.nextCursor === null || result.nextCursor.length === 0 || result.nextCursor === cursor);
  if (result.hasMore && (result.comments.length === 0 || stalledTimeCursor)) {
    throw new CommentApiException(200, CommentError.API, 'NetEase comment pagination did not advance');
  }
}

/**
 * 评论数据源统一接口。UI/控制器只依赖本接口，不接触平台 HTTP 细节。
 *
 * 网易云的点赞与发评依赖上游的网页端易盾设备校验（checkToken），鸿蒙侧
 * 无该设施，由 NeteaseCommentRepository 以 PERMISSION 错误拒绝；B 站
 * 仅需 SESSDATA + bili_jct，写操作完整支持。
 */
export interface CommentRepository {
  readonly platform: CommentPlatform;

  cachedComments(source: CommentSource, pageSize: number, sort: CommentSort): Promise<CommentPage | null>;

  loadComments(source: CommentSource, page: number, pageSize: number,
    forceRefresh: boolean, sort: CommentSort, cursor: string | null): Promise<CommentPage>;

  setLiked(source: CommentSource, commentId: string, liked: boolean): Promise<void>;

  loadReplies(source: CommentSource, rootId: string, page: number,
    pageSize: number, cursor: string | null): Promise<CommentPage>;

  sendComment(source: CommentSource, content: string, target: CommentReplyTarget | null): Promise<void>;
}
