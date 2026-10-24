/**
 * 评论面板 UI 层的 JSON 编解码：@Prop 跨组件传类实例需走字符串载体
 * （项目惯例，同 QueueSheetContent 的 queueJson），编解码集中在这里。
 */
import { CommentPlatform, CommentError, CommentSource, CommentReplyTarget, CommentEmote, CommentQuote, CommentImage, SongComment } from '../../../model/CommentModels';
import { CommentReplyPanelState } from './CommentPanelController';

// ---------- SongComment ----------

interface CommentEmoteJson {
  placeholder: string;
  url: string;
}

interface CommentQuoteJson {
  username: string;
  content: string | null;
}

interface CommentImageJson {
  url: string;
  width: number;
  height: number;
}

interface SongCommentJson {
  id: string;
  userId: string | null;
  username: string;
  avatarUrl: string | null;
  content: string;
  likeCount: number;
  replyCount: number | null;
  createTime: number | null;
  platform: number;
  userLevel: number | null;
  isLiked: boolean;
  quotedComments: CommentQuoteJson[];
  previewReplies: SongCommentJson[];
  rootId: string | null;
  emotes: CommentEmoteJson[];
  images: CommentImageJson[];
}

export class SongCommentCodec {
  static toJson(comment: SongComment): string {
    return JSON.stringify(SongCommentCodec.toPlain(comment));
  }

  static fromJson(json: string): SongComment {
    return SongCommentCodec.fromPlain(JSON.parse(json) as SongCommentJson);
  }

  static toPlain(comment: SongComment): SongCommentJson {
    const plain: SongCommentJson = {
      id: comment.id,
      userId: comment.userId,
      username: comment.username,
      avatarUrl: comment.avatarUrl,
      content: comment.content,
      likeCount: comment.likeCount,
      replyCount: comment.replyCount,
      createTime: comment.createTime,
      platform: comment.platform,
      userLevel: comment.userLevel,
      isLiked: comment.isLiked,
      quotedComments: comment.quotedComments.map((quote: CommentQuote): CommentQuoteJson => {
        return { username: quote.username, content: quote.content };
      }),
      previewReplies: comment.previewReplies.map((reply: SongComment): SongCommentJson => SongCommentCodec.toPlain(reply)),
      rootId: comment.rootId,
      emotes: comment.emotes.map((emote: CommentEmote): CommentEmoteJson => {
        return { placeholder: emote.placeholder, url: emote.url };
      }),
      images: comment.images.map((image: CommentImage): CommentImageJson => {
        return { url: image.url, width: image.width, height: image.height };
      })
    };
    return plain;
  }

  static fromPlain(plain: SongCommentJson): SongComment {
    const comment = new SongComment(plain.id, plain.username, plain.content,
      plain.platform === CommentPlatform.BILIBILI ? CommentPlatform.BILIBILI : CommentPlatform.NETEASE);
    comment.userId = plain.userId;
    comment.avatarUrl = plain.avatarUrl;
    comment.likeCount = plain.likeCount;
    comment.replyCount = plain.replyCount;
    comment.createTime = plain.createTime;
    comment.userLevel = plain.userLevel;
    comment.isLiked = plain.isLiked;
    comment.quotedComments = plain.quotedComments.map((quote: CommentQuoteJson): CommentQuote => {
      return new CommentQuote(quote.username, quote.content);
    });
    comment.previewReplies = plain.previewReplies.map((reply: SongCommentJson): SongComment => SongCommentCodec.fromPlain(reply));
    comment.rootId = plain.rootId;
    comment.emotes = plain.emotes.map((emote: CommentEmoteJson): CommentEmote => {
      return new CommentEmote(emote.placeholder, emote.url);
    });
    comment.images = plain.images.map((image: CommentImageJson): CommentImage => {
      return new CommentImage(image.url, image.width, image.height);
    });
    return comment;
  }
}

// ---------- CommentSource ----------

interface CommentSourceJson {
  platform: number;
  resourceId: number;
  secondaryId: string | null;
  subResourceId: number | null;
  resourceTitle: string | null;
  hasExplicitResourceId: boolean;
}

