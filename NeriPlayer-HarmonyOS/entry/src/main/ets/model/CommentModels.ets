/**
 * 评论域统一模型（UPSTREAM_SYNC_PLAN F-3，上游 #432/12351888 + #476/7588e073 的
 * data/model/comments 域直译）。
 *
 * 各平台原始 JSON 只在 mapper 层解析（network/comments/*CommentMapper.ets），
 * 不向 UI 泄漏平台字段；本文件保持纯逻辑，可确定性单测。
 */

/** 评论来源平台（由歌曲的逻辑音源决定，与最终播放地址无关）。 */
export enum CommentPlatform {
  NETEASE = 0,
  BILIBILI = 1
}

/** 平台的字符串名（缓存键组成部分，与上游 platform.name 对齐）。 */
export function commentPlatformName(platform: CommentPlatform): string {
  return platform === CommentPlatform.BILIBILI ? 'BILIBILI' : 'NETEASE';
}

/** 评论列表排序。 */
export enum CommentSort {
  HOT = 0,
  NEWEST = 1,
  RECOMMENDED = 2
}

/** 平台支持的排序档位（网易云三档，B 站只有热门/最新）。 */
export function commentSortsSupportedBy(platform: CommentPlatform): CommentSort[] {
  if (platform === CommentPlatform.BILIBILI) {
    return [CommentSort.HOT, CommentSort.NEWEST];
  }
  return [CommentSort.HOT, CommentSort.NEWEST, CommentSort.RECOMMENDED];
}

/** 各平台单条评论正文长度上限：网易云 140，B 站 1000。 */
export function commentLengthLimit(platform: CommentPlatform): number {
  return platform === CommentPlatform.NETEASE ? 140 : 1000;
}

/** 评论加载失败的原因分类（UI 据此区分「暂无评论」与「加载失败」）。 */
export enum CommentError {
  NETWORK,
  PERMISSION,
  NOT_FOUND,
  CLOSED,
  SERVER,
  API,
  UNKNOWN
}

/** 评论分页每页条数。 */
export const COMMENT_PAGE_SIZE: number = 20;

/**
 * 评论里的一张配图（B 站 content.pictures）。
 * width/height 为平台给出的原始像素，未知为 0；aspectRatio 在尺寸不可信时回退 1，
 * 避免图片加载完成前的高度跳动。
 */
export class CommentImage {
  url: string;
  width: number;
  height: number;

  constructor(url: string, width: number = 0, height: number = 0) {
    this.url = url;
    this.width = width;
    this.height = height;
  }

  aspectRatio(): number {
    if (this.width > 0 && this.height > 0) {
      return this.width / this.height;
    }
    return 1;
  }
}

/** 评论正文里的一条内联表情：placeholder 是正文中出现的标记文本（如 [doge]）。 */
export class CommentEmote {
  placeholder: string;
  url: string;

  constructor(placeholder: string, url: string) {
    this.placeholder = placeholder;
    this.url = url;
  }
}

/** 被引用的楼中楼摘要（网易云 beReplied）。 */
export class CommentQuote {
  username: string;
  content: string | null;

  constructor(username: string, content: string | null) {
    this.username = username;
    this.content = content;
  }
}

/** 发送评论时的回复目标（楼中楼）。 */
export class CommentReplyTarget {
  commentId: string;
  rootId: string;
  username: string;

  constructor(commentId: string, rootId: string, username: string) {
    this.commentId = commentId;
    this.rootId = rootId;
    this.username = username;
  }
}

/** 统一评论模型：平台 JSON 只在 mapper 层解析，UI 不接触平台字段。 */
export class SongComment {
  /** 平台内唯一评论 id（网易 commentId / B 站 rpid），用于去重与点赞定位。 */
  id: string;
  userId: string | null;
  username: string;
  avatarUrl: string | null;
  content: string;
  likeCount: number;
  /** 楼中楼数量；平台未提供时为 null（UI 隐藏，不能显示成 0 条）。 */
  replyCount: number | null;
  /** 发布时间 Unix 毫秒（各平台已归一化）。 */
  createTime: number | null;
  platform: CommentPlatform;
  userLevel: number | null;
  isLiked: boolean;
  quotedComments: CommentQuote[];
  /** 一级评论自带的预览回复（网易云 showFloorComment / B 站 replies）。 */
  previewReplies: SongComment[];
  rootId: string | null;
  emotes: CommentEmote[];
  images: CommentImage[];

  constructor(id: string, username: string, content: string, platform: CommentPlatform) {
    this.id = id;
    this.userId = null;
    this.username = username;
    this.avatarUrl = null;
    this.content = content;
    this.likeCount = 0;
    this.replyCount = null;
    this.createTime = null;
    this.platform = platform;
    this.userLevel = null;
    this.isLiked = false;
    this.quotedComments = [];
    this.previewReplies = [];
    this.rootId = null;
    this.emotes = [];
    this.images = [];
  }
}

/** 一页评论数据。 */
export class CommentPage {
  comments: SongComment[];
  /** 页码，从 1 开始。 */
  page: number;
  pageSize: number;
  /** 评论总数，平台未提供时为 null。 */
  total: number | null;
  hasMore: boolean;
  nextCursor: string | null;
  /** 一级评论及其楼中楼的总数（B 站 acount），用于核对列表是否已读完。 */
  totalIncludingReplies: number | null;

  constructor(comments: SongComment[], page: number, pageSize: number,
    total: number | null, hasMore: boolean, nextCursor: string | null,
    totalIncludingReplies: number | null = null) {
    this.comments = comments;
    this.page = page;
    this.pageSize = pageSize;
    this.total = total;
    this.hasMore = hasMore;
    this.nextCursor = nextCursor;
    this.totalIncludingReplies = totalIncludingReplies;
  }
}

/**
 * 歌曲对应的评论逻辑音源。
 *
 * resourceId：网易云为歌曲 id；B 站侧为打包播放 id（鸿蒙侧 B 站歌曲通常只有
 * bvid，resourceId 置 0，仓库层按 secondaryId 解析出 avid 后再请求）。
 * secondaryId：B 站 bvid（若已知）；subResourceId：B 站 cid（分 P 校验）。
 */
export class CommentSource {
  platform: CommentPlatform;
  resourceId: number;
  secondaryId: string | null;
  subResourceId: number | null;
  resourceTitle: string | null;
  hasExplicitResourceId: boolean;

  constructor(platform: CommentPlatform, resourceId: number,
    secondaryId: string | null = null, subResourceId: number | null = null,
    resourceTitle: string | null = null, hasExplicitResourceId: boolean = false) {
    this.platform = platform;
    this.resourceId = resourceId;
    this.secondaryId = secondaryId;
    this.subResourceId = subResourceId;
    this.resourceTitle = resourceTitle;
    this.hasExplicitResourceId = hasExplicitResourceId;
  }

  /** 逻辑来源键（B 站分页缓存另按确认后的 aid 绑定）。 */
  key(): string {
    return `${commentPlatformName(this.platform)}:${this.resourceId}`;
  }
}
