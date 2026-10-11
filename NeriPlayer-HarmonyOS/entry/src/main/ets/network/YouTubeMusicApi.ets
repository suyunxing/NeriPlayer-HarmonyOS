// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

import { Constants } from '../app/Constants';
import { SongItem } from '../model/SongItem';
import { MusicPlatform } from '../model/MusicPlatform';
import { AudioQualityPolicy } from '../player/AudioQualityPolicy';
import { NetworkStatus } from '../util/NetworkStatus';
import { HttpClient } from './HttpClient';
import { YtmStreamResolver } from './ytm/YtmStreamResolver';
import { YtmStreamClient } from './ytm/YtmStreamClient';
import { parseYtmSearchResponse } from './ytm/YtmSearchParser';
import {
  YtmCreatorBrowseEndpoint,
  YtmCreatorDetail,
  YtmCreatorItemsPage,
  YtmCreatorSummary,
  extractYtmSearchContinuation,
  parseYtmCreatorDetail,
  parseYtmCreatorItemsContinuation,
  parseYtmCreatorItemsPage,
  parseYtmCreatorSearchResults
} from './ytm/YtmCreatorParser';

interface YtmClient {
  clientName: string;
  clientVersion: string;
  hl: string;
  gl: string;
}

interface YtmContext {
  client: YtmClient;
}

interface YtmSearchRequest {
  context: YtmContext;
  params: string;
  query: string;
}

/** 上游 4c085185 YouTubeMusicSearchFilter 三档；songs 沿用鸿蒙已验证常量。 */
export enum YtmSearchFilter {
  SONGS = 'songs',
  VIDEOS = 'videos',
  CREATORS = 'creators'
}

function searchFilterParams(filter: YtmSearchFilter): string {
  switch (filter) {
    case YtmSearchFilter.VIDEOS:
      return 'EgWKAQIQAWoKEAkQChAFEAMQBA%3D%3D';
    case YtmSearchFilter.CREATORS:
      return 'EgWKAQIgAWoKEAkQChAFEAMQBA%3D%3D';
    default:
      return 'EgWKAQIIAWoKEAoQCRADEAA%3D';
  }
}

/** 上游 YOUTUBE_MUSIC_CONTINUATION_PAGE_LIMIT：搜索/分页收集的页数上限。 */
const YTM_CONTINUATION_PAGE_LIMIT: number = 80;

/**
 * YouTube Music client. Stream resolution uses the M6.1 primary path: the
 * anonymous IOS player client returns direct URLs (D2 decision, no JS
 * runtime); ciphered fallbacks are deferred to M6.2+.
 */
export class YouTubeMusicApi {
  // Verified 2026-08-20 via proxy: the music/search endpoint answers 404 for
  // anonymous WEB_REMIX; the generic /youtubei/v1/search with the songs
  // filter returns the same music-shaped rows. Keep this pinned to a version
  // observed live (M6.0 bootstrap probe).
  static readonly WEB_REMIX_VERSION: string = '1.20260811.15.00';

  private static musicContext(): YtmContext {
    const client: YtmClient = {
      clientName: 'WEB_REMIX',
      clientVersion: YouTubeMusicApi.WEB_REMIX_VERSION,
      hl: 'en',
      gl: 'US'
    };
    return { client: client };
  }

  private static async requestUrl(path: string): Promise<string> {
    // Prefer the live bootstrap key (cached 10 min inside YtmStreamClient);
    // the built-in Constants key is only the degraded fallback.
    const bootstrap = await YtmStreamClient.getBootstrap(Date.now());
    const apiKey = bootstrap.apiKey.length > 0 ? bootstrap.apiKey : Constants.YTM_WEB_API_KEY;
    return `${Constants.YTM_BASE}/youtubei/v1/${path}?key=${apiKey}&prettyPrint=false`;
  }

  /** youtubei/v1/browse POST（上游 postMusicBrowse；匿名 bootstrap，无登录态体系）。 */
  private static async postMusicBrowse(payload: Record<string, Object>): Promise<Record<string, Object>> {
    const url = await YouTubeMusicApi.requestUrl('browse');
    const body: Record<string, Object> = {};
    body.context = YouTubeMusicApi.musicContext() as Object;
    for (const key of Object.keys(payload)) {
      body[key] = payload[key];
    }
    const text = await HttpClient.postJson(url, JSON.stringify(body));
    return JSON.parse(text) as Record<string, Object>;
  }

  static async search(
    keyword: string,
    limit: number = 20,
    filter: YtmSearchFilter = YtmSearchFilter.SONGS
  ): Promise<SongItem[]> {
    const url = await YouTubeMusicApi.requestUrl('search');
    const body: YtmSearchRequest = {
      context: YouTubeMusicApi.musicContext(),
      params: searchFilterParams(filter),
      query: keyword
    };
    const text = await HttpClient.postJson(url, JSON.stringify(body));
    return parseYtmSearchResponse(text, limit);
  }

