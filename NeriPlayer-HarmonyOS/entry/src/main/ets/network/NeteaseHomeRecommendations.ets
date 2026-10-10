// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer),
// commits 6453ed7d (#319 expanded recommendations & radar playlists) and
// 59f1768e (#338 personalized metadata for radar playlists).

import { SongItem } from '../model/SongItem';
import { MusicPlatform } from '../model/MusicPlatform';
import { NeteasePlaylistSummary } from './NeteasePlaylistParser';

/** 雷达歌单静态定义（上游 NeteaseRadarPlaylistDefinitions）：元数据加载失败时的兜底。 */
export class NeteaseRadarPlaylistDefinition {
  readonly id: number;
  readonly name: string;

  constructor(id: number, name: string) {
    this.id = id;
    this.name = name;
  }
}

export const NETEASE_PRIVATE_RADAR_PLAYLIST_ID: number = 3136952023;
export const NETEASE_TOPLIST_SOARING_ID: number = 19723756;
export const NETEASE_TOPLIST_NEW_ID: number = 3779629;
export const NETEASE_TOPLIST_HOT_ID: number = 3778678;
export const NETEASE_FAN_RADAR_PLAYLIST_ID: number = 5327906368;

export const NETEASE_RADAR_PLAYLIST_DEFINITIONS: NeteaseRadarPlaylistDefinition[] = [
  new NeteaseRadarPlaylistDefinition(5320167908, '时光雷达'),
  new NeteaseRadarPlaylistDefinition(5362359247, '宝藏雷达'),
  new NeteaseRadarPlaylistDefinition(5300458264, '新歌雷达'),
  new NeteaseRadarPlaylistDefinition(NETEASE_FAN_RADAR_PLAYLIST_ID, '乐迷雷达'),
  new NeteaseRadarPlaylistDefinition(5341776086, '神秘雷达')
];

export function isNeteaseRadarPlaylist(playlistId: number): boolean {
  for (const definition of NETEASE_RADAR_PLAYLIST_DEFINITIONS) {
    if (definition.id === playlistId) {
      return true;
    }
  }
  return false;
}

export function radarDefinitionToSummary(definition: NeteaseRadarPlaylistDefinition):
  NeteasePlaylistSummary {
  const summary = new NeteasePlaylistSummary();
  summary.id = definition.id;
  summary.name = definition.name;
  return summary;
}

/** 首页歌曲来源（上游 NeteaseHomeSongSource）：登录门槛 + 展示名。 */
export enum NeteaseHomeSongSource {
  TOP_SOARING,
  PERSONAL_RADAR,
  DAILY_RECOMMEND,
  PRIVATE_FM,
  PERSONALIZED_NEW_SONGS,
  TOP_HOT,
  TOP_NEW
}

/** 首页歌单来源（上游 NeteaseHomePlaylistSource）。 */
export enum NeteaseHomePlaylistSource {
  PERSONALIZED,
  DAILY_RESOURCE,
  HIGH_QUALITY,
  HOT_PLAYLISTS,
  ACG_PLAYLISTS
}

export function songSourceTitle(source: NeteaseHomeSongSource): string {
  switch (source) {
    case NeteaseHomeSongSource.TOP_SOARING:
      return '飙升榜';
    case NeteaseHomeSongSource.PERSONAL_RADAR:
      return '私人雷达';
    case NeteaseHomeSongSource.DAILY_RECOMMEND:
      return '每日推荐';
    case NeteaseHomeSongSource.PRIVATE_FM:
      return '私人 FM';
    case NeteaseHomeSongSource.PERSONALIZED_NEW_SONGS:
      return '推荐新歌';
    case NeteaseHomeSongSource.TOP_HOT:
      return '热歌榜';
    case NeteaseHomeSongSource.TOP_NEW:
      return '新歌榜';
    default:
      return '推荐';
  }
}

export function songSourceRequiresLogin(source: NeteaseHomeSongSource): boolean {
  return source === NeteaseHomeSongSource.DAILY_RECOMMEND
    || source === NeteaseHomeSongSource.PRIVATE_FM;
}

export function playlistSourceTitle(source: NeteaseHomePlaylistSource): string {
  switch (source) {
    case NeteaseHomePlaylistSource.PERSONALIZED:
      return '为你推荐';
    case NeteaseHomePlaylistSource.DAILY_RESOURCE:
      return '每日推荐歌单';
    case NeteaseHomePlaylistSource.HIGH_QUALITY:
      return '精品歌单';
    case NeteaseHomePlaylistSource.HOT_PLAYLISTS:
      return '热门歌单';
    case NeteaseHomePlaylistSource.ACG_PLAYLISTS:
      return 'ACG 歌单';
    default:
      return '推荐';
  }
}