export class CommentSourceCodec {
  static toJson(source: CommentSource | null): string {
    if (source === null) {
      return '';
    }
    const plain: CommentSourceJson = {
      platform: source.platform,
      resourceId: source.resourceId,
      secondaryId: source.secondaryId,
      subResourceId: source.subResourceId,
      resourceTitle: source.resourceTitle,
      hasExplicitResourceId: source.hasExplicitResourceId
    };
    return JSON.stringify(plain);
  }

  static fromJson(json: string): CommentSource | null {
    if (json.length === 0) {
      return null;
    }
    const plain = JSON.parse(json) as CommentSourceJson;
    return new CommentSource(
      plain.platform === CommentPlatform.BILIBILI ? CommentPlatform.BILIBILI : CommentPlatform.NETEASE,
      plain.resourceId,
      plain.secondaryId,
      plain.subResourceId,
      plain.resourceTitle,
      plain.hasExplicitResourceId
    );
  }
}

// ---------- CommentReplyTarget ----------

interface CommentReplyTargetJsonShape {
  commentId: string;
  rootId: string;
  username: string;
}

export class CommentReplyTargetJson {
  static from(target: CommentReplyTarget): string {
    const plain: CommentReplyTargetJsonShape = {
      commentId: target.commentId,
      rootId: target.rootId,
      username: target.username
    };
    return JSON.stringify(plain);
  }

  static parse(json: string): CommentReplyTarget | null {
    if (json.length === 0) {
      return null;
    }
    const plain = JSON.parse(json) as CommentReplyTargetJsonShape;
    return new CommentReplyTarget(plain.commentId, plain.rootId, plain.username);
  }

  static usernameOf(json: string): string {
    const target = CommentReplyTargetJson.parse(json);
    return target !== null ? target.username : '';
  }
}

// ---------- CommentReplyPanelState ----------

interface CommentReplyStateJson {
  expanded: boolean;
  comments: string[];
  page: number;
  hasMore: boolean;
  nextCursor: string | null;
  loading: boolean;
  error: number | null;
}

export class CommentReplyPanelStateCodec {
  static toJson(thread: CommentReplyPanelState): string {
    const plain: CommentReplyStateJson = {
      expanded: thread.expanded,
      comments: thread.comments.map((reply: SongComment): string => SongCommentCodec.toJson(reply)),
      page: thread.page,
      hasMore: thread.hasMore,
      nextCursor: thread.nextCursor,
      loading: thread.loading,
      error: thread.error === null ? null : commentErrorToNumber(thread.error)
    };
    return JSON.stringify(plain);
  }

  static fromJson(json: string): CommentReplyPanelState | null {
    if (json.length === 0) {
      return null;
    }
    const plain = JSON.parse(json) as CommentReplyStateJson;
    const thread = new CommentReplyPanelState();
    thread.expanded = plain.expanded;
    thread.comments = plain.comments.map((replyJson: string): SongComment => SongCommentCodec.fromJson(replyJson));
    thread.page = plain.page;
    thread.hasMore = plain.hasMore;
    thread.nextCursor = plain.nextCursor;
    thread.loading = plain.loading;
    thread.error = plain.error === null ? null : commentErrorFromNumber(plain.error);
    return thread;
  }
}

function commentErrorToNumber(error: CommentError): number {
  return error as number;
}

function commentErrorFromNumber(value: number): CommentError {
  if (value === CommentError.NETWORK) {
    return CommentError.NETWORK;
  }
  if (value === CommentError.PERMISSION) {
    return CommentError.PERMISSION;
  }
  if (value === CommentError.NOT_FOUND) {
    return CommentError.NOT_FOUND;
  }
  if (value === CommentError.CLOSED) {
    return CommentError.CLOSED;
  }
  if (value === CommentError.SERVER) {
    return CommentError.SERVER;
  }
  if (value === CommentError.API) {
    return CommentError.API;
  }
  return CommentError.UNKNOWN;
}
