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
import {
  BiliUploaderProfile,
  BiliUploaderVideoPage,
  BiliUploaderContentPage,
  BiliCollectionArchivePage,
  BiliSeriesArchivePage,
  parseBiliUploaderProfile,
  parseBiliUploaderVideoPage,
  parseBiliUploaderContentPage,
  parseBiliCollectionArchivePage,
  parseBiliSeriesArchivePage
} from './BiliUploaderSpace';

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
  /** 服务端分页元数据（numPages 从 1 计）。 */
  numPages?: number;
  page?: number;
}

/** 搜索分页结果（上游 BiliVideoSearchPage 的鸿蒙子集）。 */
export class BiliSearchPage {
  items: SongItem[] = [];
  page: number = 1;
  numPages: number = 1;
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
  aid?: number;
  cid?: number;
  bvid?: string;
  title?: string;
  pic?: string;
  duration?: number;
  owner?: BiliViewOwner;
  pages?: BiliViewPageRaw[];
  ugc_season?: BiliUgcSeasonRaw;
}

interface BiliViewOwner {
  mid?: number;
  name?: string;
}

interface BiliViewPageRaw {
  cid?: number;
  page?: number;
  part?: string;
  duration?: number;
}

interface BiliViewEpisodeRaw {
  bvid?: string;
  title?: string;
  cover?: string;
  page?: BiliViewPageRaw;
  duration?: number;
}

interface BiliUgcSeasonRaw {
  id?: number;
  mid?: number;
  title?: string;
  episodes?: BiliViewEpisodeRaw[];
}

/** 分 P 摘要（链接解析用）。 */
export class BiliVideoPage {
  page: number = 1;
  cid: number = 0;
  title: string = '';
  durationMs: number = 0;
}

/** 合集（ugc_season）单集摘要。 */
export class BiliSeasonEpisode {
  bvid: string = '';
  title: string = '';
  durationMs: number = 0;
  coverUrl: string = '';
}

/** wbi/view 的结构化摘要（上游 VideoBasicInfo 的鸿蒙子集）。 */
export class BiliVideoInfo {
  bvid: string = '';
  aid: number = 0;
  title: string = '';
  coverUrl: string = '';
  durationMs: number = 0;
  ownerMid: number = 0;
  ownerName: string = '';
  pages: BiliVideoPage[] = [];
  seasonId: number = 0;
  seasonOwnerMid: number = 0;
  seasonTitle: string = '';
  seasonEpisodes: BiliSeasonEpisode[] = [];
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

  /**
   * wbi/view 完整摘要（探索页链接解析，上游 a8440275）：标题/UP 主/封面、
   * 分 P 列表与 ugc_season 合集单集。bvid 缺席时按 aid 查（av 号链接）。
   */
  static async getVideoInfo(bvid: string, avid: number = 0): Promise<BiliVideoInfo> {
    const params = new Map<string, string>();
    if (bvid.length > 0) {
      params.set('bvid', bvid);
    } else if (avid > 0) {
      params.set('aid', `${avid}`);
    }
    const url = await BiliApi.getWbiSignedUrl(`${Constants.BILI_BASE}/x/web-interface/wbi/view`, params);
    const text = await HttpClient.getText(url, BiliApi.biliHeaders(), 15000, true);
    const response = JSON.parse(text) as BiliViewResponse;
    const data = response.data;
    if (response.code !== 0 || data === undefined) {
      throw new Error(`bili view failed: code=${response.code} bvid=${bvid} message=${response.message ?? ''}`);
    }
    const info = new BiliVideoInfo();
    info.bvid = data.bvid ?? bvid;
    info.aid = data.aid ?? 0;
    info.title = BiliApi.stripHtml(data.title ?? '');
    info.coverUrl = (data.pic ?? '').replace('http://', 'https://');
    info.durationMs = (data.duration ?? 0) * 1000;
    info.ownerMid = data.owner?.mid ?? 0;
    info.ownerName = BiliApi.stripHtml(data.owner?.name ?? '');
    const rawPages = data.pages ?? [];
    for (const raw of rawPages) {
      const page = new BiliVideoPage();
      page.page = raw.page ?? 0;
      page.cid = raw.cid ?? 0;
      page.title = BiliApi.stripHtml(raw.part ?? '');
      page.durationMs = (raw.duration ?? 0) * 1000;
      if (page.cid > 0) {
        info.pages.push(page);
      }
    }
    const season = data.ugc_season;
    if (season !== undefined && (season.id ?? 0) > 0) {
      info.seasonId = season.id ?? 0;
      info.seasonOwnerMid = season.mid ?? 0;
      info.seasonTitle = BiliApi.stripHtml(season.title ?? '');
      for (const episode of season.episodes ?? []) {
        const entry = new BiliSeasonEpisode();
        entry.bvid = episode.bvid ?? '';
        entry.title = BiliApi.stripHtml(episode.title ?? '');
        entry.durationMs = (episode.page?.duration ?? episode.duration ?? 0) * 1000;
        entry.coverUrl = (episode.cover ?? '').replace('http://', 'https://');
        if (entry.bvid.length > 0 && !info.seasonEpisodes.some((seen: BiliSeasonEpisode): boolean => seen.bvid === entry.bvid)) {
          info.seasonEpisodes.push(entry);
        }
      }
    }
    const cid = data.cid ?? 0;
    if (cid > 0) {
      BiliApi.cidCache.set(info.bvid, cid);
    }
    return info;
  }

