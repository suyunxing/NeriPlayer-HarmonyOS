/**
 * 评论面板控制器（上游 ui/viewmodel/CommentViewModel.kt 状态机直译，#476）。
 *
 * 只依赖 CommentRepository 接口，不接触 PlayerManager/播放状态；所有请求
 * 绑定（平台 + 资源 id），歌曲切换后旧结果一律丢弃。鸿蒙无协程取消，以
 * request generation 计数代替：每次 advance 后，旧异步结果按过期丢弃。
 *
 * 状态采用不可变快照（每次变更 clone 出新对象再整体替换），页面把
 * controller.state 赋给 @State 即可观察到全部变化。
 */
import { CommentSort, CommentError, CommentSource, CommentPlatform, CommentReplyTarget, SongComment, CommentPage, COMMENT_PAGE_SIZE, commentSortsSupportedBy, commentLengthLimit } from '../../../model/CommentModels';
import { CommentRepository, CommentApiException } from '../../../network/comments/CommentRepositoryCore';
import { commentRepositoryFor } from '../../../network/comments/CommentRepositories';
import { mergeComments, distinctComments, hasMoreComments, toCommentError, findComment, applyLikeToComments, applyLikeToReplies } from './CommentPanelLogic';
import { Logger } from '../../../app/Logger';

/** 评论列表的展示状态。 */
export enum CommentListStatus {
  IDLE,
  LOADING,
  SUCCESS,
  EMPTY,
  ERROR
}

/** 单条一级评论的楼中楼展开状态。 */
export class CommentReplyPanelState {
  expanded: boolean = true;
  comments: SongComment[] = [];
  page: number = 0;
  hasMore: boolean = true;
  nextCursor: string | null = null;
  loading: boolean = false;
  error: CommentError | null = null;
}

/** 评论面板的 UI 状态快照（只存语义化错误，文案由 UI 层映射）。 */
export class CommentPanelUiState {
  source: CommentSource | null = null;
  status: CommentListStatus = CommentListStatus.IDLE;
  comments: SongComment[] = [];
  page: number = 0;
  hasMore: boolean = false;
  total: number | null = null;
  totalIncludingReplies: number | null = null;
  isRefreshing: boolean = false;
  isCheckingCache: boolean = false;
  isLoadingMore: boolean = false;
  error: CommentError | null = null;
  loadMoreError: CommentError | null = null;
  sort: CommentSort = CommentSort.HOT;
  pendingSort: CommentSort | null = null;
  nextCursor: string | null = null;
  likingIds: Set<string> = new Set();
  likeError: CommentError | null = null;
  likeErrorCode: number | null = null;
  replyThreads: Map<string, CommentReplyPanelState> = new Map();
  draft: string = '';
  replyTarget: CommentReplyTarget | null = null;
  isSending: boolean = false;
  sendError: CommentError | null = null;
  sendErrorCode: number | null = null;
  sendSucceeded: boolean = false;

  clone(): CommentPanelUiState {
    const copy = new CommentPanelUiState();
    copy.source = this.source;
    copy.status = this.status;
    copy.comments = this.comments.slice();
    copy.page = this.page;
    copy.hasMore = this.hasMore;
    copy.total = this.total;
    copy.totalIncludingReplies = this.totalIncludingReplies;
    copy.isRefreshing = this.isRefreshing;
    copy.isCheckingCache = this.isCheckingCache;
    copy.isLoadingMore = this.isLoadingMore;
    copy.error = this.error;
    copy.loadMoreError = this.loadMoreError;
    copy.sort = this.sort;
    copy.pendingSort = this.pendingSort;
    copy.nextCursor = this.nextCursor;
    copy.likingIds = new Set(this.likingIds);
    const threads = new Map<string, CommentReplyPanelState>();
    this.replyThreads.forEach((thread: CommentReplyPanelState, rootId: string) => {
      const threadCopy = new CommentReplyPanelState();
      threadCopy.expanded = thread.expanded;
      threadCopy.comments = thread.comments.slice();
      threadCopy.page = thread.page;
      threadCopy.hasMore = thread.hasMore;
      threadCopy.nextCursor = thread.nextCursor;
      threadCopy.loading = thread.loading;
      threadCopy.error = thread.error;
      threads.set(rootId, threadCopy);
    });
    copy.replyThreads = threads;
    copy.draft = this.draft;
    copy.replyTarget = this.replyTarget;
    copy.isSending = this.isSending;
    copy.sendError = this.sendError;
    copy.sendErrorCode = this.sendErrorCode;
    copy.sendSucceeded = this.sendSucceeded;
    return copy;
  }

