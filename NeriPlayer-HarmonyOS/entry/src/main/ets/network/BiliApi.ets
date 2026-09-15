// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

import { Logger } from '../app/Logger';
import { Constants } from '../app/Constants';
import { SongItem } from '../model/SongItem';
import { MusicPlatform } from '../model/MusicPlatform';
import { HttpClient } from './HttpClient';
import { mixinKeyFrom, wbiKeyFromUrl, buildWbiSignedQuery } from './BiliWbi';
import { BiliAudioOption, selectBiliAudioStream, prioritizeBiliStreamUrls } from './BiliAudioSelector';
import { AudioQualityPolicy } from '../player/AudioQualityPolicy';
import { NetworkStatus } from '../util/NetworkStatus';
import { streamHeadersFor as buildBiliStreamHeaders } from './StreamHeaders';
import {
  BiliFavFolderSummary,
  BiliFavMedia,
  BiliFavPage,
  parseBiliFavFolderList,
  parseBiliFavResourcePage,
  biliFavMediaDedupKey
} from './BiliFavParser';
import { BiliCookieRepository } from '../data/auth/BiliCookieRepository';

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

const FAV_PAGE_SIZE: number = 20;
// Concurrent page fetches when draining a whole favorite folder (mirrors
// Android BiliClient.MAX_PARALLEL_PAGE_REQUESTS).
const MAX_PARALLEL_FAV_PAGE_REQUESTS: number = 6;
const WBI_CACHE_MS: number = 10 * 60 * 1000; // mirrors Android WBI_CACHE_MS
const FAV_FOLDER_WEB_LOCATION: string = '333.1387';

interface BiliNavResponse {
  code?: number;
  data?: BiliNavData;
}

interface BiliNavData {
  wbi_img?: BiliWbiImg;
}

interface BiliWbiImg {
  img_url?: string;
  sub_url?: string;
}

interface BiliViewResponse {
  code?: number;
  message?: string;
  data?: BiliViewData;
}

interface BiliViewData {
  cid?: number;
}

/**
 * Bilibili client (video search + audio stream resolution + favorite
 * folders), following the bilibili-API-collect conventions used by the
 * Android app. Requests carry the persisted login cookie jar when logged in;
 * anonymous requests stay cookie-less on purpose: a freshly issued
 * /x/frontend/finger/spi buvid makes the WBI endpoints soft-reject with
 * code 0 + empty results (2026-08-18 host-verified), while cookie-less
 * requests work fine. search/playurl go through the WBI-signed endpoints:
 * since the 2024 risk control tightening these reject unsigned requests
 * (search answers an HTML page, playurl answers code -400).
 */