export function playlistSourceRequiresLogin(source: NeteaseHomePlaylistSource): boolean {
  return source === NeteaseHomePlaylistSource.DAILY_RESOURCE;
}

/** 按登录态过滤可用来源（上游 availableNeteaseHome*Sources）。 */
export function availableNeteaseHomeSongSources(candidates: NeteaseHomeSongSource[],
  hasLogin: boolean): NeteaseHomeSongSource[] {
  const out: NeteaseHomeSongSource[] = [];
  for (const candidate of candidates) {
    if (!songSourceRequiresLogin(candidate) || hasLogin) {
      out.push(candidate);
    }
  }
  return out;
}

export function availableNeteaseHomePlaylistSources(candidates: NeteaseHomePlaylistSource[],
  hasLogin: boolean): NeteaseHomePlaylistSource[] {
  const out: NeteaseHomePlaylistSource[] = [];
  for (const candidate of candidates) {
    if (!playlistSourceRequiresLogin(candidate) || hasLogin) {
      out.push(candidate);
    }
  }
  return out;
}

/** 响应体 code 非 200（上游 ApiCodeException）。 */
export class NeteaseApiCodeError extends Error {
  readonly code: number;

  constructor(code: number) {
    super(`api_code=${code}`);
    this.code = code;
  }
}

function readNumber(record: Record<string, Object>, key: string): number {
  const value = Number(record[key] ?? 0);
  return Number.isFinite(value) ? value : 0;
}

function readString(record: Record<string, Object>, key: string): string {
  const value = record[key];
  return value === undefined || value === null ? '' : String(value);
}

function toHttps(url: string): string {
  return url.replace('http://', 'https://');
}

function arrayField(record: Record<string, Object>, key: string): Object[] | null {
  const value = record[key];
  if (value instanceof Array) {
    return value as Object[];
  }
  return null;
}

function objectField(record: Record<string, Object>, key: string): Record<string, Object> | null {
  const value = record[key];
  if (value instanceof Object && !(value instanceof Array)) {
    return value as Record<string, Object>;
  }
  return null;
}

/** 各推荐响应的歌曲数组位置（上游 firstSongArray）。 */
function firstSongArray(root: Record<string, Object>): Object[] | null {
  const data = objectField(root, 'data');
  if (data !== null) {
    const dailySongs = arrayField(data, 'dailySongs');
    if (dailySongs !== null) {
      return dailySongs;
    }
    const songs = arrayField(data, 'songs');
    if (songs !== null) {
      return songs;
    }
    if (Array.isArray(root['data'])) {
      return root['data'] as Object[];
    }
  }
  const result = arrayField(root, 'result');
  if (result !== null) {
    return result;
  }
  const songs = arrayField(root, 'songs');
  if (songs !== null) {
    return songs;
  }
  const playlist = objectField(root, 'playlist');
  if (playlist !== null) {
    return arrayField(playlist, 'tracks');
  }
  return null;
}

/** 各推荐响应的歌单数组位置（上游 firstPlaylistArray）。 */
function firstPlaylistArray(root: Record<string, Object>): Object[] | null {
  const result = arrayField(root, 'result');
  if (result !== null) {
    return result;
  }
  const recommend = arrayField(root, 'recommend');
  if (recommend !== null) {
    return recommend;
  }
  const playlists = arrayField(root, 'playlists');
  if (playlists !== null) {
    return playlists;
  }
  const data = objectField(root, 'data');
  if (data !== null) {
    const dataPlaylists = arrayField(data, 'playlists');
    if (dataPlaylists !== null) {
      return dataPlaylists;
    }
    const list = arrayField(data, 'list');
    if (list !== null) {
      return list;
    }
  }
  return null;
}

function parseHomeSong(container: Record<string, Object>): SongItem | null {
  // /personalized/newsong 等响应把曲目包在 song 字段里（上游先解包再取字段）。
  const song = objectField(container, 'song') ?? container;
  const songId = readNumber(song, 'id');
  const name = readString(song, 'name');
  if (songId <= 0 || name.trim().length === 0) {
    return null;
  }
  const artistNames: string[] = [];
  const ar = arrayField(song, 'ar');
  const sourceArtists = ar !== null ? ar : arrayField(song, 'artists');
  if (sourceArtists !== null) {
    for (const entry of sourceArtists) {
      if (entry instanceof Object) {
        const artist = entry as Record<string, Object>;
        const artistName = readString(artist, 'name');
        if (artistName.length > 0) {
          artistNames.push(artistName);
        }
      }
    }
  }
  const album = objectField(song, 'al') ?? objectField(song, 'album');
  const songItem = new SongItem(songId, name,
    artistNames.join(' / '), album !== null ? readString(album, 'name') : '',
    album !== null ? readNumber(album, 'id') : 0,
    readNumber(song, 'dt') > 0 ? readNumber(song, 'dt') : readNumber(song, 'duration'),
    album !== null ? toHttps(readString(album, 'picUrl')) : '',
    '', MusicPlatform.NETEASE);
  songItem.audioId = `${songItem.id}`;
  return songItem;
}

