import { Logger } from '../app/Logger';
import { Constants } from '../app/Constants';
import { SongItem } from '../model/SongItem';
import { MusicPlatform } from '../model/MusicPlatform';
import { HttpClient } from './HttpClient';
import { BiliStreamSupport } from './BiliStreamSupport';
import { BiliCookieRepository } from '../data/auth/BiliCookieRepository';
import {
  BiliFavFolderSummary,
  BiliFavMedia,
  BiliFavPage,
  parseBiliFavFolderList,
  parseBiliFavResourcePage,
  biliFavMediaDedupKey
} from './BiliFavParser';

interface BiliSearchItem {
  bvid: string;
  title: string;
  author: string;
  pic: string;
  duration: string;
}

interface BiliSearchResponse {
  code: number;
  data?: BiliSearchData;
}

interface BiliSearchData {
  result?: BiliSearchItem[];
}

interface BiliDashAudio {
  bandwidth: number;
  baseUrl?: string;
  backupUrl?: string[];
}

interface BiliPlayUrlResponse {
  code: number;
  message?: string;
  data?: BiliPlayData;
}

interface BiliPlayData {
  dash?: BiliDash;
}

interface BiliDash {
  audio?: BiliDashAudio[];
}

interface BiliViewResponse {
  code: number;
  message?: string;
  data?: BiliViewData;
}

interface BiliViewData {
  cid?: number;
}

interface BiliSpiResponse {
  code?: number;
  data?: BiliSpiData;
}

interface BiliSpiData {
  b_3?: string;
  b_4?: string;
  buvid_fp?: string;
  b_lsid?: string;
}

const FAV_PAGE_SIZE: number = 20;
const ANON_COOKIE_TTL_MS: number = 60 * 60 * 1000; // mirrors Android's 1h anon cookie cache
const FAV_FOLDER_WEB_LOCATION: string = '333.1387';

/**
 * Bilibili client (video search + audio stream resolution + favorite
 * folders), following the bilibili-API-collect conventions used by the
 * Android app. Requests carry the persisted login cookie jar when logged in,
 * or anonymous buvid fingerprint cookies otherwise (Android getEffectiveCookies).
 */
export class BiliApi {
  private static anonCookieFetchedAt: number = 0;
  // playurl rejects bvid-only requests with -400 since 2026; the cid from the
  // view endpoint is stable per video, so cache it for the process lifetime.
  private static cidCache: Map<string, number> = new Map();

  private static biliHeaders(): Record<string, string> {
    const headers: Record<string, string> = {};
    headers['Referer'] = 'https://www.bilibili.com';
    return headers;
  }

  /**
   * Makes sure the api.bilibili.com cookie jar has something usable: the
   * login bundle is seeded by BiliCookieRepository, and the anonymous
   * fingerprint (/x/frontend/finger/spi) is fetched when logged out (1h TTL
   * refresh) or when the login bundle itself lacks a buvid — risk control
   * rejects SESSDATA-only playurl requests, and QR login cookies usually do
   * not include one. Failures degrade silently to cookie-less requests.
   */
  private static async ensureRequestCookies(): Promise<void> {
    const jar = HttpClient.getCookies(`${Constants.BILI_BASE}/`);
    if (jar.indexOf('buvid3=') >= 0) {
      if (BiliCookieRepository.isLoggedIn()) {
        return;
      }
      if (Date.now() - BiliApi.anonCookieFetchedAt < ANON_COOKIE_TTL_MS) {
        return;
      }
    }
    try {
      const text = await HttpClient.getText(
        `${Constants.BILI_BASE}/x/frontend/finger/spi`,
        BiliApi.biliHeaders()
      );
      const parsed = JSON.parse(text) as BiliSpiResponse;
      const data = parsed.data;
      if (data === undefined) {
        return;
      }
      const pairs: string[] = [];
      if (data.b_3 !== undefined && data.b_3.length > 0) {
        pairs.push(`buvid3=${data.b_3}`);
      }
      if (data.b_4 !== undefined && data.b_4.length > 0) {
        pairs.push(`buvid4=${data.b_4}`);
      }
      if (data.buvid_fp !== undefined && data.buvid_fp.length > 0) {
        pairs.push(`buvid_fp=${data.buvid_fp}`);
      }
      if (data.b_lsid !== undefined && data.b_lsid.length > 0) {
        pairs.push(`b_lsid=${data.b_lsid}`);
      }
      if (pairs.length > 0) {
        HttpClient.seedCookies(`${Constants.BILI_BASE}/`, pairs.join('; '));
        BiliApi.anonCookieFetchedAt = Date.now();
        Logger.info(`bili fingerprint cookies seeded: ${pairs.length} entries`);
      }
    } catch (error) {
      const e = error as Error;
      Logger.warn(`bili anon cookie fetch failed (continuing without): ${e.message}`);
    }
  }

