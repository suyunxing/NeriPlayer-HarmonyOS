// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

import { SongItem } from '../model/SongItem';
import { MusicPlatform } from '../model/MusicPlatform';

/**
 * Pure parsers for the NetEase playlist/account responses, ported from
 * Android NeteaseClient.getUserPlaylists / HomeViewModel.parseRecommend /
 * getCurrentUserId. Zero platform deps so they stay unit-testable.
 *
 * Contracts (field names verified against the Android parsers):
 * - /weapi/user/playlist  -> { code, playlist: [{ id, name, coverImgUrl, playCount, trackCount }] }
 * - /weapi/personalized/playlist -> { code, result: [{ id, name, picUrl, playCount, trackCount }] }
 * - /weapi/w/nuser/account/get -> { code, profile: { userId } }
 */

export class NeteasePlaylistSummary {
  id: number = 0;
  name: string = '';
  coverUrl: string = '';
  playCount: number = 0;
  trackCount: number = 0;
  /** 创建者 uid（user/playlist 响应的 creator.userId，0 = 未携带）；写回
   * 选择器用它过滤出自建歌单（上游 #322 parseNeteaseRemotePlaylists 的
   * ownerUserId 过滤）。 */
  creatorUserId: number = 0;
}

/** Parse outcome: non-200 codes are surfaced so callers can apply fallbacks. */
export class ParsedNeteasePlaylists {
  code: number = -1;
  items: NeteasePlaylistSummary[] = [];
}

function toHttps(url: string): string {
  return url.replace('http://', 'https://');
}