  /** 是否存在任一在途请求（点赞中/发送中/加载中）。 */
  hasBusyRequest(): boolean {
    return this.isRefreshing || this.isCheckingCache || this.isLoadingMore ||
      this.isSending || this.likingIds.size > 0 || this.pendingSort !== null;
  }
}

const CACHE_UPDATE_INDICATION_MS: number = 350;

export class CommentPanelController {
  /** 当前生效的快照；每次变更整体替换（页面 @State 赋值可观察）。 */
  state: CommentPanelUiState = new CommentPanelUiState();
  /** 状态变化通知（页面在回调里把 state 赋给 @State）。 */
  onChanged: () => void = (): void => {};

  private activeSource: CommentSource | null = null;
  private requestGeneration: number = 0;
  /** 仓库工厂，单元测试可替换。 */
  repositoryFactory: (platform: CommentPlatform) => CommentRepository = commentRepositoryFor;

  private update(mutate: (state: CommentPanelUiState) => void): void {
    const next = this.state.clone();
    mutate(next);
    this.state = next;
    this.onChanged();
  }

  private advance(): number {
    this.requestGeneration += 1;
    return this.requestGeneration;
  }

  private isCurrent(generation: number): boolean {
    return generation === this.requestGeneration;
  }

  /**
   * 歌曲切换 / 打开评论面板时调用。同一首歌重复调用不重复请求；
   * 草稿与回复目标在重开时保留。
   */
  onSourceChanged(source: CommentSource | null): void {
    if (this.activeSource !== null && source !== null &&
      this.activeSource.key() === source.key() &&
      (this.state.status !== CommentListStatus.IDLE || this.state.isCheckingCache)) {
      return;
    }
    if (this.activeSource === null && source === null) {
      return;
    }
    const previousDraft = this.state.source !== null && source !== null &&
      this.state.source.key() === source.key() ? this.state.draft : '';
    const previousTarget = this.state.source !== null && source !== null &&
      this.state.source.key() === source.key() ? this.state.replyTarget : null;

    this.activeSource = source;
    this.advance();
    if (source === null) {
      this.state = new CommentPanelUiState();
      this.onChanged();
      return;
    }
    const fresh = new CommentPanelUiState();
    fresh.source = source;
    fresh.isCheckingCache = true;
    fresh.draft = previousDraft;
    fresh.replyTarget = previousTarget;
    this.state = fresh;
    this.onChanged();
    this.startLoad(source, 1, true, false);
  }

  /**
   * 切换评论排序。新排序出结果前保留旧列表与游标（只置 pendingSort），
   * 失败时仍可继续浏览原列表；有点赞/发送在途时忽略。
   */
  selectSort(sort: CommentSort): void {
    const source = this.activeSource;
    if (source === null) {
      return;
    }
    const current = this.state;
    if (sort === (current.pendingSort ?? current.sort) ||
      !commentSortsSupportedBy(source.platform).includes(sort) ||
      current.likingIds.size > 0 || current.isSending) {
      return;
    }
    this.advance();
    this.update((next: CommentPanelUiState) => {
      next.pendingSort = sort;
      next.replyThreads = new Map();
      next.isLoadingMore = false;
      next.isRefreshing = false;
      next.isCheckingCache = false;
      next.error = null;
      next.loadMoreError = null;
    });
    this.startLoad(source, 1, true, false);
  }