  static async search(keyword: string, limit: number = 20): Promise<SongItem[]> {
    const url =
      `${Constants.BILI_BASE}/x/web-interface/search/type?search_type=video&keyword=${encodeURIComponent(keyword)}`;
    await BiliApi.ensureRequestCookies();
    const text = await HttpClient.getText(url, BiliApi.biliHeaders(), 15000, true);
    const response = JSON.parse(text) as BiliSearchResponse;
    const results = response.data?.result ?? [];
    const items: SongItem[] = [];
    for (const item of results.slice(0, limit)) {
      const song = new SongItem(
        0,
        BiliApi.stripHtml(item.title),
        item.author,
        'Bilibili',
        0,
        BiliApi.parseDurationMs(item.duration),
        item.pic.startsWith('http://') ? `https://${item.pic.substring(7)}` : item.pic,
        '',
        MusicPlatform.BILIBILI
      );
      song.channelId = 'bilibili';
      song.audioId = item.bvid;
      items.push(song);
    }
    return items;
  }

  /**
   * Resolves the best DASH audio stream for a bvid. The playurl endpoint
   * requires the video cid (fetched once per bvid via the view endpoint,
   * cached — Android passes the same parameter), and follows the Android
   * web-parameter conventions (platform=pc requires the Referer header that
   * biliHeaders() always sends). Failures throw with server context instead
   * of returning '' so playback logs stay diagnosable.
   */
  static async resolveAudioUrl(bvid: string): Promise<string> {
    const cid = await BiliApi.resolveCid(bvid);
    const url =
      `${Constants.BILI_BASE}/x/player/playurl?bvid=${bvid}&cid=${cid}&fnval=16&fnver=0&platform=pc&fourk=1`;
    await BiliApi.ensureRequestCookies();
    const text = await HttpClient.getText(url, BiliApi.biliHeaders(), 15000, true);
    const response = JSON.parse(text) as BiliPlayUrlResponse;
    if (response.code !== 0) {
      throw new Error(`bili playurl rejected: code=${response.code} bvid=${bvid} message=${response.message ?? ''}`);
    }
    const audioList = response.data?.dash?.audio ?? [];
    if (audioList.length === 0) {
      Logger.warn(`bili playurl returned no dash audio: bvid=${bvid}`);
      return '';
    }
    let best = audioList[0];
    for (const audio of audioList) {
      if (audio.bandwidth > best.bandwidth) {
        best = audio;
      }
    }
    const candidates: string[] = [];
    const baseUrl = best.baseUrl ?? '';
    if (baseUrl.length > 0) {
      candidates.push(baseUrl);
    }
    if (best.backupUrl !== undefined) {
      for (const backup of best.backupUrl) {
        if (backup.length > 0) {
          candidates.push(backup);
        }
      }
    }
    return BiliStreamSupport.pickBestStreamUrl(candidates);
  }

  /**
   * Resolves the video cid required by playurl (first page of the bvid).
   * Cached per bvid for the process lifetime — the mapping is immutable.
   */
  static async resolveCid(bvid: string): Promise<number> {
    const cached = BiliApi.cidCache.get(bvid);
    if (cached !== undefined) {
      return cached;
    }
    await BiliApi.ensureRequestCookies();
    const url = `${Constants.BILI_BASE}/x/web-interface/view?bvid=${bvid}`;
    const text = await HttpClient.getText(url, BiliApi.biliHeaders(), 15000, true);
    const response = JSON.parse(text) as BiliViewResponse;
    if (response.code !== 0) {
      throw new Error(`bili view rejected: code=${response.code} bvid=${bvid} message=${response.message ?? ''}`);
    }
    const cid = response.data?.cid ?? 0;
    if (cid <= 0) {
      throw new Error(`bili view returned no cid: bvid=${bvid}`);
    }
    BiliApi.cidCache.set(bvid, cid);
    return cid;
  }

  /**
   * HTTP headers Bilibili CDN endpoints expect from stream fetches; the
   * api.bilibili.com cookie jar entry carries the login bundle or the
   * anonymous buvid fingerprint. Null for non-Bilibili hosts.
   */
  static streamHeadersFor(url: string): Record<string, string> | null {
    return BiliStreamSupport.buildStreamHeaders(
      url,
      HttpClient.getCookies(`${Constants.BILI_BASE}/`)
    );
  }