function readNumber(record: Record<string, Object>, key: string): number {
  const value = record[key];
  if (value === undefined || value === null) {
    return 0;
  }
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function readString(record: Record<string, Object>, key: string): string {
  const value = record[key];
  if (value === undefined || value === null) {
    return '';
  }
  return String(value);
}

/** Parses /weapi/user/playlist responses (library tab, "my playlists"). */
export function parseUserPlaylistsResponse(raw: string): ParsedNeteasePlaylists {
  const out = new ParsedNeteasePlaylists();
  let root: Record<string, Object>;
  try {
    root = JSON.parse(raw) as Record<string, Object>;
  } catch (error) {
    return out;
  }
  out.code = readNumber(root, 'code');
  const rawArr = root['playlist'];
  if (!(rawArr instanceof Array)) {
    return out;
  }
  const arr: Object[] = rawArr as Object[];
  for (const entry of arr) {
    if (!(entry instanceof Object)) {
      continue;
    }
    const record = entry as Record<string, Object>;
    const summary = new NeteasePlaylistSummary();
    summary.id = readNumber(record, 'id');
    summary.name = readString(record, 'name');
    summary.coverUrl = toHttps(readString(record, 'coverImgUrl'));
    summary.playCount = readNumber(record, 'playCount');
    summary.trackCount = readNumber(record, 'trackCount');
    const creator = record['creator'];
    if (creator instanceof Object) {
      summary.creatorUserId = readNumber(creator as Record<string, Object>, 'userId');
    }
    if (summary.id !== 0 && summary.name.trim().length > 0) {
      out.items.push(summary);
    }
  }
  return out;
}

/**
 * Parses /weapi/personalized/playlist responses (home recommendations).
 * Keeps at most `cap` entries and requires a non-empty cover, matching the
 * Android parseRecommend filters.
 */
export function parseRecommendPlaylistsResponse(raw: string, cap: number = 30): ParsedNeteasePlaylists {
  const out = new ParsedNeteasePlaylists();
  let root: Record<string, Object>;
  try {
    root = JSON.parse(raw) as Record<string, Object>;
  } catch (error) {
    return out;
  }
  out.code = readNumber(root, 'code');
  const rawArr = root['result'];
  if (!(rawArr instanceof Array)) {
    return out;
  }
  const arr: Object[] = rawArr as Object[];
  for (const entry of arr) {
    if (out.items.length >= cap) {
      break;
    }
    if (!(entry instanceof Object)) {
      continue;
    }
    const record = entry as Record<string, Object>;
    const summary = new NeteasePlaylistSummary();
    summary.id = readNumber(record, 'id');
    summary.name = readString(record, 'name');
    summary.coverUrl = toHttps(readString(record, 'picUrl'));
    summary.playCount = readNumber(record, 'playCount');
    summary.trackCount = readNumber(record, 'trackCount');
    if (summary.id !== 0 && summary.name.trim().length > 0 && summary.coverUrl.length > 0) {
      out.items.push(summary);
    }
  }
  return out;
}

/**
 * Parses /weapi/w/nuser/account/get and returns profile.userId. Throws with
 * diagnostic context when the account is not logged in (301) or the payload
 * lacks a profile, mirroring Android getCurrentUserId.
 */
export function parseNeteaseUserId(raw: string): number {
  const root = JSON.parse(raw) as Record<string, Object>;
  const code = readNumber(root, 'code');
  if (code !== 200) {
    throw new Error(`netease account fetch failed: code=${code}`);
  }
  const profile = root['profile'];
  if (profile !== undefined && profile !== null && profile instanceof Object) {
    const userId = readNumber(profile as Record<string, Object>, 'userId');
    if (userId > 0) {
      return userId;
    }
  }
  throw new Error('netease account response has no profile.userId');
}

/** Android shouldFallbackRecommend: logged-in codes that must retry anonymously. */
export function shouldFallbackRecommendToAnonymous(code: number): boolean {
  return code === 301 || code === 50000005;
}

/** Playlist header + resolved songs for the remote playlist detail page. */
export class NeteasePlaylistOverview {
  id: number = 0;
  name: string = '';
  coverUrl: string = '';
  trackCount: number = 0;
  songs: SongItem[] = [];
}

/**
 * NetEase song JSON comes in two field shapes: cloudsearch uses full names
 * (artists/album/duration) while /api/v6/playlist/detail and
 * /api/v3/song/detail use short ones (ar/al/dt). Verified against the live
 * endpoints on 2026-08-17; one mapper covers both.
 */
export interface NeteaseArtist {
  name: string;
  id?: number;
}

export interface NeteaseAlbum {
  id: number;
  name: string;
  picUrl?: string;
  /** Some endpoints (dj/radio tracks) expose the cover only as picStr. */
  picStr?: string;
}

export interface NeteaseSong {
  id: number;
  name: string;
  artists?: NeteaseArtist[];
  ar?: NeteaseArtist[];
  album?: NeteaseAlbum;
  al?: NeteaseAlbum;
  duration?: number;
  dt?: number;
  url?: string;
}

/** Maps either raw song shape into the app SongItem (https covers only). */
export function neteaseSongToSongItem(song: NeteaseSong): SongItem {
  const artists = song.artists !== undefined ? song.artists : (song.ar ?? []);
  const album = song.album !== undefined ? song.album : song.al;
  const artistNames: string[] = [];
  for (const artist of artists) {
    if (artist.name.length > 0) {
      artistNames.push(artist.name);
    }
  }
  let albumId = 0;
  let albumName = '';
  let coverUrl = '';
  if (album !== undefined && album !== null) {
    albumId = album.id ?? 0;
    albumName = album.name ?? '';
    coverUrl = toHttps(album.picUrl ?? album.picStr ?? '');
  }
  const item = new SongItem(
    song.id,
    song.name,
    artistNames.join(' / '),
    albumName,
    albumId,
    song.duration ?? song.dt ?? 0,
    coverUrl,
    '',
    MusicPlatform.NETEASE
  );
  item.channelId = 'netease';
  item.audioId = `${song.id}`;
  item.artistId = artists.length > 0 ? (artists[0].id ?? 0) : 0;
  return item;
}
