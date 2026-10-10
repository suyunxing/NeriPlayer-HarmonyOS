// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer),
// commits a8440275 (bili link pages/collection shares) and 1dbb2964 (season_id).

/** 识别出的链接种类（上游 sealed ExploreLinkTarget 的判别式展开）。 */
export enum ExploreLinkKind {
  NETEASE_SONG,
  NETEASE_PLAYLIST,
  NETEASE_ARTIST,
  NETEASE_SHORT_LINK,
  BILI_VIDEO,
  BILI_FAV_FOLDER,
  BILI_FAV_FOLDER_BY_OWNER,
  BILI_COLLECTION,
  BILI_ARTIST,
  BILI_SHORT_LINK,
  YOUTUBE_VIDEO,
  YOUTUBE_PLAYLIST,
  UNSUPPORTED
}

/** 识别结果：按 kind 取对应字段（未用字段保持默认值）。 */
export class ExploreLinkTarget {
  kind: ExploreLinkKind = ExploreLinkKind.UNSUPPORTED;
  /** 网易歌曲/歌单/艺人 id、收藏夹 mediaId、UP 主 mid。 */
  id: number = 0;
  /** 短链原样 URL（网易 163cn.tv / B 站 b23.tv）。 */
  url: string = '';
  bvid: string = '';
  avid: number = 0;
  /** 分 P 页码 / 指定 cid；0 = 未指定。 */
  page: number = 0;
  cid: number = 0;
  /** 合集分享链接（video 页面带 season 参数的分享形态）。 */
  isCollectionShare: boolean = false;
  ownerMid: number = 0;
  seasonId: number = 0;
  folderId: number = 0;
  videoId: string = '';
  playlistId: string = '';
  /** UNSUPPORTED 的说明（平台/类型）。 */
  note: string = '';

  constructor(kind: ExploreLinkKind) {
    this.kind = kind;
  }
}

const HTTP_URL_REGEX: RegExp = /https?:\/\/[^\s]+/i;
const BILI_BVID_REGEX: RegExp = /BV[0-9A-Za-z]{10}/;
const BILI_AVID_REGEX: RegExp = /(?:\/video\/av|[?&]aid=)(\d+)/;
const BILI_MEDIA_LIST_REGEX: RegExp = /\/medialist\/(?:detail|play)\/(?:ml)?(\d+)/i;

class ParsedUrl {
  host: string = '';
  path: string = '';
  rawQuery: string = '';
  rawFragment: string = '';
}

function urlDecode(value: string): string {
  try {
    return decodeURIComponent(value);
  } catch (error) {
    return value;
  }
}

function queryParameters(rawQuery: string): Map<string, string> {
  const out = new Map<string, string>();
  if (rawQuery.length === 0) {
    return out;
  }
  for (const part of rawQuery.split('&')) {
    const eq = part.indexOf('=');
    const key = urlDecode(eq >= 0 ? part.substring(0, eq) : part);
    const value = eq >= 0 ? urlDecode(part.substring(eq + 1)) : '';
    if (key.length > 0) {
      out.set(key, value);
    }
  }
  return out;
}

function parseUrl(raw: string): ParsedUrl | null {
  const candidate = raw.includes('://') ? raw : `https://${raw}`;
  const schemeIdx = candidate.indexOf('://');
  if (schemeIdx <= 0) {
    return null;
  }
  const parsed = new ParsedUrl();
  let rest = candidate.substring(schemeIdx + 3);
  const hashIdx = rest.indexOf('#');
  if (hashIdx >= 0) {
    parsed.rawFragment = rest.substring(hashIdx + 1);
    rest = rest.substring(0, hashIdx);
  }
  const queryIdx = rest.indexOf('?');
  if (queryIdx >= 0) {
    parsed.rawQuery = rest.substring(queryIdx + 1);
    rest = rest.substring(0, queryIdx);
  }
  const slashIdx = rest.indexOf('/');
  const authority = slashIdx >= 0 ? rest.substring(0, slashIdx) : rest;
  parsed.path = slashIdx >= 0 ? rest.substring(slashIdx) : '';
  const portIdx = authority.indexOf(':');
  parsed.host = (portIdx >= 0 ? authority.substring(0, portIdx) : authority).toLowerCase();
  if (parsed.host.length === 0) {
    return null;
  }
  return parsed;
}

function pathSegments(path: string): string[] {
  const out: string[] = [];
  for (const segment of path.split('/')) {
    if (segment.trim().length > 0) {
      out.push(segment);
    }
  }
  return out;
}

