import { Constants } from '../app/Constants';
import { Logger } from '../app/Logger';
import { SongItem } from '../model/SongItem';
import { HttpClient } from './HttpClient';
import { NeteaseCrypto } from './NeteaseCrypto';
import { NeteaseCookieRepository } from '../data/auth/NeteaseCookieRepository';
import {
  NeteasePlaylistSummary,
  ParsedNeteasePlaylists,
  NeteasePlaylistOverview,
  NeteaseSong,
  parseUserPlaylistsResponse,
  parseRecommendPlaylistsResponse,
  parseNeteaseUserId,
  shouldFallbackRecommendToAnonymous,
  neteaseSongToSongItem
} from './NeteasePlaylistParser';

interface NeteaseSearchResponse {
  code: number;
  result?: NeteaseSearchResult;
}

interface NeteaseSearchResult {
  songs?: NeteaseSong[];
}

interface NeteaseUrlResponse {
  code: number;
  data?: NeteaseSong[];
}

interface NeteaseLyricResponse {
  lrc?: NeteaseLyricBlock;
  tlyric?: NeteaseLyricBlock;
  romalrc?: NeteaseLyricBlock;
}

interface NeteaseLyricBlock {
  lyric?: string;
}

interface NeteaseTrackId {
  id: number;
}

interface NeteasePlaylistResponse {
  code: number;
  playlist?: NeteasePlaylist;
}

interface NeteasePlaylist {
  id: number;
  name: string;
  description?: string;
  coverImgUrl?: string;
  trackCount?: number;
  tracks?: NeteaseSong[];
  trackIds?: NeteaseTrackId[];
}

class NeteaseSongId {
  id: number = 0;
}

interface NeteaseSongDetailResponse {
  code: number;
  songs?: NeteaseSong[];
}

/**
 * NetEase Cloud Music client (search, stream url, lyrics, playlist detail).
 */
export class NeteaseApi {
  private static readonly MOBILE_UA: string =
    'Mozilla/5.0 (Linux; Android 10; NeriPlayer) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';
  private static sessionReady: boolean = false;
  private static sessionPromise: Promise<void> | null = null;
  // Cached account uid, valid only while the login state it was fetched
  // under still holds (avoids stale ids across logout/relogin).
  private static cachedUserId: number = 0;
  private static cachedUserIdForLogin: boolean = false;

  private static headers(): Record<string, string> {
    const header: Record<string, string> = {};
    header['Accept'] = '*/*';
    header['Accept-Language'] = 'zh-CN,zh-Hans;q=0.9';
    header['Connection'] = 'keep-alive';
    header['Host'] = 'music.163.com';
    header['Referer'] = 'https://music.163.com';
    header['User-Agent'] = NeteaseApi.MOBILE_UA;
    return header;
  }

  /**
   * Visits the NetEase homepage once so the server issues session cookies
   * (notably __csrf), mirroring NeteaseClient.ensureWeapiSession().
   */
  private static ensureSession(): Promise<void> {
    if (NeteaseApi.sessionReady) {
      return Promise.resolve();
    }
    if (NeteaseApi.sessionPromise !== null) {
      return NeteaseApi.sessionPromise;
    }
    NeteaseApi.sessionPromise = NeteaseApi.doEnsureSession();
    return NeteaseApi.sessionPromise;
  }

  private static async doEnsureSession(): Promise<void> {
    // The credential restore (EntryAbility.onCreate -> repository.init()) is
    // async and un-awaited by the UI: without this await the cold-start
    // homepage request runs with an empty jar, the server issues an anonymous
    // __csrf, and sessionReady then pins that anonymous session for the whole
    // process even after MUSIC_U is restored.
    await NeteaseCookieRepository.init();
    // Login cookies (MUSIC_U etc.) go into the jar before the homepage GET so
    // the server sees the authenticated session and re-issues __csrf.
    NeteaseCookieRepository.seedHttpClient();
    try {
      await HttpClient.getText(`${Constants.NETEASE_BASE}/`, NeteaseApi.headers(), 15000, true);
    } catch (error) {
      const e = error as Error;
      Logger.warn(`NeteaseApi.ensureSession failed: ${e.message}`);
    }
    // The web client always carries these two cookies, even when logged out.
    HttpClient.seedCookies(`${Constants.NETEASE_BASE}/`, 'os=pc; appver=8.10.35');
    NeteaseApi.sessionReady = true;
  }

