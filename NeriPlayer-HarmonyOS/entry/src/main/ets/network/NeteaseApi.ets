import { Constants } from '../app/Constants';
import { Logger } from '../app/Logger';
import { SongItem } from '../model/SongItem';
import { MusicPlatform } from '../model/MusicPlatform';
import { HttpClient } from './HttpClient';
import { NeteaseCrypto } from './NeteaseCrypto';
import { NeteaseCookieRepository } from '../data/auth/NeteaseCookieRepository';

interface NeteaseArtist {
  name: string;
}

interface NeteaseAlbum {
  id: number;
  name: string;
  picUrl?: string;
}

interface NeteaseSong {
  id: number;
  name: string;
  artists: NeteaseArtist[];
  album: NeteaseAlbum;
  duration?: number;
  dt?: number;
  url?: string;
}

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
      const items = await NeteaseApi.searchWeapi(keyword, limit);
      if (items.length > 0) {
        return items;
      }
      Logger.warn('NeteaseApi weapi search returned no songs, falling back to legacy API');
    } catch (error) {
      const e = error as Error;
      Logger.warn(`NeteaseApi weapi search failed, falling back: ${e.message}`);
    }
    return NeteaseApi.searchLegacy(keyword, limit);
  }

  private static async searchWeapi(keyword: string, limit: number): Promise<SongItem[]> {
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
    const response = JSON.parse(text) as NeteaseSearchResponse;
    if (response.code !== 200) {
      Logger.warn(`NeteaseApi weapi search code=${response.code}`);
      return [];
    }
    const songs = response.result?.songs ?? [];
    const items: SongItem[] = [];
    for (const song of songs) {
      items.push(NeteaseApi.toSongItem(song));
    }
    return items;
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
    return items;
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
      `${Constants.NETEASE_BASE}/api/song/lyric?id=${id}&lv=-1&kv=-1&tv=-1`,
      NeteaseApi.headers()
    );
    const response = JSON.parse(text) as NeteaseLyricResponse;
    return new LyricPayload(response.lrc?.lyric ?? '', response.tlyric?.lyric ?? '');
  }

  static async getPlaylistDetail(id: number): Promise<SongItem[]> {
    const text = await HttpClient.getText(
      `${Constants.NETEASE_BASE}/api/v6/playlist/detail?id=${id}`,
      NeteaseApi.headers()
    );
    const response = JSON.parse(text) as NeteasePlaylistResponse;
    const playlist = response.playlist;
    if (playlist === undefined) {
      return [];
    }
    let songs = playlist.tracks ?? [];
    if (songs.length === 0 && playlist.trackIds !== undefined) {
      const ids: number[] = [];
      for (const trackId of playlist.trackIds.slice(0, 200)) {
        ids.push(trackId.id);
      }
      songs = await NeteaseApi.fetchSongDetail(ids);
    }
    const items: SongItem[] = [];
    for (const song of songs) {
      items.push(NeteaseApi.toSongItem(song));
    }
    return items;
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
    const artistNames: string[] = [];
    if (song.artists !== undefined) {
      for (const artist of song.artists) {
        artistNames.push(artist.name);
      }
    }
    const item = new SongItem(
      song.id,
      song.name,
      artistNames.join(' / '),
      song.album !== undefined ? song.album.name : '',
      song.album !== undefined ? song.album.id : 0,
      song.duration ?? song.dt ?? 0,
      song.album !== undefined ? (song.album.picUrl ?? '') : '',
      '',
      MusicPlatform.NETEASE
    );
    item.channelId = 'netease';
    item.audioId = `${song.id}`;
    return item;
  }
}

export class LyricPayload {
  lyric: string;
  translated: string;

  constructor(lyric: string = '', translated: string = '') {
    this.lyric = lyric;
    this.translated = translated;
  }
}
