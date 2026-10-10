// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

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
import { buildNeteasePlaylistAddTracksParams } from './NeteasePlaylistWriteback';
import {
  NeteaseApiCodeError,
  parseNeteaseHomePlaylists,
  parseNeteaseHomeSongs,
  parseNeteasePlaylistDetailSummaryOrNull
} from './NeteaseHomeRecommendations';
import { AudioQualityPolicy } from '../player/AudioQualityPolicy';
import { NetworkStatus } from '../util/NetworkStatus';
import { MusicPlatform } from '../model/MusicPlatform';

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
  yrc?: NeteaseLyricBlock;
  ytlrc?: NeteaseLyricBlock;
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
  /** Playlist-level last-updated (ms). Present on /api/v6/playlist/detail; used as the source-sync fingerprint. */
  updateTime?: number;
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
    // appver tracks the current web client version (api-enhanced osMap pc),
    // kept in sync with NeteasePhoneLogin.buildWebSessionSeed so the shared
    // jar never flips between two appver values.
    HttpClient.seedCookies(`${Constants.NETEASE_BASE}/`, 'os=pc; appver=3.1.17.204416');
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
   * quality-fallback behavior. The starting tier follows the per-network +
   * per-platform policy (backlog §7).
   */
  static async getSongUrl(id: number, levels: string[] = []): Promise<string> {
    let ladder = levels;
    if (ladder.length === 0) {
      const chosen = AudioQualityPolicy.effectiveForPlatform(await NetworkStatus.isWifi(),
        MusicPlatform.NETEASE);
      ladder = NeteaseApi.qualityLadderFrom(chosen);
    }
    for (const level of ladder) {
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
    return NeteaseApi.getSongUrlLegacy(id);
  }

  /** Ordered fallback ladder starting at the chosen tier (Android parity). */
  static qualityLadderFrom(chosen: string): string[] {
    const ladder = ['lossless', 'exhigh', 'high', 'standard'];
    const index = ladder.indexOf(chosen);
    if (index < 0) {
      return ['exhigh', 'high', 'standard'];
    }
    return ladder.slice(index);
  }

  /**
   * Anonymous legacy URL endpoint (320k mp3 on the jdymusic CDN). The download
   * path prefers this source: the weapi AAC CDN (jdyyaac) serves payloads with
   * periodic filler runs (~1.2% of bytes) that stream fine but fail local
   * playback with 5400106 CONTAINER_ERR once committed to disk.
   */
  static async getSongUrlLegacy(id: number): Promise<string> {
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
      `${Constants.NETEASE_BASE}/api/song/lyric?id=${id}&lv=-1&kv=-1&tv=-1&roma=-1&yv=-1&ytv=-1&yrv=-1`,
      NeteaseApi.headers()
    );
    const response = JSON.parse(text) as NeteaseLyricResponse;
    // Android extractPreferredNeteaseLyricContent: word-timed YRC wins over
    // plain LRC; its translation (ytlrc) wins over tlyric. LrcParser
    // auto-detects YRC-shaped lines, so downstream stays format-agnostic.
    const yrc = response.yrc?.lyric ?? '';
    const ytlrc = response.ytlrc?.lyric ?? '';
    const lrc = yrc.length > 0 ? yrc : (response.lrc?.lyric ?? '');
    const translated = ytlrc.length > 0 ? ytlrc : (response.tlyric?.lyric ?? '');
    return new LyricPayload(
      lrc,
      translated,
      response.romalrc?.lyric ?? ''
    );
  }

  static async getPlaylistDetail(id: number): Promise<SongItem[]> {
    const overview = await NeteaseApi.getPlaylistOverview(id);
    return overview.songs;
  }

  /**
   * Cheap playlist change fingerprint for source-sync, without resolving the
   * songs: prefers the playlist-level updateTime (ms) and degrades to the
   * track count when the field is absent. One /api/v6/playlist/detail request.
   */
  static async getPlaylistFingerprint(id: number): Promise<string> {
    const text = await HttpClient.getText(
      `${Constants.NETEASE_BASE}/api/v6/playlist/detail?id=${id}`,
      NeteaseApi.headers()
    );
    const response = JSON.parse(text) as NeteasePlaylistResponse;
    const playlist = response.playlist;
    if (playlist === undefined) {
      throw new Error(`netease playlist detail empty: id=${id}`);
    }
    if (playlist.updateTime !== undefined && playlist.updateTime > 0) {
      return `u${playlist.updateTime}`;
    }
    return `t${playlist.trackCount ?? 0}`;
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

  // ---- 首页推荐扩展（上游 #319/#338） ----

  /**
   * 推荐族 weapi 调用：登录态端点在响应 code 301（会话失效）时 resetSession
   * 重试一次（parse 抛出的 NeteaseApiCodeError 包在 call 闭包内，重试才有
   * 机会感知）。
   */
  private static async weapiHomeCall<T>(path: string, params: Map<string, string>,
    parse: (raw: string) => T, loginRequired: boolean): Promise<T> {
    const call = (): Promise<T> =>
      NeteaseApi.callWeapiText(path, params).then((raw: string): T => parse(raw));
    if (!loginRequired) {
      return call();
    }
    try {
      return await call();
    } catch (error) {
      if (error instanceof NeteaseApiCodeError && error.code === 301
        && NeteaseCookieRepository.isLoggedIn()) {
        Logger.warn(`NeteaseApi ${path} got 301 while logged in, refreshing session`);
        NeteaseApi.resetSession();
        return call();
      }
      if (error instanceof Error) {
        throw error;
      }
      throw new Error(`NeteaseApi ${path} failed`);
    }
  }

  /** 每日推荐歌单（/v1/discovery/recommend/resource，需登录）。 */
  static async getDailyRecommendedPlaylists(): Promise<NeteasePlaylistSummary[]> {
    return NeteaseApi.weapiHomeCall('/weapi/v1/discovery/recommend/resource',
      new Map<string, string>(), parseNeteaseHomePlaylists, true);
  }

  /** 每日推荐歌曲（/v3/discovery/recommend/songs，需登录；afresh 换一批）。 */
  static async getDailyRecommendedSongs(afresh: boolean): Promise<SongItem[]> {
    const params = new Map<string, string>();
    params.set('afresh', `${afresh}`);
    return NeteaseApi.weapiHomeCall('/weapi/v3/discovery/recommend/songs',
      params, parseNeteaseHomeSongs, true);
  }

  /** 私人 FM（/v1/radio/get，需登录）。 */
  static async getPersonalFmSongs(): Promise<SongItem[]> {
    return NeteaseApi.weapiHomeCall('/weapi/v1/radio/get',
      new Map<string, string>(), parseNeteaseHomeSongs, true);
  }

  /** 推荐新歌（/personalized/newsong，匿名可用）。 */
  static async getPersonalizedNewSongs(limit: number = 30): Promise<SongItem[]> {
    const params = new Map<string, string>();
    params.set('type', 'recommend');
    params.set('limit', `${limit}`);
    params.set('areaId', '0');
    return NeteaseApi.weapiHomeCall('/weapi/personalized/newsong',
      params, parseNeteaseHomeSongs, false);
  }

  /** 分类歌单（/top/playlist，匿名可用）。 */
  static async getTopPlaylists(cat: string = '全部', order: string = 'hot',
    limit: number = 30, offset: number = 0): Promise<NeteasePlaylistSummary[]> {
    const params = new Map<string, string>();
    params.set('cat', cat);
    params.set('order', order);
    params.set('limit', `${limit}`);
    params.set('offset', `${offset}`);
    params.set('total', 'true');
    return NeteaseApi.weapiHomeCall('/weapi/top/playlist',
      params, parseNeteaseHomePlaylists, false);
  }

  /**
   * 轻量歌单摘要（雷达歌单元数据用）：只取 /api/v6/playlist/detail 头部对象，
   * 不做 trackIds 全量补拉（getPlaylistOverview 会对大歌单分批拉曲，此处不需要）。
   */
  static async getPlaylistSummary(id: number): Promise<NeteasePlaylistSummary | null> {
    const text = await HttpClient.getText(
      `${Constants.NETEASE_BASE}/api/v6/playlist/detail?id=${id}`,
      NeteaseApi.headers()
    );
    return parseNeteasePlaylistDetailSummaryOrNull(text);
  }

  private static async callWeapiText(path: string, params: Map<string, string>):
    Promise<string> {
    const payload: Record<string, Object> = {};
    for (const entry of params) {
      payload[entry[0]] = entry[1];
    }
    const encrypted = await NeteaseCrypto.weapiParams(payload);
    const url = await NeteaseApi.weapiUrl(path);
    return HttpClient.postForm(url, encrypted, 15000, NeteaseApi.headers(), true);
  }

  /**
   * 往自建歌单批量加歌（/weapi/playlist/manipulate/tracks，上游 #322）。
   * 返回体 code 200 为成功；登录态下 301 先 resetSession 再重试一次。
   */
  static async addSongsToPlaylist(playlistId: number, songIds: number[]): Promise<boolean> {
    let code = await NeteaseApi.callPlaylistManipulateTracks(playlistId, songIds);
    if (code === 301 && NeteaseCookieRepository.isLoggedIn()) {
      Logger.warn('NeteaseApi playlist manipulate got 301 while logged in, refreshing session');
      NeteaseApi.resetSession();
      code = await NeteaseApi.callPlaylistManipulateTracks(playlistId, songIds);
    }
    return code === 200;
  }

  private static async callPlaylistManipulateTracks(playlistId: number,
    songIds: number[]): Promise<number> {
    const payload: Record<string, Object> = {};
    const params = buildNeteasePlaylistAddTracksParams(playlistId, songIds);
    for (const key of Object.keys(params)) {
      payload[key] = params[key];
    }
    const encrypted = await NeteaseCrypto.weapiParams(payload);
    const url = await NeteaseApi.weapiUrl('/weapi/playlist/manipulate/tracks');
    const text = await HttpClient.postForm(url, encrypted, 15000, NeteaseApi.headers(), true);
    let root: Record<string, Object>;
    try {
      root = JSON.parse(text) as Record<string, Object>;
    } catch (error) {
      return -1;
    }
    const code = Number(root['code'] ?? -1);
    return Number.isFinite(code) ? code : -1;
  }

  /**
   * 目标歌单现有曲目 id 快照（写回去重与失败复核用）：null = 获取失败或
   * 响应可疑（trackCount>0 却解析不出曲目）。复用 getPlaylistOverview 的
   * 完整解析（含 trackIds 超出首屏的分批补拉）。
   */
  static async playlistTrackIdSet(playlistId: number): Promise<Set<number> | null> {
    try {
      const overview = await NeteaseApi.getPlaylistOverview(playlistId);
      const ids = new Set<number>();
      for (const song of overview.songs) {
        const id = Number(song.audioId);
        if (Number.isFinite(id) && id > 0) {
          ids.add(id);
        }
      }
      if (ids.size === 0 && overview.trackCount > 0) {
        return null;
      }
      return ids;
    } catch (error) {
      return null;
    }
  }

  /**
   * 批量解析曲目是否仍可访问（/song/detail）：写回失败归因用，返回仍存在
   * 的 id 集；null = 查询失败（调用方不应据此猜测）。
   */
  static async resolvableNeteaseSongIds(ids: number[]): Promise<Set<number> | null> {
    try {
      const songs = await NeteaseApi.fetchSongDetail(ids);
      const resolved = new Set<number>();
      for (const song of songs) {
        resolved.add(song.id);
      }
      return resolved;
    } catch (error) {
      return null;
    }
  }

  /** 歌曲 id → 可播放 SongItem（探索页链接解析开播用）。 */
  static async getSongsByIds(ids: number[]): Promise<SongItem[]> {
    const songs = await NeteaseApi.fetchSongDetail(ids);
    const items: SongItem[] = [];
    for (const song of songs) {
      items.push(NeteaseApi.toSongItem(song));
    }
    return items;
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

  // ---- 专辑 / 艺人详情（backlog §3.4，Android getAlbumDetail /
  // getArtistSongs / getArtistHead / getArtistAlbums） -----------------------

  /** Album detail + full track list (weapi /weapi/v1/album/{id}). */
  static async getAlbumDetail(albumId: number): Promise<SongItem[]> {
    if (albumId <= 0) {
      return [];
    }
    try {
      const payload: Record<string, Object> = {};
      payload['n'] = '100000';
      payload['s'] = '8';
      const params = await NeteaseCrypto.weapiParams(payload);
      const url = await NeteaseApi.weapiUrl(`/weapi/v1/album/${albumId}`);
      const text = await HttpClient.postForm(url, params, 15000, NeteaseApi.headers(), true);
      const response = JSON.parse(text) as Record<string, Object>;
      if (Number(response['code'] ?? -1) !== 200) {
        Logger.warn(`NeteaseApi album detail code=${Number(response['code'] ?? -1)}`);
        return [];
      }
      const album = response['album'] as Record<string, Object> | undefined;
      const songs = response['songs'] as Object[] | undefined;
      const items: SongItem[] = [];
      if (songs !== undefined && Array.isArray(songs)) {
        for (const raw of songs) {
          items.push(NeteaseApi.toSongItem(raw as NeteaseSong));
        }
      }
      // The weapi album payload omits per-song covers; the album art covers all.
      if (album !== undefined && album['picUrl'] !== undefined) {
        const pic = String(album['picUrl']);
        for (const item of items) {
          if (item.coverUrl.length === 0) {
            item.coverUrl = pic;
          }
        }
      }
      return items;
    } catch (error) {
      const e = error as Error;
      Logger.warn(`NeteaseApi album detail failed: ${e.message}`);
      return [];
    }
  }

  /** Artist hot/new songs (legacy /api/v1/artist/songs, POST form). */
  static async getArtistSongs(artistId: number, order: string = 'hot', limit: number = 50): Promise<SongItem[]> {
    if (artistId <= 0) {
      return [];
    }
    try {
      const form: Record<string, string> = {};
      form['id'] = `${artistId}`;
      form['private_cloud'] = 'true';
      form['work_type'] = '1';
      form['order'] = order;
      form['offset'] = '0';
      form['limit'] = `${limit}`;
      const text = await HttpClient.postForm(
        `${Constants.NETEASE_BASE}/api/v1/artist/songs`,
        form,
        15000,
        NeteaseApi.headers(),
        true
      );
      const response = JSON.parse(text) as Record<string, Object>;
      if (Number(response['code'] ?? -1) !== 200) {
        Logger.warn(`NeteaseApi artist songs code=${Number(response['code'] ?? -1)}`);
        return [];
      }
      const songs = response['songs'] as Object[] | undefined;
      const items: SongItem[] = [];
      if (songs !== undefined && Array.isArray(songs)) {
        for (const raw of songs) {
          items.push(NeteaseApi.toSongItem(raw as NeteaseSong));
        }
      }
      return items;
    } catch (error) {
      const e = error as Error;
      Logger.warn(`NeteaseApi artist songs failed: ${e.message}`);
      return [];
    }
  }

  /** Artist head info (name/cover/fans) for the artist page header. */
  static async getArtistHead(artistId: number): Promise<NeteaseArtistHead | null> {
    if (artistId <= 0) {
      return null;
    }
    try {
      const form: Record<string, string> = {};
      form['id'] = `${artistId}`;
      const text = await HttpClient.postForm(
        `${Constants.NETEASE_BASE}/api/artist/head/info/get`,
        form,
        15000,
        NeteaseApi.headers(),
        true
      );
      const response = JSON.parse(text) as Record<string, Object>;
      if (Number(response['code'] ?? -1) !== 200) {
        return null;
      }
      const data = response['data'] as Record<string, Object> | undefined;
      const artist = data === undefined ? undefined : data['artist'] as Record<string, Object> | undefined;
      const head = new NeteaseArtistHead();
      if (artist !== undefined) {
        head.name = String(artist['name'] ?? '');
        head.coverUrl = String(artist['cover'] ?? '');
        head.albumCount = Number(artist['albumCount'] ?? 0);
        head.songCount = Number(artist['songCount'] ?? 0);
        head.fansCount = Number(artist['fansCount'] ?? 0);
      }
      return head.name.length > 0 ? head : null;
    } catch (error) {
      const e = error as Error;
      Logger.warn(`NeteaseApi artist head failed: ${e.message}`);
      return null;
    }
  }
}

export class NeteaseArtistHead {
  name: string = '';
  coverUrl: string = '';
  albumCount: number = 0;
  songCount: number = 0;
  fansCount: number = 0;
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