function parseHomePlaylist(record: Record<string, Object>): NeteasePlaylistSummary | null {
  const id = readNumber(record, 'id');
  const name = readString(record, 'name');
  if (id <= 0 || name.trim().length === 0) {
    return null;
  }
  const summary = new NeteasePlaylistSummary();
  summary.id = id;
  summary.name = name;
  let cover = readString(record, 'picUrl');
  if (cover.length === 0) {
    cover = readString(record, 'coverImgUrl');
  }
  if (cover.length === 0) {
    cover = readString(record, 'coverUrl');
  }
  summary.coverUrl = toHttps(cover);
  summary.playCount = readNumber(record, 'playCount') > 0
    ? readNumber(record, 'playCount') : readNumber(record, 'playcount');
  summary.trackCount = readNumber(record, 'trackCount') > 0
    ? readNumber(record, 'trackCount') : readNumber(record, 'songCount');
  return summary;
}

/** 解析各推荐接口的歌曲响应（code!=200 抛 NeteaseApiCodeError）。 */
export function parseNeteaseHomeSongs(raw: string, limit: number = Number.MAX_SAFE_INTEGER):
  SongItem[] {
  const root = JSON.parse(raw) as Record<string, Object>;
  const code = readNumber(root, 'code');
  if (code !== 200) {
    throw new NeteaseApiCodeError(code);
  }
  const songs = firstSongArray(root);
  const out: SongItem[] = [];
  if (songs === null) {
    return out;
  }
  for (const entry of songs) {
    if (out.length >= limit) {
      break;
    }
    if (!(entry instanceof Object)) {
      continue;
    }
    const container = entry as Record<string, Object>;
    const song = parseHomeSong(container);
    if (song !== null) {
      out.push(song);
    }
  }
  return out;
}

/** 解析各推荐接口的歌单响应。 */
export function parseNeteaseHomePlaylists(raw: string,
  limit: number = Number.MAX_SAFE_INTEGER): NeteasePlaylistSummary[] {
  const root = JSON.parse(raw) as Record<string, Object>;
  const code = readNumber(root, 'code');
  if (code !== 200) {
    throw new NeteaseApiCodeError(code);
  }
  const playlists = firstPlaylistArray(root);
  const out: NeteasePlaylistSummary[] = [];
  if (playlists === null) {
    return out;
  }
  for (const entry of playlists) {
    if (out.length >= limit) {
      break;
    }
    if (!(entry instanceof Object)) {
      continue;
    }
    const summary = parseHomePlaylist(entry as Record<string, Object>);
    if (summary !== null) {
      out.push(summary);
    }
  }
  return out;
}

/** 歌单详情响应取摘要（playlist|result），缺歌单对象时返回 null。 */
export function parseNeteasePlaylistDetailSummaryOrNull(raw: string): NeteasePlaylistSummary | null {
  const root = JSON.parse(raw) as Record<string, Object>;
  const code = root['code'] === undefined ? 200 : readNumber(root, 'code');
  if (code !== 200) {
    throw new NeteaseApiCodeError(code);
  }
  const playlist = objectField(root, 'playlist') ?? objectField(root, 'result');
  return playlist === null ? null : parseHomePlaylist(playlist);
}

/** 歌单详情取摘要，失败/缺对象回落静态定义（上游 parseNeteasePlaylistDetailSummary）。 */
export function parseNeteasePlaylistDetailSummary(raw: string,
  fallback: NeteasePlaylistSummary): NeteasePlaylistSummary {
  const parsed = parseNeteasePlaylistDetailSummaryOrNull(raw);
  return parsed === null ? fallback : parsed;
}

/**
 * 合并去重（上游 appendUniqueNeteaseHomeSongs）：以 audioId（缺失时
 * platform:id:name）为键，追加 next 中未见过的歌，总量封顶 limit。
 */
export function appendUniqueNeteaseHomeSongs(current: SongItem[], next: SongItem[],
  limit: number): SongItem[] {
  if (limit <= 0) {
    return [];
  }
  const seen = new Set<string>();
  const out: SongItem[] = [];
  for (const song of current) {
    if (out.length >= limit) {
      return out;
    }
    const key = song.audioId.length > 0 ? song.audioId
      : `${song.platform}:${song.id}:${song.name}`;
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    out.push(song);
  }
  for (const song of next) {
    if (out.length >= limit) {
      break;
    }
    const key = song.audioId.length > 0 ? song.audioId
      : `${song.platform}:${song.id}:${song.name}`;
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    out.push(song);
  }
  return out;
}