  /** Forces the next request to re-establish the weapi session. */
  static resetSession(): void {
    NeteaseApi.sessionReady = false;
    NeteaseApi.sessionPromise = null;
  }

  private static async weapiUrl(path: string): Promise<string> {
    await NeteaseApi.ensureSession();
    const cookies = HttpClient.getCookies(`${Constants.NETEASE_BASE}/`);
    const csrfMatch = /(?:^|;\s*)__csrf=([^;]+)/.exec(cookies);
    const csrf = csrfMatch !== null ? csrfMatch[1] : '';
    return `${Constants.NETEASE_BASE}${path}?csrf_token=${csrf}`;
  }

  static async search(keyword: string, limit: number = 30): Promise<SongItem[]> {
    try {
      let response = await NeteaseApi.searchWeapi(keyword, limit);
      // 2026-08-29 实测：登录态 jar 请求 cloudsearch 会被风控（code=50000005），
      // 匿名请求正常——与推荐接口同款行为。命中降级码时仅本次移除 MUSIC_U
      // 重试，完了恢复 cookie 种子；仍拿不到歌再走 legacy 兜底。
      const logged = NeteaseCookieRepository.isLoggedIn();
      if (logged && response.code !== 200 && shouldFallbackRecommendToAnonymous(response.code)) {
        Logger.warn(`NeteaseApi weapi search code=${response.code} while logged in, retrying anonymously`);
        HttpClient.removeCookie(`${Constants.NETEASE_BASE}/`, 'MUSIC_U');
        try {
          response = await NeteaseApi.searchWeapi(keyword, limit);
        } finally {
          NeteaseCookieRepository.seedHttpClient();
        }
      }
      const songs = response.code === 200 ? (response.result?.songs ?? []) : [];
      if (songs.length > 0) {
        const items: SongItem[] = [];
        for (const song of songs) {
          items.push(NeteaseApi.toSongItem(song));
        }
        return items;
      }
      Logger.warn(`NeteaseApi weapi search code=${response.code} songs=${songs.length}, falling back to legacy API`);
    } catch (error) {
      const e = error as Error;
      Logger.warn(`NeteaseApi weapi search failed, falling back to legacy API: ${e.message}`);
    }
    return NeteaseApi.searchLegacy(keyword, limit);
  }

  private static async searchWeapi(keyword: string, limit: number): Promise<NeteaseSearchResponse> {
    const payload: Record<string, Object> = {};
    payload['s'] = keyword;
    payload['type'] = '1';
    payload['limit'] = `${limit}`;
    payload['offset'] = '0';
    payload['total'] = 'true';
    const params = await NeteaseCrypto.weapiParams(payload);
    const url = await NeteaseApi.weapiUrl('/weapi/cloudsearch/get/web');
    const text = await HttpClient.postForm(
      url,
      params,
      15000,
      NeteaseApi.headers(),
      true
    );
    Logger.debug(`weapi search resp len=${text.length} head=${text.substring(0, 160)}`);
    return JSON.parse(text) as NeteaseSearchResponse;
  }

  private static async searchLegacy(keyword: string, limit: number): Promise<SongItem[]> {
    const url = `${Constants.NETEASE_BASE}/api/search/get/web?s=${encodeURIComponent(keyword)}&type=1&offset=0&limit=${limit}`;
    const text = await HttpClient.getText(url, NeteaseApi.headers(), 15000, true);
    Logger.debug(`legacy search resp len=${text.length} head=${text.substring(0, 160)}`);
    const response = JSON.parse(text) as NeteaseSearchResponse;
    if (response.code !== 200) {
      Logger.warn(`NeteaseApi legacy search code=${response.code}`);
      return [];
    }
    const songs = response.result?.songs ?? [];
    const items: SongItem[] = [];
    for (const song of songs) {
      items.push(NeteaseApi.toSongItem(song));
    }
    await NeteaseApi.fillSearchCovers(items);
    return items;
  }