export class BiliApi {
  private static wbiMixinKey: string = '';
  private static wbiKeyFetchedAt: number = 0;
  private static wbiKeyPromise: Promise<string> | null = null;
  // playurl rejects bvid-only requests with -400 since 2026; the cid from the
  // view endpoint is stable per video, so cache it for the process lifetime.
  private static cidCache: Map<string, number> = new Map();
  // Anonymous fingerprint seeding (backlog §3.6, Android ensureAnonCookies):
  // cached 1h like upstream; empty until the first logged-out fetch succeeds.
  private static anonCookieHeader: string = '';
  private static anonCookiesAt: number = 0;
  private static readonly ANON_COOKIE_CACHE_MS: number = 3600000;
  private static readonly FINGERPRINT_UA: string =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 13_2_3 like Mac OS X) '
    + 'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.3 '
    + 'Mobile/15E148 Safari/604.1 Edg/114.0.0.0';

  /**
   * Seeds buvid3/buvid4/buvid_fp/buvid_fp_plain/b_lsid into the cookie jar
   * for logged-out sessions (x/frontend/finger/spi): without them bilibili
   * risk control answers -412 on playurl and starves anonymous WBI search.
   * A logged-in jar always wins; failures are logged and never block calls.
   */
  static async ensureAnonymousFingerprint(): Promise<void> {
    try {
      if (BiliCookieRepository.isLoggedIn()) {
        return;
      }
      const now = Date.now();
      if (BiliApi.anonCookieHeader.length > 0
        && now - BiliApi.anonCookiesAt < BiliApi.ANON_COOKIE_CACHE_MS) {
        return;
      }
      const text = await HttpClient.getText(
        `${Constants.BILI_BASE}/x/frontend/finger/spi`,
        { 'User-Agent': BiliApi.FINGERPRINT_UA, 'Referer': 'https://www.bilibili.com/' }
      );
      const parsed = JSON.parse(text) as Record<string, Object>;
      const data = parsed['data'] as Record<string, Object> | undefined;
      if (data === undefined) {
        return;
      }
      const pairs: string[] = [];
      const wanted: [string, string, string][] = [
        ['buvid3', 'b_3', 'buvid3'],
        ['buvid4', 'b_4', 'buvid4'],
        ['buvid_fp', 'buvid_fp', ''],
        ['buvid_fp_plain', 'buvid_fp_plain', ''],
        ['b_lsid', 'b_lsid', '']
      ];
      for (const entry of wanted) {
        const primary = String(data[entry[1]] ?? '');
        const fallback = entry[2].length > 0 ? String(data[entry[2]] ?? '') : '';
        const value = primary.length > 0 ? primary : fallback;
        if (value.length > 0) {
          pairs.push(`${entry[0]}=${value}`);
        }
      }
      if (pairs.length === 0) {
        return;
      }
      BiliApi.anonCookieHeader = pairs.join('; ');
      BiliApi.anonCookiesAt = now;
      HttpClient.seedCookies(`${Constants.BILI_BASE}/`, BiliApi.anonCookieHeader);
      Logger.info('BiliApi: seeded anonymous buvid fingerprint cookies');
    } catch (error) {
      Logger.warn(`BiliApi anonymous fingerprint seeding failed: ${(error as Error).message}`);
    }
  }

  private static biliHeaders(): Record<string, string> {
    const headers: Record<string, string> = {};
    headers['Referer'] = 'https://www.bilibili.com';
    return headers;
  }

  /**
   * Fetches the WBI mixin key from nav with a 10-minute cache and in-flight
   * de-duplication (Android getOrRefreshMixinKey; the WebTicket fallback
   * remains unported — nav is the stable primary source).
   */
  private static async getWbiMixinKey(): Promise<string> {
    if (BiliApi.wbiMixinKey.length > 0 && Date.now() - BiliApi.wbiKeyFetchedAt < WBI_CACHE_MS) {
      return BiliApi.wbiMixinKey;
    }
    if (BiliApi.wbiKeyPromise !== null) {
      return BiliApi.wbiKeyPromise;
    }
    BiliApi.wbiKeyPromise = BiliApi.fetchWbiMixinKey()
      .then((key: string) => {
        BiliApi.wbiMixinKey = key;
        BiliApi.wbiKeyFetchedAt = Date.now();
        return key;
      })
      .finally(() => {
        BiliApi.wbiKeyPromise = null;
      });
    return BiliApi.wbiKeyPromise;
  }

  private static async fetchWbiMixinKey(): Promise<string> {
    const text = await HttpClient.getText(
      `${Constants.BILI_BASE}/x/web-interface/nav`,
      BiliApi.biliHeaders(),
      15000,
      true
    );
    const parsed = JSON.parse(text) as BiliNavResponse;
    const wbiImg = parsed.data?.wbi_img;
    const imgUrl = wbiImg?.img_url ?? '';
    const subUrl = wbiImg?.sub_url ?? '';
    const mixinKey = mixinKeyFrom(wbiKeyFromUrl(imgUrl), wbiKeyFromUrl(subUrl));
    if (mixinKey.length < 32) {
      throw new Error(`Invalid wbi mixin urls from nav (len=${mixinKey.length})`);
    }
    Logger.info('bili wbi mixin key refreshed');
    return mixinKey;
  }

  private static async getWbiSignedUrl(baseUrl: string, params: Map<string, string>): Promise<string> {
    const mixinKey = await BiliApi.getWbiMixinKey();
    const wts = Math.floor(Date.now() / 1000);
    return `${baseUrl}?${buildWbiSignedQuery(params, mixinKey, wts)}`;
  }

  /** Fetches and caches the playback cid for a bvid (wbi/view). */
  static async resolveCid(bvid: string): Promise<number> {
    const cached = BiliApi.cidCache.get(bvid);
    if (cached !== undefined) {
      return cached;
    }
    const params = new Map<string, string>();
    params.set('bvid', bvid);
    const url = await BiliApi.getWbiSignedUrl(`${Constants.BILI_BASE}/x/web-interface/wbi/view`, params);
    const text = await HttpClient.getText(url, BiliApi.biliHeaders(), 15000, true);
    const parsed = JSON.parse(text) as BiliViewResponse;
    const cid = parsed.data?.cid ?? 0;
    if (parsed.code !== 0 || cid <= 0) {
      throw new Error(`bili view failed: code=${parsed.code} bvid=${bvid} message=${parsed.message ?? ''}`);
    }
    BiliApi.cidCache.set(bvid, cid);
    return cid;
  }

  static async search(keyword: string, limit: number = 20): Promise<SongItem[]> {
    await BiliApi.ensureAnonymousFingerprint();
    const items = await BiliApi.searchOnce(keyword, limit);
    if (items.length > 0) {
      return items;
    }
    // Anonymous WBI search is intermittently rejected with an empty result
    // on the first request of a session (risk control warms up per buvid);
    // one delayed retry hides this from users.
    await new Promise<void>((resolve) => setTimeout(resolve, 600));
    return BiliApi.searchOnce(keyword, limit);
  }

  private static async searchOnce(keyword: string, limit: number): Promise<SongItem[]> {
    const params = new Map<string, string>();
    params.set('search_type', 'video');
    params.set('keyword', keyword);
    const url = await BiliApi.getWbiSignedUrl(
      `${Constants.BILI_BASE}/x/web-interface/wbi/search/type`,
      params
    );
    const text = await HttpClient.getText(url, BiliApi.biliHeaders(), 15000, true);
    const response = JSON.parse(text) as BiliSearchResponse;
    const results = response.data?.result ?? [];
    if (results.length === 0) {
      // Business rejections answer HTTP 200 with a non-zero code; keep the
      // code visible so risk-control patterns stay diagnosable.
      Logger.warn(`bili search empty: code=${response.code} results=0 keywordLen=${keyword.length}`);
    }
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
   * Resolves the best DASH audio stream for a bvid through the WBI-signed
   * endpoints (Android getPlayInfoByBvid + requestPlayUrl): wbi/view yields
   * the cid, then wbi/playurl with bvid+cid and fnval=272 DASH|DOLBY /
   * platform=pc answers the DASH manifest. Unsigned playurl answers code
   * -400 since the 2024 risk control tightening.
   */
  static async resolveAudioUrl(bvid: string): Promise<string> {
    await BiliApi.ensureAnonymousFingerprint();
    const cid = await BiliApi.resolveCid(bvid);
    const params = new Map<string, string>();
    params.set('bvid', bvid);
    params.set('cid', `${cid}`);
    params.set('fnval', '272');
    params.set('fnver', '0');
    params.set('fourk', '0');
    params.set('otype', 'json');
    params.set('platform', 'pc');
    const url = await BiliApi.getWbiSignedUrl(`${Constants.BILI_BASE}/x/player/wbi/playurl`, params);
    const text = await HttpClient.getText(url, BiliApi.biliHeaders(), 15000, true);
    const response = JSON.parse(text) as BiliPlayUrlResponse;
    if (response.code !== 0) {
      throw new Error(`requestPlayUrl failed: code=${response.code} bvid=${bvid} cid=${cid} message=${response.message ?? ''}`);
    }
    const audioList = response.data?.dash?.audio ?? [];
    if (audioList.length === 0) {
      Logger.warn(`bili playurl returned no dash audio: bvid=${bvid}`);
      return '';
    }
    // Track choice follows np.audio_quality with the degrade chain, then the
    // CDN URLs are re-ordered upos-first — the highest-bandwidth track on a
    // slow link stutters (audible fragment loops).
    // Track choice follows the per-network audio quality (np.audio_quality_*)
    // with the degrade chain, then the CDN URLs are re-ordered upos-first —
    // the highest-bandwidth track on a slow link stutters (audible fragment
    // loops).
    const options: BiliAudioOption[] = [];
    for (const audio of audioList) {
      const option = new BiliAudioOption();
      option.bandwidth = audio.bandwidth;
      option.baseUrl = audio.baseUrl ?? '';
      option.backupUrl = audio.backupUrl ?? [];
      if (option.bandwidth > 0 && (option.baseUrl.length > 0 || option.backupUrl.length > 0)) {
        options.push(option);
      }
    }
    if (options.length === 0) {
      return '';
    }
    const quality = AudioQualityPolicy.effectiveForPlatform(await NetworkStatus.isWifi(),
      MusicPlatform.BILIBILI);
    const track = selectBiliAudioStream(options, quality);
    if (track === null) {
      return '';
    }
    const urls = prioritizeBiliStreamUrls(track.baseUrl, track.backupUrl);
    let stream = urls.length > 0 ? urls[0] : '';
    if (stream.startsWith('http://')) {
      stream = `https://${stream.substring(7)}`;
    }
    return stream;
  }

  /**
   * HTTP headers Bilibili CDN endpoints expect from stream fetches; the
   * api.bilibili.com cookie jar entry carries the login bundle or the
   * anonymous buvid fingerprint. Null for non-Bilibili hosts.
   */
  static streamHeadersFor(url: string): Record<string, string> | null {
    const headers = buildBiliStreamHeaders(url, HttpClient.getCookies(`${Constants.BILI_BASE}/`));
    return Object.keys(headers).length > 0 ? headers : null;
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
   * Fetches every item of a favorite folder (Android getAllFavFolderItems:
   * stop at !has_more or count reached, failed pages skipped, entries deduped
   * by type:id:bvid). Remaining pages are drained in small parallel chunks so
   * large folders do not pay one full round-trip per page; ordering still
   * follows page order.
   */
  static async getAllFavFolderItems(mediaId: number): Promise<BiliFavMedia[]> {
    const first = await BiliApi.getFavFolderPage(mediaId, 1);
    const items: BiliFavMedia[] = [];
    const seen = new Set<string>();
    BiliApi.appendFavPageItems(items, seen, first.items);
    if (!first.hasMore || first.totalCount <= items.length) {
      return items;
    }
    const totalPages = Math.ceil(first.totalCount / FAV_PAGE_SIZE);
    let stop = false;
    for (let start = 2; start <= totalPages && !stop; start += MAX_PARALLEL_FAV_PAGE_REQUESTS) {
      const pages: number[] = [];
      for (let pn = start; pn < start + MAX_PARALLEL_FAV_PAGE_REQUESTS && pn <= totalPages; pn++) {
        pages.push(pn);
      }
      const fetched = await Promise.all(pages.map((pn: number): Promise<BiliFavPage | null> =>
        BiliApi.getFavFolderPage(mediaId, pn).catch((error: Error): BiliFavPage | null => {
          Logger.warn(`bili fav page ${pn} failed: ${error.message}`);
          return null;
        })
      ));
      for (const page of fetched) {
        if (page === null) {
          continue;
        }
        BiliApi.appendFavPageItems(items, seen, page.items);
        if (!page.hasMore) {
          stop = true;
        }
      }
    }
    return items;
  }

  private static appendFavPageItems(items: BiliFavMedia[], seen: Set<string>, pageItems: BiliFavMedia[]): void {
    for (const item of pageItems) {
      const key = biliFavMediaDedupKey(item);
      if (!seen.has(key)) {
        seen.add(key);
        items.push(item);
      }
    }
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
