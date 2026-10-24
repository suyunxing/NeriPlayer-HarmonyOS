/**
 * 评论面板纯逻辑（上游 CommentViewModel 中的无副作用部分抽出，便于确定性
 * 单测）：列表合并/读完判定/点赞写回/目标查找/错误归一/时间与富文本切分。
 */
import { CommentError, CommentEmote, SongComment } from '../../../model/CommentModels';
import { CommentApiException } from '../../../network/comments/CommentRepositoryCore';

/**
 * 按 id 去重合并（保留既有评论，新页追加）。
 */
export function mergeComments(existing: SongComment[], incoming: SongComment[]): SongComment[] {
  if (incoming.length === 0) {
    return existing;
  }
  if (existing.length === 0) {
    return distinctComments(incoming);
  }
  const seen = new Set<string>();
  for (const comment of existing) {
    seen.add(comment.id);
  }
  const merged = existing.slice();
  for (const comment of incoming) {
    if (!seen.has(comment.id)) {
      seen.add(comment.id);
      merged.push(comment);
    }
  }
  return merged;
}

export function distinctComments(comments: SongComment[]): SongComment[] {
  const seen = new Set<string>();
  const result: SongComment[] = [];
  for (const comment of comments) {
    if (!seen.has(comment.id)) {
      seen.add(comment.id);
      result.push(comment);
    }
  }
  return result;
}

/**
 * 「是否还有下一页」判定：接口 hasMore 优先；B 站提供含楼中楼的总数
 * （totalIncludingReplies）时按「一级 + 各自 replyCount」核对剩余量——
 * 预览回复已计入 replyCount，不能重复累加；计数不一致时沿用接口状态。
 */
export function hasMoreComments(hasMore: boolean, comments: SongComment[],
  totalIncludingReplies: number | null): boolean {
  if (!hasMore || totalIncludingReplies === null) {
    return hasMore;
  }
  let remaining = totalIncludingReplies;
  for (const comment of comments) {
    if (remaining <= 0) {
      return true;
    }
    remaining--;
    const replies = comment.replyCount !== null && comment.replyCount > 0 ? comment.replyCount : 0;
    // 超出总数说明计数不一致，继续沿用接口的分页状态。
    if (replies > remaining) {
      return true;
    }
    remaining -= replies;
  }
  return remaining !== 0;
}

/**
 * 异常 -> 语义化评论错误（网络异常归一为 NETWORK）。
 */
export function toCommentError(error: Object): CommentError {
  if (error instanceof CommentApiException) {
    return error.reason;
  }
  const message = error instanceof Error ? error.message : `${error}`;
  if (message.indexOf('timed out') >= 0 || message.indexOf('network') >= 0 ||
    message.indexOf('Connection') >= 0 || message.indexOf('Failed to connect') >= 0) {
    return CommentError.NETWORK;
  }
  return CommentError.UNKNOWN;
}

/**
 * 点赞目标可能是一级评论、预览回复或展开的楼中楼，三者共用同一 id 空间，
 * 按「一级 -> 预览 -> 展开」顺序查找。
 */
export function findComment(comments: SongComment[], replyThreads: Map<string, SongComment[]>,
  commentId: string): SongComment | null {
  for (const comment of comments) {
    if (comment.id === commentId) {
      return comment;
    }
  }
  for (const comment of comments) {
    for (const reply of comment.previewReplies) {
      if (reply.id === commentId) {
        return reply;
      }
    }
  }
  const roots: string[] = [];
  replyThreads.forEach((_, rootId: string) => {
    roots.push(rootId);
  });
  for (const rootId of roots) {
    const thread = replyThreads.get(rootId) ?? [];
    for (const reply of thread) {
      if (reply.id === commentId) {
        return reply;
      }
    }
  }
  return null;
}

/** 克隆一条评论（浅拷贝；previewReplies/emotes 等数组引用共享，写回时整体替换）。 */
function cloneComment(comment: SongComment): SongComment {
  const copy = new SongComment(comment.id, comment.username, comment.content, comment.platform);
  copy.userId = comment.userId;
  copy.avatarUrl = comment.avatarUrl;
  copy.likeCount = comment.likeCount;
  copy.replyCount = comment.replyCount;
  copy.createTime = comment.createTime;
  copy.userLevel = comment.userLevel;
  copy.isLiked = comment.isLiked;
  copy.quotedComments = comment.quotedComments.slice();
  copy.previewReplies = comment.previewReplies.slice();
  copy.rootId = comment.rootId;
  copy.emotes = comment.emotes.slice();
  copy.images = comment.images.slice();
  return copy;
}

/**
 * 把点赞结果写回一级列表（含各评论自带的预览回复）：翻转 isLiked 并增减
 * 点赞数（不降到负数）。展开楼中楼的写回用 applyLikeToReplies。
 */
