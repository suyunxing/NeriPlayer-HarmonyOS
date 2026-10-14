/**
 * 网易云评论 JSON -> 统一评论模型（上游 platform/comments/mapper/NeteaseCommentMapper.kt
 * 直译，#432/12351888）。所有网易评论字段解析集中在这里，平台 JSON 不向 UI 泄漏。
 */
import { CommentPage, CommentPlatform, CommentError, CommentEmote, CommentQuote, SongComment } from '../../model/CommentModels';
import { CommentApiException } from './CommentRepositoryCore';
import { neteaseEmoteUrlMap } from './NeteaseEmoteCatalog';

interface NeteaseCommentUserJson {
  userId?: number;
  nickname?: string;
  avatarUrl?: string;
  level?: number;
}

interface NeteaseBeRepliedJson {
  user?: NeteaseCommentUserJson;
  content?: string;
  status?: number;
}

interface NeteaseFloorCommentJson {
  replyCount?: number;
  comments?: NeteaseCommentJson[];
}

interface NeteaseCommentJson {
  commentId?: number;
  time?: number;
  content?: string;
  likedCount?: number;
  liked?: boolean;
  replyCount?: number;
  parentCommentId?: number;
  user?: NeteaseCommentUserJson;
  beReplied?: NeteaseBeRepliedJson[];
  showFloorComment?: NeteaseFloorCommentJson;
}

interface NeteaseCommentDataJson {
  comments?: NeteaseCommentJson[];
  totalCount?: number;
  total?: number;
  hasMore?: boolean;
  more?: boolean;
  cursor?: string;
  time?: number;
}

interface NeteaseCommentResponseJson {
  code?: number;
  data?: NeteaseCommentDataJson;
  comments?: NeteaseCommentJson[];
  totalCount?: number;
  total?: number;
  hasMore?: boolean;
  more?: boolean;
  cursor?: string;
}

/**
 * 网易云业务错误码 -> 统一错误分类。
 */
export function neteaseCommentError(code: number): CommentError {
  if (code === 301 || code === 315 || code === 401 || code === 403 || code === -460) {
    return CommentError.PERMISSION;
  }
  if (code === 404) {
    return CommentError.NOT_FOUND;
  }
  if (code >= 500 && code <= 599) {
    return CommentError.SERVER;
  }
  return CommentError.API;
}

/**
 * 网易云评论列表 JSON -> 评论页。
 *
 * 响应可能是新形态（{code, data:{comments,...}}）或老形态（comments 挂根对象）；
 * hasMore 三级回退：hasMore 字段 -> more 字段 -> 按总数推算 -> 按本页条数推算。
 */
export function parseNeteaseCommentPage(rawJson: string, page: number, pageSize: number): CommentPage {
  const root = JSON.parse(rawJson) as NeteaseCommentResponseJson;
  const code = root.code ?? -1;
  if (code !== 200) {
    throw new CommentApiException(code, neteaseCommentError(code), `NetEase comment API failed: code=${code}`);
  }
  let data: NeteaseCommentDataJson | NeteaseCommentResponseJson;
  if (root.data !== undefined) {
    if (root.data.comments === undefined) {
      throw new CommentApiException(200, CommentError.API, 'Invalid NetEase comment data');
    }
    data = root.data;
  } else {
    data = root;
  }

  const rawComments = data.comments ?? [];
  const comments: SongComment[] = [];
  for (const item of rawComments) {
    comments.push(parseNeteaseComment(item, true));
  }

  const rawTotal = data.totalCount ?? data.total ?? -1;
  const total = rawTotal >= 0 ? rawTotal : null;
  let hasMore: boolean;
  if (data.hasMore !== undefined) {
    hasMore = data.hasMore;
  } else if (data.more !== undefined) {
    hasMore = data.more;
  } else if (total !== null) {
    hasMore = page * pageSize < total;
  } else {
    hasMore = comments.length >= pageSize;
  }
  const rawCursor = data.cursor ?? '';
  const nextCursor = rawCursor.length > 0 && rawCursor !== 'null' ? rawCursor : null;

  return new CommentPage(comments, page, pageSize, total, hasMore, nextCursor);
}

/**
 * 单条网易云评论映射：user 子对象取昵称/头像/等级，时间戳已是毫秒，
 * 回复数做 replyCount -> showFloorComment.replyCount 双位置防御性回退。
 */