  /**
   * 上游 searchCreators + collectSearchResults：creators 过滤搜索，按
   * browseId 去重、跨 continuation 收集到 limit；首页失败抛错、续页失败中断
   * 返回已收集部分。
   */
  static async searchCreators(keyword: string, limit: number = 20): Promise<YtmCreatorSummary[]> {
    const query = keyword.trim();
    if (query.length === 0) {
      return [];
    }
    const requestedLimit = Math.max(1, limit);
    const items: YtmCreatorSummary[] = [];
    const seenKeys = new Set<string>();
    let continuation = '';
    let page = 0;
    while (page < YTM_CONTINUATION_PAGE_LIMIT && items.length < requestedLimit) {
      const url = await YouTubeMusicApi.requestUrl('search');
      const body: Record<string, Object> = {};
      body.context = YouTubeMusicApi.musicContext() as Object;
      body.query = query;
      body.params = searchFilterParams(YtmSearchFilter.CREATORS);
      if (continuation.length > 0) {
        body.continuation = continuation;
      }
      let text: string;
      try {
        text = await HttpClient.postJson(url, JSON.stringify(body));
      } catch (error) {
        if (page === 0) {
          throw error as Error;
        }
        break;
      }
      const root = JSON.parse(text) as Record<string, Object>;
      for (const summary of parseYtmCreatorSearchResults(root, requestedLimit - items.length)) {
        if (!seenKeys.has(summary.browseId)) {
          seenKeys.add(summary.browseId);
          items.push(summary);
        }
      }
      continuation = extractYtmSearchContinuation(root);
      if (continuation.length === 0) {
        break;
      }
      page++;
    }
    return items.length > requestedLimit ? items.slice(0, requestedLimit) : items;
  }

  /** 上游 getCreatorDetail：browseId → browse → parseCreatorDetail。 */
  static async getCreatorDetail(creator: YtmCreatorSummary): Promise<YtmCreatorDetail> {
    if (creator.browseId.trim().length === 0) {
      throw new Error('YouTube Music creator browseId is required');
    }
    const payload: Record<string, Object> = {};
    payload.browseId = creator.browseId;
    const root = await YouTubeMusicApi.postMusicBrowse(payload);
    return parseYtmCreatorDetail(root, creator);
  }

  /** 上游 getCreatorItems：分区 moreEndpoint → browse → parseCreatorItemsPage。 */
  static async getCreatorItems(
    endpoint: YtmCreatorBrowseEndpoint,
    fallbackTitle: string
  ): Promise<YtmCreatorItemsPage> {
    if (endpoint.browseId.trim().length === 0) {
      throw new Error('YouTube Music creator items browseId is required');
    }
    const payload: Record<string, Object> = {};
    payload.browseId = endpoint.browseId;
    if (endpoint.params.length > 0) {
      payload.params = endpoint.params;
    }
    const root = await YouTubeMusicApi.postMusicBrowse(payload);
    return parseYtmCreatorItemsPage(root, fallbackTitle);
  }

  /** 上游 getCreatorItemsContinuation：{continuation} → browse → 解析续页。 */
  static async getCreatorItemsContinuation(continuation: string): Promise<YtmCreatorItemsPage> {
    if (continuation.trim().length === 0) {
      throw new Error('YouTube Music creator items continuation is required');
    }
    const payload: Record<string, Object> = {};
    payload.continuation = continuation;
    const root = await YouTubeMusicApi.postMusicBrowse(payload);
    return parseYtmCreatorItemsContinuation(root);
  }

  /** M6.1 primary path: IOS client direct stream (see network/ytm/). */
  static async resolveStream(videoId: string): Promise<string> {
    const quality = AudioQualityPolicy.effectiveForPlatform(await NetworkStatus.isWifi(),
      MusicPlatform.YOUTUBE_MUSIC);
    return YtmStreamResolver.resolveStreamUrl(videoId, quality);
  }

  /** 裸 videoId → 可播放 SongItem（探索页链接解析；标题/封面留给自动匹配补全）。 */
  static songFromVideoId(videoId: string): SongItem {
    const song = new SongItem(0, '', '', '', 0, 0, '',
      `${Constants.YOUTUBE_MUSIC_MEDIA_PREFIX}${videoId}`, MusicPlatform.YOUTUBE_MUSIC);
    song.channelId = Constants.YOUTUBE_MUSIC_IDENTITY_ALBUM;
    song.audioId = videoId;
    return song;
  }

}
