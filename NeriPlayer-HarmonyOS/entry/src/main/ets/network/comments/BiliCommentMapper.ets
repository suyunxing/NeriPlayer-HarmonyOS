/**
 * B 站评论 JSON（x/v2/reply 根对象）-> 统一评论模型（上游
 * platform/comments/mapper/BiliCommentMapper.kt 直译，含 #487/2c68dbbb 的
 * 到底误报修复：空页但总数未读完按 API 错误抛出，而不是当作已加载完）。
 */
import { CommentPage, CommentPlatform, CommentError, CommentEmote, CommentImage, SongComment } from '../../model/CommentModels';
import { CommentApiException } from './CommentRepositoryCore';

/** B 站评论区「评论已关闭」业务码。 */
const BILI_CODE_REPLY_CLOSED: number = 12061;

interface BiliMemberJson {
  mid?: string;
  uname?: string;
  avatar?: string;
  level_info?: BiliLevelInfoJson;
}

interface BiliLevelInfoJson {
  current_level?: number;
}

interface BiliEmoteJson {
  id?: number;
  size?: number;
  url?: string;
}

interface BiliPictureJson {
  img_src?: string;
  img_width?: number;
  img_height?: number;
}

interface BiliContentJson {
  message?: string;
  emote?: Record<string, BiliEmoteJson>;
  pictures?: BiliPictureJson[];
}

interface BiliReplyJson {
  rpid?: number;
  parent?: number;
  root?: number;
  ctime?: number;
  like?: number;
  action?: number;
  rcount?: number;
  count?: number;
  member?: BiliMemberJson;
  content?: BiliContentJson;
  replies?: BiliReplyJson[];
}

interface BiliReplyPageJson {
  num?: number;
  size?: number;
  count?: number;
  acount?: number;
}

interface BiliReplyDataJson {
  page?: BiliReplyPageJson;
  replies?: BiliReplyJson[];
}

interface BiliReplyResponseJson {
  code?: number;
  message?: string;
  data?: BiliReplyDataJson;
}

/**
 * B 站业务错误码 -> 统一错误分类。
 */
export function biliCommentError(code: number): CommentError {
  if (code === -101 || code === -102 || code === -111 || code === -403 || code === -412 || code === 12004) {
    return CommentError.PERMISSION;
  }
  if (code === -404 || code === 12006) {
    return CommentError.NOT_FOUND;
  }
  if (code === BILI_CODE_REPLY_CLOSED || code === 12002) {
    return CommentError.CLOSED;
  }
  if (code >= 500 && code <= 599) {
    return CommentError.SERVER;
  }
  return CommentError.API;
}

/**
 * B 站评论根对象 -> 评论页。
 *
 * 分页防御（上游 #487）：匿名访问可能返回全零分页信息（page.num/size 异常）按
 * API 错误抛出；返回空页但按总数还有剩余同样抛出——两者都不能当作「已读完」，
 * 否则 UI 会误报接口不可用或漏掉后续页。hasMore 按实际返回条数推算。
 */
export function parseBiliCommentPage(rawJson: string, page: number, pageSize: number,
  includeReplyTotal: boolean = false): CommentPage {
  const root = JSON.parse(rawJson) as BiliReplyResponseJson;
  const code = root.code ?? -1;
  if (code !== 0) {
    throw new CommentApiException(code, biliCommentError(code), `Bili comment API failed: code=${code}`);
  }

  const data = root.data ?? {};
  const pageObject = data.page;
  // 匿名受限响应的分页信息是全零，不能把截断当作评论已读完。
  if (pageObject === undefined || pageObject.num === undefined ||
    pageObject.num !== page || (pageObject.size ?? 0) <= 0) {
    throw new CommentApiException(0, CommentError.API,
      `Bili comment API returned invalid pagination: requested page=${page}`);
  }
  const rawTotal = pageObject.count ?? -1;
  const total = rawTotal >= 0 ? rawTotal : null;

  const comments: SongComment[] = [];
  for (const item of data.replies ?? []) {
    comments.push(parseBiliComment(item, true));
  }

  const loadedThrough = (page - 1) * pageSize + comments.length;
  if (comments.length === 0 && total !== null && loadedThrough < total) {
    throw new CommentApiException(0, CommentError.API,
      `Bili comment API returned an incomplete empty page: page=${page}`);
  }
  // 按实际返回条数判断，避免总数不足一页时把匿名截断误当作结束。
  const hasMore = total !== null ? loadedThrough < total : comments.length >= pageSize;

  let totalIncludingReplies: number | null = null;
  if (includeReplyTotal) {
    const acount = pageObject.acount ?? -1;
    if (acount >= (total ?? 0)) {
      totalIncludingReplies = acount;
    }
  }

  return new CommentPage(comments, page, pageSize, total, hasMore, null, totalIncludingReplies);
}

