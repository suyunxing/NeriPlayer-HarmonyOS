import { SongItem } from '../model/SongItem';

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
