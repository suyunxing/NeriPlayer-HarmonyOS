/**
 * 根据歌曲的「逻辑音源」解析评论来源（上游 platform/comments/CommentSourceResolver.kt
 * 直译，#476）。关键规则：平台只由 SongItem 的原始平台信息决定——显式 channelId
 * 优先，其次才是 album 的来源标记；绝不由最终播放地址（mediaUri/streamUrl）或
 * 播放回退结果推断。网易云歌曲即使音频回退到 B 站，仍返回网易云评论来源。
 */
import { CommentPlatform, CommentSource } from '../../model/CommentModels';
import { SongItem } from '../../model/SongItem';
import { Constants } from '../../app/Constants';

const BILIBILI_CHANNEL_ID: string = 'bilibili';
const NETEASE_CHANNEL_ID: string = 'netease';

function startsWithIgnoreCase(value: string, prefix: string): boolean {
  if (value.length < prefix.length) {
    return false;
  }
  return value.substring(0, prefix.length).toLowerCase() === prefix.toLowerCase();
}

/**
 * 解析歌曲的评论来源；平台不支持评论（本地歌曲 / YouTube Music / 未知来源，
 * 或网易云缺资源 id）时返回 null。
 */
export function resolveCommentSource(song: SongItem | null): CommentSource | null {
  if (song === null) {
    return null;
  }

  const channelId = song.channelId.trim().toLowerCase();
  let platform: CommentPlatform | null = null;
  if (channelId === BILIBILI_CHANNEL_ID) {
    platform = CommentPlatform.BILIBILI;
  } else if (channelId === NETEASE_CHANNEL_ID) {
    platform = CommentPlatform.NETEASE;
  } else if (startsWithIgnoreCase(song.album, Constants.BILIBILI_IDENTITY_HINT)) {
    platform = CommentPlatform.BILIBILI;
  } else if (startsWithIgnoreCase(song.album, Constants.NETEASE_IDENTITY_HINT)) {
    platform = CommentPlatform.NETEASE;
  }
  if (platform === null) {
    return null;
  }

  const isBili = platform === CommentPlatform.BILIBILI;
  const explicitResourceId = Number(song.audioId.trim());
  if (isBili) {
    // 鸿蒙侧 B 站歌曲 audioId 是 bvid（非数字）：资源定位交由仓库层按 bvid
    // 解析 avid；历史上游的打包数字 id 形态保留兼容（hasExplicitResourceId）。
    const bvid = Number.isFinite(explicitResourceId) && explicitResourceId > 0 ? '' : song.audioId.trim();
    const cid = Number(song.subAudioId.trim());
    return new CommentSource(
      CommentPlatform.BILIBILI,
      Number.isFinite(explicitResourceId) && explicitResourceId > 0 ? explicitResourceId : 0,
      bvid.length > 0 ? bvid : null,
      Number.isFinite(cid) && cid > 0 ? cid : null,
      bvid.length === 0 && !(Number.isFinite(cid) && cid > 0) ? song.name : null,
      Number.isFinite(explicitResourceId) && explicitResourceId > 0
    );
  }

  const resourceId = Number.isFinite(explicitResourceId) && explicitResourceId > 0
    ? explicitResourceId : song.id;
  if (!(resourceId > 0)) {
    return null;
  }
  return new CommentSource(CommentPlatform.NETEASE, resourceId);
}