/** 从任意文本中抠出第一个 http(s) URL，去掉中文句读尾缀（上游同规则）。 */
export function extractExploreHttpUrl(input: string): string | null {
  const trimmed = input.trim();
  if (trimmed.length === 0) {
    return null;
  }
  const match = HTTP_URL_REGEX.exec(trimmed);
  if (match !== null) {
    const cleaned = match[0]
      .replace(/[。，,.)）\]】}》>]+$/, '');
    return cleaned.length > 0 ? cleaned : null;
  }
  return trimmed.startsWith('http://') || trimmed.startsWith('https://') ? trimmed : null;
}

function positive(value: number): number {
  return Number.isFinite(value) && value > 0 ? Math.floor(value) : 0;
}

function parsePositiveParam(params: Map<string, string>, key: string): number {
  return positive(Number(params.get(key) ?? 0));
}

/** B 站合集分享判定：season_id/ep_id/outer_id 之一（上游 params.isBiliCollectionShare）。 */
function isBiliCollectionShare(params: Map<string, string>): boolean {
  return params.has('season_id') || params.has('ep_id') || params.has('outer_id');
}

function recognizeNeteaseLink(uri: ParsedUrl): ExploreLinkTarget | null {
  // 网易分享链接大量使用 #/song?id= 形态：路径 = 路径 + fragment 路径拼接，
  // 查询 = 查询串 + fragment 查询串合并。
  const fragmentPath = uri.rawFragment.split('?')[0];
  const targetPath = `${uri.path}/${fragmentPath}`.toLowerCase();
  const fragmentQuery = uri.rawFragment.includes('?')
    ? uri.rawFragment.substring(uri.rawFragment.indexOf('?') + 1) : '';
  const merged = new Map<string, string>(queryParameters(uri.rawQuery));
  for (const entry of queryParameters(fragmentQuery)) {
    merged.set(entry[0], entry[1]);
  }
  const id = parsePositiveParam(merged, 'id');
  if (id <= 0) {
    return null;
  }
  if (targetPath.includes('/song')) {
    const target = new ExploreLinkTarget(ExploreLinkKind.NETEASE_SONG);
    target.id = id;
    return target;
  }
  if (targetPath.includes('/playlist')) {
    const target = new ExploreLinkTarget(ExploreLinkKind.NETEASE_PLAYLIST);
    target.id = id;
    return target;
  }
  if (targetPath.includes('/artist')) {
    const target = new ExploreLinkTarget(ExploreLinkKind.NETEASE_ARTIST);
    target.id = id;
    return target;
  }
  return null;
}

function recognizeBiliCollectionLink(uri: ParsedUrl): ExploreLinkTarget | null {
  if (uri.host !== 'space.bilibili.com') {
    return null;
  }
  const segments = pathSegments(uri.path);
  const ownerMid = positive(Number(segments.length > 0 ? segments[0] : 0));
  if (ownerMid <= 0 || segments.length < 3) {
    return null;
  }
  if (segments[1] !== 'lists') {
    return null;
  }
  const seasonId = positive(Number(segments[2]));
  if (seasonId <= 0) {
    return null;
  }
  const listType = (queryParameters(uri.rawQuery).get('type') ?? '').toLowerCase();
  if (listType === 'series') {
    const target = new ExploreLinkTarget(ExploreLinkKind.UNSUPPORTED);
    target.note = 'Bilibili 系列（series）暂不支持，请使用合集链接';
    return target;
  }
  const target = new ExploreLinkTarget(ExploreLinkKind.BILI_COLLECTION);
  target.ownerMid = ownerMid;
  target.seasonId = seasonId;
  return target;
}

function recognizeBiliFavoriteFolderLink(uri: ParsedUrl): ExploreLinkTarget | null {
  const medialist = BILI_MEDIA_LIST_REGEX.exec(uri.path);
  const mediaId = positive(Number(medialist !== null ? medialist[1] : 0));
  if (mediaId > 0) {
    const target = new ExploreLinkTarget(ExploreLinkKind.BILI_FAV_FOLDER);
    target.id = mediaId;
    return target;
  }
  if (uri.host !== 'space.bilibili.com') {
    return null;
  }
  const segments = pathSegments(uri.path);
  const ownerMid = positive(Number(segments.length > 0 ? segments[0] : 0));
  if (ownerMid <= 0 || segments.length < 2 || segments[1] !== 'favlist') {
    return null;
  }
  const rawFid = queryParameters(uri.rawQuery).get('fid') ?? '';
  const folderId = positive(Number(rawFid.startsWith('ml') ? rawFid.substring(2) : rawFid));
  if (folderId <= 0) {
    return null;
  }
  const target = new ExploreLinkTarget(ExploreLinkKind.BILI_FAV_FOLDER_BY_OWNER);
  target.ownerMid = ownerMid;
  target.folderId = folderId;
  return target;
}

