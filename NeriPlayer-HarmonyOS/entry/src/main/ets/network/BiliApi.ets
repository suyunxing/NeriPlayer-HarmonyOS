import { Logger } from '../app/Logger';
import { Constants } from '../app/Constants';
import { SongItem } from '../model/SongItem';
import { MusicPlatform } from '../model/MusicPlatform';
import { HttpClient } from './HttpClient';
import { BiliCookieRepository } from '../data/auth/BiliCookieRepository';
import { mixinKeyFrom, wbiKeyFromUrl, buildWbiSignedQuery } from './BiliWbi';
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
  data?: BiliPlayData;
}

interface BiliPlayData {
  dash?: BiliDash;
}

interface BiliDash {
  audio?: BiliDashAudio[];
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
  data?: BiliViewData;
}

interface BiliViewData {
  cid?: number;
}

/**
 * Bilibili client (video search + audio stream resolution + favorite
 * folders), following the bilibili-API-collect conventions used by the
 * Android app. Requests carry the persisted login cookie jar when logged in,
 * or anonymous buvid fingerprint cookies otherwise (Android getEffectiveCookies).
 * search/playurl go through the WBI-signed endpoints: since the 2024 risk
 * control tightening these reject unsigned requests (search answers an HTML
 * page, playurl answers code -400).
 */
export class BiliApi {
  private static anonCookieFetchedAt: number = 0;
  private static wbiMixinKey: string = '';
  private static wbiKeyFetchedAt: number = 0;
  private static wbiKeyPromise: Promise<string> | null = null;

  private static biliHeaders(): Record<string, string> {
    const headers: Record<string, string> = {};
    headers['Referer'] = 'https://www.bilibili.com';
    return headers;
  }

  /**
   * Makes sure the api.bilibili.com cookie jar has something usable: the
   * login bundle is seeded by BiliCookieRepository, so this only fetches the
   * anonymous fingerprint (/x/frontend/finger/spi) when logged out. Failures
   * degrade silently to cookie-less requests.
   */
  private static async ensureRequestCookies(): Promise<void> {
    if (BiliCookieRepository.isLoggedIn()) {
      return;
    }
    const jar = HttpClient.getCookies(`${Constants.BILI_BASE}/`);
    if (jar.indexOf('buvid3=') >= 0 && Date.now() - BiliApi.anonCookieFetchedAt < ANON_COOKIE_TTL_MS) {
      return;
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
        Logger.info(`bili anon cookies seeded: ${pairs.length} entries`);
      }
    } catch (error) {
      const e = error as Error;
      Logger.warn(`bili anon cookie fetch failed (continuing without): ${e.message}`);
    }
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
    await BiliApi.ensureRequestCookies();
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

  /** Fetches the playback cid for a bvid (wbi/view, Android fetchVideoBasicInfo). */
  private static async fetchCid(bvid: string): Promise<number> {
    const params = new Map<string, string>();
    params.set('bvid', bvid);
    const url = await BiliApi.getWbiSignedUrl(`${Constants.BILI_BASE}/x/web-interface/wbi/view`, params);
    const text = await HttpClient.getText(url, BiliApi.biliHeaders(), 15000, true);
    const parsed = JSON.parse(text) as BiliViewResponse;
    const cid = parsed.data?.cid ?? 0;
    if (parsed.code !== 0 || cid <= 0) {
      throw new Error(`bili view failed: code=${parsed.code} bvid=${bvid}`);
    }
    return cid;
  }

  static async search(keyword: string, limit: number = 20): Promise<SongItem[]> {
    const params = new Map<string, string>();
    params.set('search_type', 'video');
    params.set('keyword', keyword);
    const url = await BiliApi.getWbiSignedUrl(
      `${Constants.BILI_BASE}/x/web-interface/wbi/search/type`,
      params
    );
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
   * Resolves the best DASH audio stream for a bvid through the WBI-signed
   * endpoints (Android getPlayInfoByBvid + requestPlayUrl): wbi/view yields
   * the cid, then wbi/playurl with bvid+cid and fnval=272 DASH|DOLBY /
   * platform=pc answers the DASH manifest. Unsigned playurl answers code
   * -400 since the 2024 risk control tightening.
   */
  static async resolveAudioUrl(bvid: string): Promise<string> {
    await BiliApi.ensureRequestCookies();
    const cid = await BiliApi.fetchCid(bvid);
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
      throw new Error(`requestPlayUrl failed: code=${response.code} bvid=${bvid} cid=${cid}`);
    }
    const audioList = response.data?.dash?.audio ?? [];
    if (audioList.length === 0) {
      return '';
    }
    let best = audioList[0];
    for (const audio of audioList) {
      if (audio.bandwidth > best.bandwidth) {
        best = audio;
      }
    }
    let stream = best.baseUrl ?? '';
    if (stream.length === 0 && best.backupUrl !== undefined && best.backupUrl.length > 0) {
      stream = best.backupUrl[0];
    }
    if (stream.startsWith('http://')) {
      stream = `https://${stream.substring(7)}`;
    }
    return stream;
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