  /**
   * 点赞/取消点赞一条评论（一级与楼中楼共用入口）。成功后把结果写回这条
   * 评论所有可能出现的位置；失败只记录错误，不清空列表。
   */
  async toggleLike(commentId: string): Promise<void> {
    const source = this.activeSource;
    if (source === null) {
      return;
    }
    const current = this.state;
    if (current.status !== CommentListStatus.SUCCESS || current.hasBusyRequest()) {
      return;
    }
    if (current.likingIds.has(commentId)) {
      return;
    }
    const comment = findComment(current.comments, viewThreads(current), commentId);
    if (comment === null) {
      return;
    }
    const generation = this.requestGeneration;
    const liked = !comment.isLiked;
    this.update((next: CommentPanelUiState) => {
      next.likingIds.add(commentId);
      next.likeError = null;
      next.likeErrorCode = null;
    });
    try {
      await this.repositoryFactory(source.platform).setLiked(source, commentId, liked);
      if (!this.isCurrent(generation)) {
        return;
      }
      this.update((next: CommentPanelUiState) => {
        next.comments = applyLikeToComments(next.comments, commentId, liked);
        const threads = new Map<string, CommentReplyPanelState>();
        next.replyThreads.forEach((thread: CommentReplyPanelState, rootId: string) => {
          if (!thread.comments.some((reply: SongComment): boolean => reply.id === commentId)) {
            threads.set(rootId, thread);
            return;
          }
          const copy = new CommentReplyPanelState();
          copy.expanded = thread.expanded;
          copy.comments = applyLikeToReplies(thread.comments, commentId, liked);
          copy.page = thread.page;
          copy.hasMore = thread.hasMore;
          copy.nextCursor = thread.nextCursor;
          copy.loading = thread.loading;
          copy.error = thread.error;
          threads.set(rootId, copy);
        });
        next.replyThreads = threads;
      });
    } catch (error) {
      if (this.isCurrent(generation)) {
        const apiError = error instanceof CommentApiException ? error : null;
        Logger.warn(`comment like failed: platform=${source.platform}`);
        this.update((next: CommentPanelUiState) => {
          next.likeError = toCommentError(error as Object);
          next.likeErrorCode = apiError !== null ? apiError.code : null;
        });
      }
    } finally {
      if (this.isCurrent(generation)) {
        this.update((next: CommentPanelUiState) => {
          next.likingIds.delete(commentId);
        });
      }
    }
  }

  /** 关闭点赞失败的提示（点赞结果与列表数据不受影响）。 */
  dismissLikeError(): void {
    this.update((next: CommentPanelUiState) => {
      next.likeError = null;
      next.likeErrorCode = null;
    });
  }

  /** 关闭列表加载失败提示条（已展示的旧数据继续留在界面上）。 */
  dismissLoadError(): void {
    this.update((next: CommentPanelUiState) => {
      next.error = null;
    });
  }

  /** 首屏加载失败后重试。 */
  retry(): void {
    const source = this.activeSource;
    if (source === null || this.state.isSending) {
      return;
    }
    this.update((next: CommentPanelUiState) => {
      next.status = CommentListStatus.LOADING;
      next.error = null;
    });
    this.startLoad(source, 1, true, false);
  }

  /** 下拉刷新：重新拉第 1 页并替换旧数据。 */
  refresh(): void {
    const source = this.activeSource;
    if (source === null) {
      return;
    }
    if (this.state.hasBusyRequest()) {
      return;
    }
    this.update((next: CommentPanelUiState) => {
      next.isRefreshing = true;
      next.error = null;
      next.replyThreads = new Map();
    });
    this.startLoad(source, 1, true, false);
  }

  /** 触底加载下一页（同一时刻只允许一个翻页请求）。 */
  loadMore(): void {
    const source = this.activeSource;
    if (source === null) {
      return;
    }
    const current = this.state;
    if (current.isLoadingMore || current.hasBusyRequest() || !current.hasMore ||
      current.status !== CommentListStatus.SUCCESS || current.page <= 0) {
      return;
    }
    this.update((next: CommentPanelUiState) => {
      next.isLoadingMore = true;
      next.loadMoreError = null;
    });
    this.startLoad(source, current.page + 1, false, false);
  }