/**
 * 单条 B 站评论映射：member/content 子对象取昵称、正文与等级，
 * ctime 秒级换算毫秒，回复数 rcount 缺失回退 count。
 */
function parseBiliComment(item: BiliReplyJson, includePreview: boolean): SongComment {
  const member = item.member ?? {};
  const content = item.content ?? {};
  const rawCtime = item.ctime ?? 0;
  const createTime = rawCtime > 0 ? rawCtime * 1000 : null;

  const comment = new SongComment(
    `${item.rpid ?? 0}`,
    member.uname ?? '',
    content.message ?? '',
    CommentPlatform.BILIBILI
  );
  const mid = member.mid ?? '';
  comment.userId = mid.length > 0 ? mid : null;
  comment.avatarUrl = normalizeBiliAvatarUrl(member.avatar ?? '');
  // rcount 为楼中楼数量，缺失时回退 count（含子评论的回复数）。
  const rcount = item.rcount ?? -1;
  const fallbackCount = item.count ?? -1;
  comment.replyCount = rcount >= 0 ? rcount : (fallbackCount >= 0 ? fallbackCount : null);
  comment.createTime = createTime;
  const level = member.level_info?.current_level ?? 0;
  comment.userLevel = level > 0 ? level : null;
  comment.isLiked = item.action === 1;

  if (includePreview) {
    for (const reply of item.replies ?? []) {
      comment.previewReplies.push(parseBiliComment(reply, false));
    }
  }

  const root = item.root ?? 0;
  comment.rootId = root > 0 ? `${root}` : null;
  comment.emotes = parseBiliEmotes(content);
  comment.images = parseBiliImages(content);
  return comment;
}

/**
 * B 站评论内联表情（content.emote）。JSON key 就是正文里出现的标记文本；
 * 地址为空或非对象的条目直接丢弃，不做占位。
 */
function parseBiliEmotes(content: BiliContentJson): CommentEmote[] {
  const emoteObject = content.emote;
  if (emoteObject === undefined) {
    return [];
  }
  const result: CommentEmote[] = [];
  const keys = Object.keys(emoteObject);
  for (const placeholder of keys) {
    const url = ensureBiliMediaScheme(emoteObject[placeholder]?.url ?? '');
    if (url !== null) {
      result.push(new CommentEmote(placeholder, url));
    }
  }
  return result;
}

/**
 * B 站评论配图（content.pictures）。宽高缺失时取 0，地址为空的条目丢弃。
 */
function parseBiliImages(content: BiliContentJson): CommentImage[] {
  const result: CommentImage[] = [];
  for (const picture of content.pictures ?? []) {
    const url = ensureBiliMediaScheme(picture.img_src ?? '');
    if (url === null) {
      continue;
    }
    result.push(new CommentImage(url, picture.img_width ?? 0, picture.img_height ?? 0));
  }
  return result;
}

/** B 站媒体地址协议归一化：`//` 开头补 `https:`，空值返回 null。 */
function ensureBiliMediaScheme(raw: string): string | null {
  const trimmed = raw.trim();
  if (trimmed.length === 0) {
    return null;
  }
  return trimmed.startsWith('//') ? `https:${trimmed}` : trimmed;
}

/**
 * B 站头像地址归一化：补协议头后追加 48x48 缩放参数（评论行内小头像，
 * 原图通常 200+ px，缩小请求省流量；已带 @ 参数或查询串的地址原样使用）。
 */
function normalizeBiliAvatarUrl(raw: string): string | null {
  const withScheme = ensureBiliMediaScheme(raw);
  if (withScheme === null) {
    return null;
  }
  if (withScheme.indexOf('@') >= 0 || withScheme.indexOf('?') >= 0) {
    return withScheme;
  }
  return `${withScheme}@48w_48h_1c.webp`;
}