  static async search(keyword: string, limit: number = 20): Promise<SongItem[]> {
    const page = await BiliApi.searchPage(keyword, limit, 1);
    return page.items;
  }

  /**
   * 上游 searchVideos(keyword, page)：wbi/search/type 带 page 参数；
   * 返回本页条目与 numPages（hasMore = page < numPages）。
   */
  static async searchPage(keyword: string, limit: number, page: number): Promise<BiliSearchPage> {
    await BiliApi.ensureAnonymousFingerprint();
    let result = await BiliApi.searchOnce(keyword, limit, page);
    if (result.items.length > 0 || page > 1) {
      return result;
    }
    // Anonymous WBI search is intermittently rejected with an empty result
    // on the first request of a session (risk control warms up per buvid);
    // one delayed retry hides this from users.
    await new Promise<void>((resolve) => setTimeout(resolve, 600));
    result = await BiliApi.searchOnce(keyword, limit, page);
    if (result.items.length === 0) {
      Logger.warn(`bili search empty after retry: page=${page} keywordLen=${keyword.length}`);
    }
    return result;
  }

  private static async searchOnce(keyword: string, limit: number, page: number): Promise<BiliSearchPage> {
    const params = new Map<string, string>();
    params.set('search_type', 'video');
    params.set('keyword', keyword);
    params.set('page', `${page}`);
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
    const out = new BiliSearchPage();
    out.items = items;
    const numPages = response.data?.numPages ?? 0;
    out.page = page;
    out.numPages = numPages > 0 ? numPages : (items.length > 0 ? page : 0);
    return out;
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

  // ---------- 评论端点（UPSTREAM_SYNC_PLAN F-3，上游 #432/#476 BiliCommentApi） ----------

  /**
   * 评论缓存会话键：登录 cookie（SESSDATA）存在才非空，账号切换后自动隔离
   * 缓存；值只作缓存键，不入日志。
   */
  static biliCommentSessionKey(): string | null {
    const sessdata = HttpClient.getCookiesMap(`${Constants.BILI_BASE}/`).get('SESSDATA') ?? '';
    return sessdata.length > 0 ? sessdata : null;
  }

  /**
   * 视频评论列表（/x/v2/reply，type=1 视频）。sort：0 最新 / 1 热门。
   * 匿名也可读，但可能被风控截断为全零分页（由 BiliCommentMapper 防御）。
   */
  static async getVideoComments(aid: number, page: number, pageSize: number,
    sort: number): Promise<string> {
    if (!(aid > 0) || page < 1 || pageSize < 1 || pageSize > 49) {
      throw new Error('invalid video comments request');
    }
    const url = `${Constants.BILI_BASE}/x/v2/reply?type=1&oid=${aid}` +
      `&pn=${page}&ps=${pageSize}&sort=${sort}`;
    return HttpClient.getText(url, BiliApi.biliHeaders(), 15000, true);
  }

  /** 楼中楼回复列表（/x/v2/reply/reply）。 */
  static async getVideoCommentReplies(aid: number, rootId: string,
    page: number, pageSize: number): Promise<string> {
    if (!(aid > 0) || !(Number(rootId) > 0) || page < 1 || pageSize < 1 || pageSize > 20) {
      throw new Error('invalid video comment replies request');
    }
    const url = `${Constants.BILI_BASE}/x/v2/reply/reply?type=1&oid=${aid}` +
      `&root=${rootId}&pn=${page}&ps=${pageSize}`;
    return HttpClient.getText(url, BiliApi.biliHeaders(), 15000, true);
  }

  /**
   * 点赞 / 取消点赞评论（/x/v2/reply/action）。需要 SESSDATA + bili_jct；
   * 未登录时返回 code=-101 的 JSON（与上游 loginRequired() 一致，由仓库层
   * 转 PERMISSION 错误），成功以业务 code 0 判定。
   */
  static async setVideoCommentLiked(aid: number, commentId: string,
    liked: boolean): Promise<string> {
    if (!(aid > 0) || !(Number(commentId) > 0)) {
      throw new Error('invalid video comment like request');
    }
    const csrf = await BiliApi.requireCommentCsrf();
    if (csrf === null) {
      return '{"code":-101}';
    }
    const form: Record<string, string> = {
      'type': '1',
      'oid': `${aid}`,
      'rpid': commentId,
      'action': liked ? '1' : '0',
      'csrf': csrf
    };
    return HttpClient.postForm(`${Constants.BILI_BASE}/x/v2/reply/action`,
      form, 15000, BiliApi.biliHeaders(), true);
  }

  /**
   * 发表评论 / 楼中楼回复（/x/v2/reply/add）。需要 SESSDATA + bili_jct；
   * 网络结果不确定时不自动重发（发评无幂等键，重复发出由用户自行核对）。
   */
  static async sendVideoComment(aid: number, content: string,
    rootId: string | null, parentId: string | null): Promise<string> {
    if (!(aid > 0) || content.trim().length === 0) {
      throw new Error('invalid video comment send request');
    }
    if ((rootId === null) !== (parentId === null)) {
      throw new Error('reply target must be complete');
    }
    const csrf = await BiliApi.requireCommentCsrf();
    if (csrf === null) {
      return '{"code":-101}';
    }
    const form: Record<string, string> = {
      'type': '1',
      'oid': `${aid}`,
      'message': content,
      'root': rootId ?? '0',
      'parent': parentId ?? '0',
      'plat': '1',
      'statistics': '{"appId":100,"platform":5}',
      'gaia_source': 'main_web',
      'csrf': csrf
    };
    return HttpClient.postForm(`${Constants.BILI_BASE}/x/v2/reply/add`,
      form, 15000, BiliApi.biliHeaders(), true);
  }

  /**
   * 评论写操作的前置：确保匿名指纹已种下并校验登录 cookie（SESSDATA +
   * bili_jct 缺一不可，后者即 csrf）。未登录返回 null。
   */
  private static async requireCommentCsrf(): Promise<string | null> {
    await BiliApi.ensureAnonymousFingerprint();
    const cookies = HttpClient.getCookiesMap(`${Constants.BILI_BASE}/`);
    const sessdata = cookies.get('SESSDATA') ?? '';
    const csrf = cookies.get('bili_jct') ?? '';
    if (sessdata.length === 0 || csrf.length === 0) {
      return null;
    }
    return csrf;
  }

  // ---- UP 主空间（上游 e95b2ef9）----

  /** Uploader archive page size (Android UPLOADER_VIDEO_PAGE_SIZE). */
  private static readonly UPLOADER_VIDEO_PAGE_SIZE: number = 30;
  /** Uploader collection/series page size (Android UPLOADER_CONTENT_PAGE_SIZE). */
  private static readonly UPLOADER_CONTENT_PAGE_SIZE: number = 20;
  /** Collection/series content page size (Android COLLECTION_ARCHIVE_PAGE_SIZE). */
  private static readonly COLLECTION_ARCHIVE_PAGE_SIZE: number = 30;

  /**
   * Android requireSuccessfulData: HTTP 200 body must carry code=0 with a
   * data object, otherwise the call throws with the endpoint's business
   * message (e.g. acc/info answers -404 for a hidden uploader).
   */
  private static async requireSuccessfulData(url: string, what: string): Promise<Record<string, Object>> {
    await BiliApi.ensureAnonymousFingerprint();
    const text = await HttpClient.getText(url, BiliApi.biliHeaders(), 15000, true);
    const root = JSON.parse(text) as Record<string, Object>;
    const code = Number(root['code'] ?? -1);
    const dataRaw = root['data'];
    if (code !== 0 || dataRaw === undefined || dataRaw === null) {
      throw new Error(`bili ${what} failed: code=${code} message=${String(root['message'] ?? '')}`);
    }
    return dataRaw as Record<string, Object>;
  }

  /** x/space/wbi/acc/info: uploader profile (name/avatar/sign/banner). */
  static async getUploaderProfile(mid: number): Promise<BiliUploaderProfile> {
    if (mid <= 0) {
      throw new Error('Uploader mid must be positive');
    }
    const params = new Map<string, string>();
    params.set('mid', `${mid}`);
    params.set('platform', 'web');
    params.set('web_location', '1550101');
    const url = await BiliApi.getWbiSignedUrl(
      `${Constants.BILI_BASE}/x/space/wbi/acc/info`, params);
    const data = await BiliApi.requireSuccessfulData(url, 'uploader profile');
    return parseBiliUploaderProfile(data, mid);
  }

  /** x/space/wbi/arc/search: uploader archive videos, newest first by default. */
  static async getUploaderVideos(
    mid: number,
    page: number = 1,
    pageSize: number = BiliApi.UPLOADER_VIDEO_PAGE_SIZE,
    order: string = 'pubdate'
  ): Promise<BiliUploaderVideoPage> {
    if (mid <= 0) {
      throw new Error('Uploader mid must be positive');
    }
    const resolvedPage = Math.max(1, Math.floor(page));
    const resolvedPageSize = Math.min(Math.max(1, Math.floor(pageSize)), BiliApi.UPLOADER_VIDEO_PAGE_SIZE);
    const params = new Map<string, string>();
    params.set('mid', `${mid}`);
    params.set('pn', `${resolvedPage}`);
    params.set('ps', `${resolvedPageSize}`);
    params.set('order', order);
    const url = await BiliApi.getWbiSignedUrl(
      `${Constants.BILI_BASE}/x/space/wbi/arc/search`, params);
    const data = await BiliApi.requireSuccessfulData(url, 'uploader videos');
    return parseBiliUploaderVideoPage(data, resolvedPage, resolvedPageSize, mid);
  }

  /** x/polymer/web-space/seasons_series_list: uploader collections + series. */
  static async getUploaderContents(
    mid: number,
    page: number = 1,
    pageSize: number = BiliApi.UPLOADER_CONTENT_PAGE_SIZE
  ): Promise<BiliUploaderContentPage> {
    if (mid <= 0) {
      throw new Error('Uploader mid must be positive');
    }
    const resolvedPage = Math.max(1, Math.floor(page));
    const resolvedPageSize = Math.min(Math.max(1, Math.floor(pageSize)), BiliApi.UPLOADER_CONTENT_PAGE_SIZE);
    const params = new Map<string, string>();
    params.set('mid', `${mid}`);
    params.set('page_num', `${resolvedPage}`);
    params.set('page_size', `${resolvedPageSize}`);
    params.set('web_location', '333.999');
    const url = await BiliApi.getWbiSignedUrl(
      `${Constants.BILI_BASE}/x/polymer/web-space/seasons_series_list`, params);
    const data = await BiliApi.requireSuccessfulData(url, 'uploader collections and series');
    return parseBiliUploaderContentPage(data, resolvedPage, resolvedPageSize, mid);
  }

  /**
   * x/polymer/web-space/seasons_archives_list: one page of a collection's
   * (合集) videos. The meta block gives the canonical title/total.
   */
  static async getCollectionArchives(
    mid: number,
    seasonId: number,
    page: number = 1,
    pageSize: number = BiliApi.COLLECTION_ARCHIVE_PAGE_SIZE
  ): Promise<BiliCollectionArchivePage> {
    if (mid <= 0 || seasonId <= 0) {
      throw new Error('Collection id must be positive');
    }
    const resolvedPage = Math.max(1, Math.floor(page));
    const resolvedPageSize = Math.min(Math.max(1, Math.floor(pageSize)), BiliApi.COLLECTION_ARCHIVE_PAGE_SIZE);
    const params = new Map<string, string>();
    params.set('mid', `${mid}`);
    params.set('season_id', `${seasonId}`);
    params.set('sort_reverse', 'false');
    params.set('page_num', `${resolvedPage}`);
    params.set('page_size', `${resolvedPageSize}`);
    params.set('web_location', '333.999');
    const url = await BiliApi.getWbiSignedUrl(
      `${Constants.BILI_BASE}/x/polymer/web-space/seasons_archives_list`, params);
    const data = await BiliApi.requireSuccessfulData(url, 'collection archives');
    return parseBiliCollectionArchivePage(data, seasonId, mid);
  }

  /** x/series/archives: one page of a series' (系列) videos, newest first. */
  static async getSeriesArchives(
    mid: number,
    seriesId: number,
    page: number = 1,
    pageSize: number = BiliApi.COLLECTION_ARCHIVE_PAGE_SIZE
  ): Promise<BiliSeriesArchivePage> {
    if (mid <= 0 || seriesId <= 0) {
      throw new Error('Series id must be positive');
    }
    const resolvedPage = Math.max(1, Math.floor(page));
    const resolvedPageSize = Math.min(Math.max(1, Math.floor(pageSize)), BiliApi.COLLECTION_ARCHIVE_PAGE_SIZE);
    const url =
      `${Constants.BILI_BASE}/x/series/archives?mid=${mid}&series_id=${seriesId}` +
      `&only_normal=true&sort=desc&pn=${resolvedPage}&ps=${resolvedPageSize}`;
    const data = await BiliApi.requireSuccessfulData(url, 'series archives');
    return parseBiliSeriesArchivePage(data, resolvedPage, resolvedPageSize);
  }
}