  /**
   * legacy 搜索接口已不再返回 album.picUrl（2026-08-29 实测只剩 picId），
   * 走到该兜底时结果会整体无封面——播放页与动态取色也跟着拿不到图。
   * song/detail 批量接口仍返回完整 album.picUrl，按歌曲 id 补齐缺的封面；
   * 补图失败时保持无封面继续（UI 占位图兜底），不阻塞搜索结果。
   */
  private static async fillSearchCovers(items: SongItem[]): Promise<void> {
    const missing: SongItem[] = [];
    for (const item of items) {
      if (item.coverUrl.length === 0 && item.id > 0) {
        missing.push(item);
      }
    }
    if (missing.length === 0) {
      return;
    }
    const ids = missing.map((item: SongItem) => `${item.id}`).join(',');
    try {
      const text = await HttpClient.getText(
        `${Constants.NETEASE_BASE}/api/song/detail?ids=[${ids}]`,
        NeteaseApi.headers(),
        15000,
        true
      );
      const response = JSON.parse(text) as NeteaseSongDetailResponse;
      const picById = new Map<string, string>();
      for (const song of response.songs ?? []) {
        const pic = song.album?.picUrl ?? '';
        if (pic.length > 0) {
          picById.set(`${song.id}`, pic.replace('http://', 'https://'));
        }
      }
      for (const item of missing) {
        const pic = picById.get(`${item.id}`);
        if (pic !== undefined) {
          item.coverUrl = pic;
        }
      }
    } catch (error) {
      const e = error as Error;
      Logger.warn(`NeteaseApi fillSearchCovers failed: ${e.message}`);
    }
  }

  /**
   * Tries quality levels from highest to lowest, mirroring the Android
   * quality-fallback behavior.
   */
  static async getSongUrl(id: number, levels: string[] = ['exhigh', 'high', 'standard']): Promise<string> {
    for (const level of levels) {
      try {
        const url = await NeteaseApi.requestSongUrl(id, level);
        if (url.length > 0) {
          return url;
        }
      } catch (error) {
        const e = error as Error;
        Logger.warn(`NeteaseApi.getSongUrl level=${level} failed: ${e.message}`);
      }
    }
    // Legacy fallback endpoint (no weapi) for resilient clients.
    try {
      const legacy = await HttpClient.getText(
        `${Constants.NETEASE_BASE}/api/song/enhance/player/url?ids=[${id}]&br=320000`,
        NeteaseApi.headers()
      );
      const parsed = JSON.parse(legacy) as NeteaseUrlResponse;
      if (parsed.data !== undefined && parsed.data.length > 0 && parsed.data[0].url !== undefined) {
        return parsed.data[0].url;
      }
    } catch (error) {
      const e = error as Error;
      Logger.warn(`NeteaseApi legacy url failed: ${e.message}`);
    }
    return '';
  }

  static async getLyric(id: number): Promise<LyricPayload> {
    const text = await HttpClient.getText(
      `${Constants.NETEASE_BASE}/api/song/lyric?id=${id}&lv=-1&kv=-1&tv=-1&roma=-1`,
      NeteaseApi.headers()
    );
    const response = JSON.parse(text) as NeteaseLyricResponse;
    return new LyricPayload(
      response.lrc?.lyric ?? '',
      response.tlyric?.lyric ?? '',
      response.romalrc?.lyric ?? ''
    );
  }

  static async getPlaylistDetail(id: number): Promise<SongItem[]> {
    const overview = await NeteaseApi.getPlaylistOverview(id);
    return overview.songs;
  }

  /**
   * Home recommendations via /weapi/personalized/playlist. When the logged-in
   * jar trips a 301/risk-control code the call retries anonymously once,
   * mirroring Android HomeViewModel.refreshRecommend.
   */
  static async getRecommendedPlaylists(limit: number = 30): Promise<NeteasePlaylistSummary[]> {
    const logged = NeteaseCookieRepository.isLoggedIn();
    let parsed = await NeteaseApi.callRecommend(limit);
    if (logged && parsed.code !== 200 && shouldFallbackRecommendToAnonymous(parsed.code)) {
      Logger.warn(`NeteaseApi recommend code=${parsed.code} while logged in, retrying anonymously`);
      // The jar is shared: drop only MUSIC_U for this request, then restore.
      HttpClient.removeCookie(`${Constants.NETEASE_BASE}/`, 'MUSIC_U');
      try {
        parsed = await NeteaseApi.callRecommend(limit);
      } finally {
        NeteaseCookieRepository.seedHttpClient();
      }
    }
    return parsed.items;
  }