function parseNeteaseComment(item: NeteaseCommentJson, includePreview: boolean): SongComment {
  const user = item.user ?? {};
  const rawTime = item.time ?? 0;
  const createTime = rawTime > 0 ? rawTime : null;
  // 正文原样保留（含表情标记），UI 按 emotes 自行切分渲染。
  const contentText = item.content ?? '';

  const comment = new SongComment(
    `${item.commentId ?? 0}`,
    user.nickname ?? '',
    contentText,
    CommentPlatform.NETEASE
  );
  const userId = user.userId ?? 0;
  comment.userId = userId > 0 ? `${userId}` : null;
  const avatar = user.avatarUrl ?? '';
  comment.avatarUrl = avatar.length > 0 ? avatar : null;
  comment.likeCount = item.likedCount ?? 0;
  comment.replyCount = resolveNeteaseReplyCount(item);
  comment.createTime = createTime;
  const level = user.level ?? 0;
  comment.userLevel = level > 0 ? level : null;
  comment.isLiked = item.liked ?? false;

  for (const quote of item.beReplied ?? []) {
    const status = quote.status ?? 0;
    const content = status === -5 || quote.content === undefined || quote.content === null
      ? null : quote.content;
    comment.quotedComments.push(new CommentQuote(quote.user?.nickname ?? '', content));
  }

  if (includePreview) {
    for (const reply of item.showFloorComment?.comments ?? []) {
      comment.previewReplies.push(parseNeteaseComment(reply, false));
    }
  }

  const parentCommentId = item.parentCommentId ?? 0;
  comment.rootId = parentCommentId > 0 ? `${parentCommentId}` : null;
  comment.emotes = parseNeteaseEmotes(contentText);
  return comment;
}

/**
 * 网易云正文里的 `[名称]` 表情标记 -> 统一表情模型。
 *
 * 只展开能命中内置表情表的标记（未知 `[xxx]` 当纯文本），同一标记多次出现只产出一条；
 * 正文不改写，切段交给 UI。手工扫描与上游正则 `\[[^\[\]]+]` 等价：标记非空、
 * 内部不含 `[`、非重叠。
 */
function parseNeteaseEmotes(content: string): CommentEmote[] {
  if (content.length === 0) {
    return [];
  }
  const catalog = neteaseEmoteUrlMap();
  const result: CommentEmote[] = [];
  let cursor = 0;
  while (cursor < content.length) {
    const start = content.indexOf('[', cursor);
    if (start < 0) {
      break;
    }
    const end = content.indexOf(']', start + 1);
    if (end < 0) {
      break;
    }
    const inner = content.substring(start + 1, end);
    if (inner.length === 0 || inner.indexOf('[') >= 0) {
      // 该位置匹配失败，从下一个字符继续找 `[`（内部的 `[` 仍可能成对）。
      cursor = start + 1;
      continue;
    }
    const url = catalog.get(inner);
    if (url !== undefined) {
      const token = content.substring(start, end + 1);
      if (!result.some((seen: CommentEmote): boolean => seen.placeholder === token)) {
        result.push(new CommentEmote(token, url));
      }
    }
    cursor = end + 1;
  }
  return result;
}

/**
 * 网易云楼中楼回复分页解析：复用列表解析后，把 nextCursor 换成楼中楼接口
 * 自己的游标（优先 data.time，缺失回退本页最后一条回复的发布时间）。
 */
export function parseNeteaseReplyPage(rawJson: string, page: number, pageSize: number): CommentPage {
  const result = parseNeteaseCommentPage(rawJson, page, pageSize);
  const root = JSON.parse(rawJson) as NeteaseCommentResponseJson;
  if (root.data === undefined) {
    throw new CommentApiException(200, CommentError.API, 'Missing NetEase reply data');
  }
  const rawTime = root.data.time ?? 0;
  let cursor: string | null = null;
  if (rawTime > 0) {
    cursor = `${rawTime}`;
  } else if (result.comments.length > 0) {
    const last = result.comments[result.comments.length - 1];
    cursor = last.createTime !== null ? `${last.createTime}` : null;
  }
  return new CommentPage(result.comments, result.page, result.pageSize, result.total,
    result.hasMore, cursor, result.totalIncludingReplies);
}

/**
 * 网易云回复数的位置随接口形态而变：老接口顶层 replyCount，
 * 新版 /api/v1/resource/comments 放在 showFloorComment.replyCount。
 * 两处都没有时返回 null（UI 隐藏该字段，不能显示成 0 条回复）。
 */
function resolveNeteaseReplyCount(item: NeteaseCommentJson): number | null {
  const direct = item.replyCount ?? -1;
  if (direct >= 0) {
    return direct;
  }
  const floor = item.showFloorComment?.replyCount ?? -1;
  return floor >= 0 ? floor : null;
}