function recognizeBiliArtistLink(uri: ParsedUrl): ExploreLinkTarget | null {
  const segments = pathSegments(uri.path);
  let artistId = 0;
  if (uri.host === 'space.bilibili.com') {
    artistId = positive(Number(segments.length > 0 ? segments[0] : 0));
  } else if (segments.length > 0 && segments[0] === 'space' && segments.length > 1) {
    artistId = positive(Number(segments[1]));
  }
  if (artistId <= 0) {
    return null;
  }
  const target = new ExploreLinkTarget(ExploreLinkKind.BILI_ARTIST);
  target.id = artistId;
  return target;
}

function recognizeBiliLink(uri: ParsedUrl, raw: string): ExploreLinkTarget | null {
  const params = queryParameters(uri.rawQuery);
  const page = parsePositiveParam(params, 'p');
  const cid = parsePositiveParam(params, 'cid');
  const isCollectionShare = isBiliCollectionShare(params);
  const bvidMatch = BILI_BVID_REGEX.exec(raw);
  if (bvidMatch !== null) {
    const target = new ExploreLinkTarget(ExploreLinkKind.BILI_VIDEO);
    target.bvid = bvidMatch[0];
    target.page = page;
    target.cid = cid;
    target.isCollectionShare = isCollectionShare;
    return target;
  }
  const aidParam = parsePositiveParam(params, 'aid');
  let avid = aidParam;
  if (avid <= 0) {
    const avidMatch = BILI_AVID_REGEX.exec(raw);
    avid = positive(Number(avidMatch !== null ? avidMatch[1] : 0));
  }
  if (avid > 0) {
    const target = new ExploreLinkTarget(ExploreLinkKind.BILI_VIDEO);
    target.avid = avid;
    target.page = page;
    target.cid = cid;
    target.isCollectionShare = isCollectionShare;
    return target;
  }
  if (uri.host === 'b23.tv') {
    const target = new ExploreLinkTarget(ExploreLinkKind.BILI_SHORT_LINK);
    target.url = raw;
    return target;
  }
  return recognizeBiliCollectionLink(uri)
    ?? recognizeBiliFavoriteFolderLink(uri)
    ?? recognizeBiliArtistLink(uri);
}

function recognizeYouTubeLink(uri: ParsedUrl): ExploreLinkTarget | null {
  const path = uri.path.replace(/^\/+/, '');
  const params = queryParameters(uri.rawQuery);
  const playlistId = params.get('list') ?? '';
  let videoId = '';
  if (uri.host === 'youtu.be') {
    videoId = path.split('/')[0];
  } else if (path === 'embed' || path.startsWith('embed/')) {
    videoId = path.substring('embed/'.length);
  } else if (path === 'shorts' || path.startsWith('shorts/')) {
    videoId = path.substring('shorts/'.length);
  } else if (path === 'live' || path.startsWith('live/')) {
    videoId = path.substring('live/'.length);
  } else {
    videoId = params.get('v') ?? '';
  }

  if (videoId.length > 0) {
    const target = new ExploreLinkTarget(ExploreLinkKind.YOUTUBE_VIDEO);
    target.videoId = videoId;
    target.playlistId = playlistId;
    return target;
  }
  if (playlistId.length > 0) {
    const target = new ExploreLinkTarget(ExploreLinkKind.YOUTUBE_PLAYLIST);
    target.playlistId = playlistId;
    return target;
  }
  if (path.startsWith('channel/') || path.startsWith('@')
    || path.startsWith('c/') || path.startsWith('browse/')) {
    const target = new ExploreLinkTarget(ExploreLinkKind.UNSUPPORTED);
    target.note = 'YouTube 频道/艺人页暂不支持';
    return target;
  }
  return null;
}

/** 识别剪贴板/输入框里的分享链接；null = 不是可识别的链接（按关键词搜索）。 */
export function recognizeExploreLink(input: string): ExploreLinkTarget | null {
  const normalized = extractExploreHttpUrl(input);
  if (normalized === null) {
    return null;
  }
  const uri = parseUrl(normalized);
  if (uri === null) {
    return null;
  }
  const host = uri.host;
  if (host.endsWith('music.163.com')) {
    return recognizeNeteaseLink(uri);
  }
  if (host === '163cn.tv') {
    const target = new ExploreLinkTarget(ExploreLinkKind.NETEASE_SHORT_LINK);
    target.url = normalized;
    return target;
  }
  if (host.endsWith('bilibili.com') || host === 'b23.tv') {
    return recognizeBiliLink(uri, normalized);
  }
  if (host === 'youtu.be' || host.endsWith('youtube.com') || host.endsWith('youtube-nocookie.com')) {
    return recognizeYouTubeLink(uri);
  }
  return null;
}