export function applyLikeToComments(comments: SongComment[],
  commentId: string, liked: boolean): SongComment[] {
  const delta = liked ? 1 : -1;
  const applied = (comment: SongComment): SongComment => {
    if (comment.id !== commentId) {
      return comment;
    }
    const copy = cloneComment(comment);
    copy.isLiked = liked;
    copy.likeCount = Math.max(0, comment.likeCount + delta);
    return copy;
  };

  return comments.map((item: SongComment): SongComment => {
    if (item.id === commentId) {
      return applied(item);
    }
    if (item.previewReplies.some((reply: SongComment): boolean => reply.id === commentId)) {
      const copy = cloneComment(item);
      copy.previewReplies = item.previewReplies.map(applied);
      return copy;
    }
    return item;
  });
}

/** 把点赞结果写回一条楼中楼线程（展开的回复列表）。 */
export function applyLikeToReplies(replies: SongComment[],
  commentId: string, liked: boolean): SongComment[] {
  const delta = liked ? 1 : -1;
  return replies.map((reply: SongComment): SongComment => {
    if (reply.id !== commentId) {
      return reply;
    }
    const copy = cloneComment(reply);
    copy.isLiked = liked;
    copy.likeCount = Math.max(0, reply.likeCount + delta);
    return copy;
  });
}

/**
 * 富文本切段：按评论的 emotes 占位符把正文切成文本段与表情段，供 UI 的
 * Text + Span/ImageSpan 内联渲染。未命中任何占位符时输出单一文本段。
 */
export class CommentTextSegment {
  text: string;
  emoteUrl: string | null;

  constructor(text: string, emoteUrl: string | null) {
    this.text = text;
    this.emoteUrl = emoteUrl;
  }
}

export function buildCommentSegments(content: string, emotes: CommentEmote[]): CommentTextSegment[] {
  if (emotes.length === 0 || content.length === 0) {
    return [new CommentTextSegment(content, null)];
  }
  const placeholders = emotes.map((emote: CommentEmote): string => emote.placeholder);
  const segments: CommentTextSegment[] = [];
  let cursor = 0;
  let index = 0;
  while (index < content.length) {
    const hit = firstPlaceholderAt(content, placeholders, index);
    if (hit === null) {
      break;
    }
    if (hit.start > cursor) {
      segments.push(new CommentTextSegment(content.substring(cursor, hit.start), null));
    }
    segments.push(new CommentTextSegment(hit.placeholder, emotes[hit.emoteIndex].url));
    cursor = hit.start + hit.placeholder.length;
    index = cursor;
  }
  if (cursor < content.length) {
    segments.push(new CommentTextSegment(content.substring(cursor), null));
  }
  return segments.length > 0 ? segments : [new CommentTextSegment(content, null)];
}

function firstPlaceholderAt(content: string, placeholders: string[], from: number): PlaceholderHit | null {
  let best: PlaceholderHit | null = null;
  for (let i = 0; i < placeholders.length; i++) {
    const at = content.indexOf(placeholders[i], from);
    if (at >= 0 && (best === null || at < best.start)) {
      best = new PlaceholderHit(at, placeholders[i], i);
    }
  }
  return best;
}

class PlaceholderHit {
  start: number;
  placeholder: string;
  emoteIndex: number;

  constructor(start: number, placeholder: string, emoteIndex: number) {
    this.start = start;
    this.placeholder = placeholder;
    this.emoteIndex = emoteIndex;
  }
}

/**
 * 评论时间的相对展示：1 分钟内「刚刚」，24 小时内「N 分钟/小时前」，
 * 7 天内「N 天前」，更早回退完整日期。
 */
export function formatCommentTime(createTime: number | null, nowMs: number): string {
  if (createTime === null || createTime <= 0) {
    return '';
  }
  const diff = Math.max(0, nowMs - createTime);
  const minute = 60 * 1000;
  const hour = 60 * minute;
  const day = 24 * hour;
  if (diff < minute) {
    return '刚刚';
  }
  if (diff < hour) {
    return `${Math.floor(diff / minute)} 分钟前`;
  }
  if (diff < day) {
    return `${Math.floor(diff / hour)} 小时前`;
  }
  if (diff < 7 * day) {
    return `${Math.floor(diff / day)} 天前`;
  }
  const date = new Date(createTime);
  const month = `${date.getMonth() + 1}`.padStart(2, '0');
  const dayOfMonth = `${date.getDate()}`.padStart(2, '0');
  const hours = `${date.getHours()}`.padStart(2, '0');
  const minutes = `${date.getMinutes()}`.padStart(2, '0');
  return `${date.getFullYear()}-${month}-${dayOfMonth} ${hours}:${minutes}`;
}