  /**
   * 面板关闭时调用：状态复位（重新打开时读取当前账号的点赞状态）；
   * 若关闭时正在发送，发送错误降级为网络错误提示。
   */
  onSheetHidden(): void {
    this.advance();
    this.update((next: CommentPanelUiState) => {
      next.status = CommentListStatus.IDLE;
      next.isRefreshing = false;
      next.isCheckingCache = false;
      next.isLoadingMore = false;
      next.likingIds = new Set();
      next.pendingSort = null;
      next.likeError = null;
      next.likeErrorCode = null;
      next.replyThreads = new Map();
      if (next.isSending) {
        next.sendError = CommentError.NETWORK;
      }
      next.isSending = false;
      next.sendSucceeded = false;
    });
  }

  /** 更新输入框内容（发送中忽略输入，避免与提交内容竞争）。 */
  updateDraft(content: string): void {
    if (this.state.isSending) {
      return;
    }
    this.update((next: CommentPanelUiState) => {
      next.draft = content;
      next.sendError = null;
      next.sendErrorCode = null;
      next.sendSucceeded = false;
    });
  }

  /** 选择/取消回复目标（null 表示发表一级评论）。 */
  replyTo(target: CommentReplyTarget | null): void {
    if (this.state.isSending) {
      return;
    }
    this.update((next: CommentPanelUiState) => {
      next.replyTarget = target;
      next.sendError = null;
      next.sendErrorCode = null;
      next.sendSucceeded = false;
    });
  }

  /**
   * 发送评论：一级评论按当前排序刷新（不是最新排序先切到最新），楼中楼
   * 回复则丢掉该楼缓存重新加载第 1 页；失败保留草稿。
   */
  async sendComment(): Promise<void> {
    const source = this.activeSource;
    if (source === null) {
      return;
    }
    const current = this.state;
    const content = current.draft.trim();
    if (current.hasBusyRequest() ||
      (current.status !== CommentListStatus.SUCCESS && current.status !== CommentListStatus.EMPTY) ||
      content.length === 0 || current.draft.length > commentLengthLimit(source.platform)) {
      return;
    }
    const target = current.replyTarget;
    const generation = this.requestGeneration;
    this.update((next: CommentPanelUiState) => {
      next.isSending = true;
      next.sendError = null;
      next.sendErrorCode = null;
      next.sendSucceeded = false;
    });
    try {
      await this.repositoryFactory(source.platform).sendComment(source, content, target);
      if (!this.isCurrent(generation)) {
        return;
      }
      this.update((next: CommentPanelUiState) => {
        next.isSending = false;
        next.draft = '';
        next.replyTarget = null;
        next.sendSucceeded = true;
      });
      if (target === null) {
        if (this.state.sort === CommentSort.NEWEST) {
          this.refresh();
        } else {
          this.selectSort(CommentSort.NEWEST);
        }
      } else {
        this.update((next: CommentPanelUiState) => {
          next.replyThreads.delete(target.rootId);
        });
        this.loadReplies(target.rootId);
      }
    } catch (error) {
      if (this.isCurrent(generation)) {
        const apiError = error instanceof CommentApiException ? error : null;
        this.update((next: CommentPanelUiState) => {
          next.isSending = false;
          next.sendError = toCommentError(error as Object);
          next.sendErrorCode = apiError !== null ? apiError.code : null;
        });
      }
    }
  }

  /** 展开/收起楼中楼：首次展开先拉第 1 页回复，已有数据只切换展开状态。 */
  toggleReplies(rootId: string): void {
    const thread = this.state.replyThreads.get(rootId);
    if (thread === undefined) {
      this.loadReplies(rootId);
      return;
    }
    this.update((next: CommentPanelUiState) => {
      const copy = cloneThread(thread);
      copy.expanded = !thread.expanded;
      next.replyThreads.set(rootId, copy);
    });
  }