  private static async callRecommend(limit: number): Promise<ParsedNeteasePlaylists> {
    const payload: Record<string, Object> = {};
    payload['limit'] = `${limit}`;
    const params = await NeteaseCrypto.weapiParams(payload);
    const url = await NeteaseApi.weapiUrl('/weapi/personalized/playlist');
    const text = await HttpClient.postForm(url, params, 15000, NeteaseApi.headers(), true);
    return parseRecommendPlaylistsResponse(text, 30);
  }

  /**
   * Current account uid from /weapi/w/nuser/account/get. Throws when the
   * session is anonymous (301) or the payload has no profile, mirroring
   * Android getCurrentUserId.
   */
  static async getCurrentUserId(): Promise<number> {
    const logged = NeteaseCookieRepository.isLoggedIn();
    if (NeteaseApi.cachedUserId > 0 && NeteaseApi.cachedUserIdForLogin === logged) {
      return NeteaseApi.cachedUserId;
    }
    const payload: Record<string, Object> = {};
    const params = await NeteaseCrypto.weapiParams(payload);
    const url = await NeteaseApi.weapiUrl('/weapi/w/nuser/account/get');
    const text = await HttpClient.postForm(url, params, 15000, NeteaseApi.headers(), true);
    const uid = parseNeteaseUserId(text);
    NeteaseApi.cachedUserId = uid;
    NeteaseApi.cachedUserIdForLogin = logged;
    return uid;
  }

  /**
   * The logged-in user's playlists via /weapi/user/playlist (library tab).
   * A 301 while logged in refreshes the weapi session and retries once.
   */
  static async getUserPlaylists(offset: number = 0, limit: number = 30): Promise<NeteasePlaylistSummary[]> {
    const uid = await NeteaseApi.getCurrentUserId();
    let parsed = await NeteaseApi.callUserPlaylists(uid, offset, limit);
    if (parsed.code === 301 && NeteaseCookieRepository.isLoggedIn()) {
      Logger.warn('NeteaseApi user playlists got 301 while logged in, refreshing session');
      NeteaseApi.resetSession();
      parsed = await NeteaseApi.callUserPlaylists(uid, offset, limit);
    }
    return parsed.items;
  }

  private static async callUserPlaylists(uid: number, offset: number, limit: number): Promise<ParsedNeteasePlaylists> {
    const payload: Record<string, Object> = {};
    payload['uid'] = `${uid}`;
    payload['offset'] = `${offset}`;
    payload['limit'] = `${limit}`;
    payload['includeVideo'] = 'true';
    const params = await NeteaseCrypto.weapiParams(payload);
    const url = await NeteaseApi.weapiUrl('/weapi/user/playlist');
    const text = await HttpClient.postForm(url, params, 15000, NeteaseApi.headers(), true);
    return parseUserPlaylistsResponse(text);
  }

