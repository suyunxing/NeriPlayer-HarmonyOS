import { Constants } from '../app/Constants';
import { SongItem } from '../model/SongItem';
import { AudioQualityPolicy } from '../player/AudioQualityPolicy';
import { NetworkStatus } from '../util/NetworkStatus';
import { HttpClient } from './HttpClient';
import { YtmStreamResolver } from './ytm/YtmStreamResolver';
import { YtmStreamClient } from './ytm/YtmStreamClient';
import { parseYtmSearchResponse } from './ytm/YtmSearchParser';

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

  static async search(keyword: string, limit: number = 20): Promise<SongItem[]> {
    // Prefer the live bootstrap key (cached 10 min inside YtmStreamClient);
    // the built-in Constants key is only the degraded fallback.
    const bootstrap = await YtmStreamClient.getBootstrap(Date.now());
    const apiKey = bootstrap.apiKey.length > 0 ? bootstrap.apiKey : Constants.YTM_WEB_API_KEY;
    const url =
      `${Constants.YTM_BASE}/youtubei/v1/search?key=${apiKey}&prettyPrint=false`;
    const client: YtmClient = {
      clientName: 'WEB_REMIX',
      clientVersion: YouTubeMusicApi.WEB_REMIX_VERSION,
      hl: 'en',
      gl: 'US'
    };
    const context: YtmContext = { client: client };
    const body: YtmSearchRequest = {
      context: context,
      params: 'EgWKAQIIAWoKEAoQCRADEAA%3D',
      query: keyword
    };
    const text = await HttpClient.postJson(url, JSON.stringify(body));
    return parseYtmSearchResponse(text, limit);
  }

  /** M6.1 primary path: IOS client direct stream (see network/ytm/). */
  static async resolveStream(videoId: string): Promise<string> {
    const quality = AudioQualityPolicy.effective(await NetworkStatus.isWifi());
    return YtmStreamResolver.resolveStreamUrl(videoId, quality);
  }

}