  /**
   * 加载某楼楼中楼的下一页。结果按 id 去重合并进对应楼层，并用返回的
   * total 回写楼层回复数；失败只记录该楼错误，不影响主列表。
   */
  async loadReplies(rootId: string): Promise<void> {
    const source = this.activeSource;
    if (source === null) {
      return;
    }
    const current = this.state;
    if (current.isRefreshing || current.isCheckingCache || current.pendingSort !== null ||
      current.status !== CommentListStatus.SUCCESS) {
      return;
    }
    if (!current.comments.some((comment: SongComment): boolean => comment.id === rootId)) {
      return;
    }
    const existing = current.replyThreads.get(rootId) ?? new CommentReplyPanelState();
    if (existing.loading || !existing.hasMore) {
      return;
    }
    const generation = this.requestGeneration;
    this.update((next: CommentPanelUiState) => {
      const copy = cloneThread(existing);
      copy.loading = true;
      copy.error = null;
      next.replyThreads.set(rootId, copy);
    });
    try {
      const result = await this.repositoryFactory(source.platform).loadReplies(
        source, rootId, existing.page + 1, COMMENT_PAGE_SIZE, existing.nextCursor);
      if (!this.isCurrent(generation)) {
        return;
      }
      const merged = mergeComments(existing.comments, result.comments);
      if (result.hasMore && merged.length === existing.comments.length) {
        throw new CommentApiException(0, CommentError.API, 'Comment replies did not advance');
      }
      this.update((next: CommentPanelUiState) => {
        next.comments = next.comments.map((comment: SongComment): SongComment => {
          if (comment.id !== rootId) {
            return comment;
          }
          const copy = new SongComment(comment.id, comment.username, comment.content, comment.platform);
          copy.userId = comment.userId;
          copy.avatarUrl = comment.avatarUrl;
          copy.likeCount = comment.likeCount;
          copy.replyCount = result.total !== null ? result.total
            : Math.max(comment.replyCount ?? 0, merged.length);
          copy.createTime = comment.createTime;
          copy.userLevel = comment.userLevel;
          copy.isLiked = comment.isLiked;
          copy.quotedComments = comment.quotedComments.slice();
          copy.previewReplies = comment.previewReplies.slice();
          copy.rootId = comment.rootId;
          copy.emotes = comment.emotes.slice();
          copy.images = comment.images.slice();
          return copy;
        });
        const latest = next.replyThreads.get(rootId);
        if (latest === undefined) {
          return;
        }
        const copy = cloneThread(latest);
        copy.comments = merged;
        copy.page = result.page;
        copy.hasMore = result.hasMore;
        copy.nextCursor = result.nextCursor;
        copy.loading = false;
        copy.error = null;
        next.replyThreads.set(rootId, copy);
      });
    } catch (error) {
      if (this.isCurrent(generation)) {
        this.update((next: CommentPanelUiState) => {
          const latest = next.replyThreads.get(rootId);
          if (latest === undefined) {
            return;
          }
          const copy = cloneThread(latest);
          copy.loading = false;
          copy.error = toCommentError(error as Object);
          next.replyThreads.set(rootId, copy);
        });
      }
    }
  }