  /** Remote playlist header + fully resolved songs for the detail page. */
  static async getPlaylistOverview(id: number): Promise<NeteasePlaylistOverview> {
    const text = await HttpClient.getText(
      `${Constants.NETEASE_BASE}/api/v6/playlist/detail?id=${id}`,
      NeteaseApi.headers()
    );
    const response = JSON.parse(text) as NeteasePlaylistResponse;
    const overview = new NeteasePlaylistOverview();
    const playlist = response.playlist;
    if (playlist === undefined) {
      overview.id = id;
      return overview;
    }
    overview.id = playlist.id;
    overview.name = playlist.name;
    overview.coverUrl = (playlist.coverImgUrl ?? '').replace('http://', 'https://');
    overview.trackCount = playlist.trackCount ?? 0;
    // /api/v6/playlist/detail embeds only the first few tracks in `tracks`
    // while `trackIds` carries the authoritative full order. When trackIds is
    // longer, fetch the missing songs in batches and reassemble in playlist
    // order (mirrors Android resolvePlaylistTracks/fetchFullPlaylistTracks).
    let songs = playlist.tracks ?? [];
    if (playlist.trackIds !== undefined && playlist.trackIds.length > songs.length) {
      const byId = new Map<number, NeteaseSong>();
      for (const song of songs) {
        byId.set(song.id, song);
      }
      const orderedIds: number[] = [];
      const missing: number[] = [];
      for (const trackId of playlist.trackIds) {
        orderedIds.push(trackId.id);
        if (!byId.has(trackId.id)) {
          missing.push(trackId.id);
        }
      }
      if (missing.length > 0) {
        const fetched = await NeteaseApi.fetchSongDetail(missing);
        for (const song of fetched) {
          byId.set(song.id, song);
        }
      }
      songs = [];
      for (const id of orderedIds) {
        const song = byId.get(id);
        if (song !== undefined) {
          songs.push(song);
        }
      }
    }
    for (const song of songs) {
      overview.songs.push(NeteaseApi.toSongItem(song));
    }
    return overview;
  }

  private static async requestSongUrl(id: number, level: string): Promise<string> {
    let response = await NeteaseApi.callSongUrl(id, level);
    // Logged-in flow hitting a 301 ("not logged in"): refresh the weapi
    // session (re-seed MUSIC_U, fetch a fresh __csrf) and retry once,
    // mirroring Android getSongDownloadUrl.
    if (response.code === 301 && NeteaseCookieRepository.isLoggedIn()) {
      Logger.warn(`NeteaseApi song url got 301 while logged in, refreshing session`);
      NeteaseApi.resetSession();
      response = await NeteaseApi.callSongUrl(id, level);
    }
    if (response.data !== undefined && response.data.length > 0) {
      return response.data[0].url ?? '';
    }
    return '';
  }

  private static async callSongUrl(id: number, level: string): Promise<NeteaseUrlResponse> {
    const payload: Record<string, Object> = {};
    payload['ids'] = `[${id}]`;
    payload['level'] = level;
    payload['encodeType'] = 'aac';
    const params = await NeteaseCrypto.weapiParams(payload);
    const url = await NeteaseApi.weapiUrl('/weapi/song/enhance/player/url/v1');
    const text = await HttpClient.postForm(
      url,
      params,
      15000,
      NeteaseApi.headers(),
      true
    );
    const response = JSON.parse(text) as NeteaseUrlResponse;
    if (response.code === undefined) {
      response.code = -1;
    }
    return response;
  }

  private static async fetchSongDetail(ids: number[]): Promise<NeteaseSong[]> {
    if (ids.length === 0) {
      return [];
    }
    const chunks: NeteaseSong[] = [];
    const chunkSize = 200;
    for (let offset = 0; offset < ids.length; offset += chunkSize) {
      const chunk = ids.slice(offset, offset + chunkSize);
      const c = JSON.stringify(chunk.map((id: number): NeteaseSongId => {
        const request = new NeteaseSongId();
        request.id = id;
        return request;
      }));
      const form: Record<string, string> = {};
      form['c'] = c;
      const text = await HttpClient.postForm(
        `${Constants.NETEASE_BASE}/api/v3/song/detail`,
        form,
        15000,
        NeteaseApi.headers()
      );
      const response = JSON.parse(text) as NeteaseSongDetailResponse;
      if (response.songs !== undefined) {
        chunks.push(...response.songs);
      }
    }
    return chunks;
  }

  private static toSongItem(song: NeteaseSong): SongItem {
    // cloudsearch returns artists/album while playlist/song-detail return the
    // short ar/al shape; the pure mapper in NeteasePlaylistParser covers both.
    return neteaseSongToSongItem(song);
  }
}

export class LyricPayload {
  lyric: string;
  translated: string;
  phonetic: string;

  constructor(lyric: string = '', translated: string = '', phonetic: string = '') {
    this.lyric = lyric;
    this.translated = translated;
    this.phonetic = phonetic;
  }
}