  /**
   * Lists the user's created favorite folders: created/list-all first, with
   * the paginated created/list endpoint as a fallback when count > list size
   * (Android getUserCreatedFavFolders). Login cookies required for non-empty
   * results.
   */
  static async getUserFavFolders(mid: number): Promise<BiliFavFolderSummary[]> {
    if (mid <= 0) {
      throw new Error('无法获取用户 mid（DedeUserID 缺失）');
    }
    await BiliApi.ensureRequestCookies();
    const listAllUrl =
      `${Constants.BILI_BASE}/x/v3/fav/folder/created/list-all?up_mid=${mid}&web_location=${FAV_FOLDER_WEB_LOCATION}`;
    const first = parseBiliFavFolderList(await HttpClient.getText(listAllUrl, BiliApi.biliHeaders(), 15000, true));
    if (first.totalCount <= first.folders.length) {
      return first.folders;
    }
    const merged = new Map<number, BiliFavFolderSummary>();
    for (const folder of first.folders) {
      merged.set(folder.mediaId, folder);
    }
    const totalPages = Math.ceil(first.totalCount / FAV_PAGE_SIZE);
    for (let pn = 2; pn <= totalPages; pn++) {
      const pageUrl =
        `${Constants.BILI_BASE}/x/v3/fav/folder/created/list?up_mid=${mid}&pn=${pn}&ps=${FAV_PAGE_SIZE}&web_location=${FAV_FOLDER_WEB_LOCATION}`;
      try {
        const page = parseBiliFavFolderList(await HttpClient.getText(pageUrl, BiliApi.biliHeaders(), 15000, true));
        for (const folder of page.folders) {
          if (!merged.has(folder.mediaId)) {
            merged.set(folder.mediaId, folder);
          }
        }
      } catch (error) {
        // Failed pages are skipped (Android parallel fetch tolerates this too).
        const e = error as Error;
        Logger.warn(`bili fav folder page ${pn} failed: ${e.message}`);
      }
    }
    const out: BiliFavFolderSummary[] = [];
    merged.forEach((folder: BiliFavFolderSummary) => {
      out.push(folder);
    });
    return out;
  }

  /** Fetches one page of a favorite folder's contents (Android getFavFolderContents). */
  static async getFavFolderPage(mediaId: number, page: number, keyword: string = ''): Promise<BiliFavPage> {
    await BiliApi.ensureRequestCookies();
    let url =
      `${Constants.BILI_BASE}/x/v3/fav/resource/list?media_id=${mediaId}&pn=${page}&ps=${FAV_PAGE_SIZE}` +
      `&order=mtime&platform=web`;
    if (keyword.length > 0) {
      url += `&keyword=${encodeURIComponent(keyword)}`;
    }
    const text = await HttpClient.getText(url, BiliApi.biliHeaders(), 15000, true);
    return parseBiliFavResourcePage(text);
  }

  /**
   * Fetches every item of a favorite folder sequentially (Android
   * getAllFavFolderItems: stop at !has_more or count reached, failed pages
   * skipped, entries deduped by type:id:bvid).
   */
  static async getAllFavFolderItems(mediaId: number): Promise<BiliFavMedia[]> {
    const first = await BiliApi.getFavFolderPage(mediaId, 1);
    const items: BiliFavMedia[] = [];
    const seen = new Set<string>();
    for (const item of first.items) {
      const key = biliFavMediaDedupKey(item);
      if (!seen.has(key)) {
        seen.add(key);
        items.push(item);
      }
    }
    if (!first.hasMore || first.totalCount <= items.length) {
      return items;
    }
    const totalPages = Math.ceil(first.totalCount / FAV_PAGE_SIZE);
    for (let pn = 2; pn <= totalPages; pn++) {
      try {
        const page = await BiliApi.getFavFolderPage(mediaId, pn);
        for (const item of page.items) {
          const key = biliFavMediaDedupKey(item);
          if (!seen.has(key)) {
            seen.add(key);
            items.push(item);
          }
        }
        if (!page.hasMore) {
          break;
        }
      } catch (error) {
        const e = error as Error;
        Logger.warn(`bili fav page ${pn} failed: ${e.message}`);
      }
    }
    return items;
  }

  private static stripHtml(text: string): string {
    return text.replace(/<[^>]+>/g, '').replace(/&amp;/g, '&').trim();
  }

  private static parseDurationMs(duration: string): number {
    const parts = duration.split(':');
    if (parts.length !== 2) {
      return 0;
    }
    const minutes = Number(parts[0]);
    const seconds = Number(parts[1]);
    if (Number.isNaN(minutes) || Number.isNaN(seconds)) {
      return 0;
    }
    return (minutes * 60 + seconds) * 1000;
  }
}