  /**
   * 按页码发起单次评论请求：首页整体替换列表，后续页按 id 去重合并。
   * cacheFirst 时先出缓存快照再强制网络刷新；首页失败置 ERROR，后续页
   * 失败只置 loadMoreError；过期结果整体丢弃。
   */
  private async startLoad(source: CommentSource, page: number, forceRefresh: boolean,
    cacheFirst: boolean): Promise<void> {
    const repository = this.repositoryFactory(source.platform);
    const isFirstPage = page <= 1;
    const sort = this.state.pendingSort ?? this.state.sort;
    const cursor = isFirstPage ? null : this.state.nextCursor;
    const generation = this.advance();
    let cached: CommentPage | null = null;
    try {
      if (cacheFirst) {
        cached = await repository.cachedComments(source, COMMENT_PAGE_SIZE, sort);
        if (!this.isCurrent(generation)) {
          return;
        }
        const snapshot = cached;
        this.update((next: CommentPanelUiState) => {
          if (snapshot === null) {
            next.status = CommentListStatus.LOADING;
            next.isCheckingCache = false;
            return;
          }
          const comments = distinctComments(snapshot.comments);
          next.status = snapshot.comments.length === 0 ? CommentListStatus.EMPTY : CommentListStatus.SUCCESS;
          next.comments = comments;
          next.page = snapshot.page;
          next.hasMore = hasMoreComments(snapshot.hasMore, comments, snapshot.totalIncludingReplies);
          next.total = snapshot.total;
          next.totalIncludingReplies = snapshot.totalIncludingReplies;
          next.nextCursor = snapshot.nextCursor;
        });
      }
      const result = await repository.loadComments(source, page, COMMENT_PAGE_SIZE,
        forceRefresh || cached !== null, sort, cursor);
      if (!this.isCurrent(generation)) {
        return;
      }
      if (cached !== null && (cached.comments !== result.comments || cached.total !== result.total ||
        cached.hasMore !== result.hasMore)) {
        // 缓存与网络结果不同：短暂展示刷新指示再替换（上游 350ms 指示窗）。
        this.update((next: CommentPanelUiState) => {
          next.isRefreshing = true;
        });
        await sleep(CACHE_UPDATE_INDICATION_MS);
        if (!this.isCurrent(generation)) {
          return;
        }
      }
      this.update((next: CommentPanelUiState) => {
        const comments = isFirstPage ? distinctComments(result.comments)
          : mergeComments(next.comments, result.comments);
        const totalIncludingReplies = isFirstPage ? result.totalIncludingReplies
          : (result.totalIncludingReplies ?? next.totalIncludingReplies);
        next.status = comments.length === 0 ? CommentListStatus.EMPTY : CommentListStatus.SUCCESS;
        next.comments = comments;
        next.sort = sort;
        next.pendingSort = null;
        next.page = result.page;
        next.hasMore = hasMoreComments(result.hasMore, comments, totalIncludingReplies);
        next.totalIncludingReplies = totalIncludingReplies;
        next.nextCursor = result.nextCursor;
        // 后续页可能拿到服务端降级空载荷，不能把首页总数覆盖掉。
        next.total = isFirstPage ? result.total : (next.total ?? result.total);
        next.isRefreshing = false;
        next.isCheckingCache = false;
        next.isLoadingMore = false;
        next.error = null;
        next.loadMoreError = null;
      });
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      Logger.warn(`load comments failed: platform=${source.platform}, resourceId=${source.resourceId}, page=${page}`);
      this.update((next: CommentPanelUiState) => {
        if (isFirstPage) {
          next.status = cached !== null ? next.status
            : (next.comments.length > 0 ? CommentListStatus.SUCCESS : CommentListStatus.ERROR);
          next.pendingSort = null;
          next.isRefreshing = false;
          next.isCheckingCache = false;
          next.isLoadingMore = false;
          if (cached === null) {
            next.error = toCommentError(error as Object);
          }
        } else {
          next.isLoadingMore = false;
          next.loadMoreError = toCommentError(error as Object);
        }
      });
    }
  }
}

function cloneThread(thread: CommentReplyPanelState): CommentReplyPanelState {
  const copy = new CommentReplyPanelState();
  copy.expanded = thread.expanded;
  copy.comments = thread.comments.slice();
  copy.page = thread.page;
  copy.hasMore = thread.hasMore;
  copy.nextCursor = thread.nextCursor;
  copy.loading = thread.loading;
  copy.error = thread.error;
  return copy;
}

function viewThreads(state: CommentPanelUiState): Map<string, SongComment[]> {
  const threads = new Map<string, SongComment[]>();
  state.replyThreads.forEach((thread: CommentReplyPanelState, rootId: string) => {
    threads.set(rootId, thread.comments);
  });
  return threads;
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve) => {
    setTimeout(resolve, ms);
  });
}
