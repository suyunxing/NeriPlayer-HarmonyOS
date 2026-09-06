import { Constants } from '../../app/Constants';
import { Logger } from '../../app/Logger';
import { HttpClient } from '../HttpClient';
import { YtmBootstrapData, parseYtmBootstrapHtml } from './YtmPlayerParser';
import { YtmClientCatalog, YtmClientProfile } from './YtmClientCatalog';

/**
 * Anonymous youtubei/v1/player access for the M6 chain (D2 decision).
 *
 * Bootstrap mirrors the Android client + probe flow: fetch the music.youtube
 * home page, extract INNERTUBE_API_KEY/VISITOR_DATA/STS, cache for 10 minutes.
 * When the page is unreachable or the markers are missing we degrade to the
 * built-in public web key without visitorData/STS - the spike verified the
 * player API accepts that key for IOS contexts too, and yt-dlp-style IOS
 * requests run without STS.
 */

const YTM_BOOTSTRAP_TTL_MS: number = 10 * 60 * 1000;
const YTM_MINIMAL_COOKIE: string = 'CONSENT=YES+cb.20210328-17-p0.en+FX+419';

interface YtmPlayerClientContext {
  clientName: string;
  clientVersion: string;
  platform: string;
  hl: string;
  gl: string;
  userAgent: string;
  timeZone: string;
  utcOffsetMinutes: number;
  deviceMake: string;
  deviceModel: string;
  osName: string;
  osVersion: string;
  visitorData?: string;
}

interface YtmPlayerRequestContext {
  useSsl: boolean;
  internalExperimentFlags: string[];
  consistencyTokenJars: string[];
}

interface YtmPlayerUserContext {
  lockedSafetyMode: boolean;
}

interface YtmContentPlaybackContext {
  html5Preference: string;
  signatureTimestamp?: number;
}

interface YtmPlayerContextEnvelope {
  client: YtmPlayerClientContext;
  request: YtmPlayerRequestContext;
  user: YtmPlayerUserContext;
}

interface YtmPlaybackContextEnvelope {
  contentPlaybackContext: YtmContentPlaybackContext;
}

interface YtmPlayerRequestBody {
  context: YtmPlayerContextEnvelope;
  videoId: string;
  contentCheckOk: boolean;
  racyCheckOk: boolean;
  playbackContext: YtmPlaybackContextEnvelope;
}

/** Transport error carrying the HTTP status; 0 = network-layer failure. */
export class YtmHttpError extends Error {
  readonly httpCode: number;

  constructor(httpCode: number, message: string) {
    super(message);
    this.httpCode = httpCode;
  }
}

export class YtmStreamClient {
  private static bootstrap: YtmBootstrapData | null = null;
  private static bootstrapFetchedAtMs: number = 0;
  private static bootstrapInFlight: Promise<YtmBootstrapData> | null = null;

  static async getBootstrap(nowMs: number): Promise<YtmBootstrapData> {
    if (
      YtmStreamClient.bootstrap !== null &&
      nowMs - YtmStreamClient.bootstrapFetchedAtMs < YTM_BOOTSTRAP_TTL_MS
    ) {
      return YtmStreamClient.bootstrap;
    }
    if (YtmStreamClient.bootstrapInFlight !== null) {
      return YtmStreamClient.bootstrapInFlight;
    }
    const task = YtmStreamClient.fetchBootstrap()
      .then((data: YtmBootstrapData) => {
        YtmStreamClient.bootstrap = data;
        YtmStreamClient.bootstrapFetchedAtMs = nowMs;
        return data;
      })
      .finally(() => {
        YtmStreamClient.bootstrapInFlight = null;
      });
    YtmStreamClient.bootstrapInFlight = task;
    return task;
  }

  /** Fetches and parses the bootstrap page; degrades to the public web key. */
  private static async fetchBootstrap(): Promise<YtmBootstrapData> {
    try {
      const bootstrapHeaders: Record<string, string> = {
        'User-Agent': HttpClient.DEFAULT_UA,
        'Accept-Language': 'en-US,en;q=0.9',
        'Cookie': YTM_MINIMAL_COOKIE
      };
      const html = await HttpClient.getText(`${Constants.YTM_BASE}/`, bootstrapHeaders);
      const parsed = parseYtmBootstrapHtml(html);
      if (parsed !== null && parsed.apiKey.length > 0) {
        Logger.debug('YtmStreamClient: bootstrap extracted from home page');
        return parsed;
      }
      Logger.warn('YtmStreamClient: bootstrap markers missing, degrading to built-in key');
    } catch (error) {
      const e = error as Error;
      Logger.warn(
        `YtmStreamClient: bootstrap fetch failed (${e.message}), degrading to built-in key`
      );
    }
    const fallback = new YtmBootstrapData();
    fallback.apiKey = Constants.YTM_WEB_API_KEY;
    return fallback;
  }

  static buildPlayerUrl(apiKey: string, videoId: string): string {
    return `https://www.youtube.com/youtubei/v1/player?prettyPrint=false&id=${videoId}&key=${apiKey}`;
  }

  static buildPlayerPayload(
    profile: YtmClientProfile,
    videoId: string,
    bootstrap: YtmBootstrapData
  ): string {
    const client: YtmPlayerClientContext = {
      clientName: profile.clientName,
      clientVersion: profile.clientVersion,
      platform: profile.platform,
      hl: 'en',
      gl: 'US',
      userAgent: profile.userAgent,
      timeZone: 'UTC',
      utcOffsetMinutes: -new Date().getTimezoneOffset(),
      deviceMake: profile.deviceMake,
      deviceModel: profile.deviceModel,
      osName: profile.osName,
      osVersion: profile.osVersion
    };
    if (bootstrap.visitorData.length > 0) {
      client.visitorData = bootstrap.visitorData;
    }
    const requestContext: YtmPlayerRequestContext = {
      useSsl: true,
      internalExperimentFlags: [],
      consistencyTokenJars: []
    };
    const userContext: YtmPlayerUserContext = { lockedSafetyMode: false };
    const envelope: YtmPlayerContextEnvelope = {
      client: client,
      request: requestContext,
      user: userContext
    };
    const playback: YtmContentPlaybackContext = { html5Preference: 'HTML5_PREF_WANTS' };
    if (bootstrap.signatureTimestamp > 0) {
      playback.signatureTimestamp = bootstrap.signatureTimestamp;
    }
    const playbackEnvelope: YtmPlaybackContextEnvelope = { contentPlaybackContext: playback };
    const body: YtmPlayerRequestBody = {
      context: envelope,
      videoId: videoId,
      contentCheckOk: true,
      racyCheckOk: true,
      playbackContext: playbackEnvelope
    };
    return JSON.stringify(body);
  }

  static buildPlayerHeaders(
    profile: YtmClientProfile,
    bootstrap: YtmBootstrapData
  ): Record<string, string> {
    const headers: Record<string, string> = {
      'User-Agent': profile.userAgent,
      'Content-Type': 'application/json',
      'Accept-Language': 'en-US,en;q=0.9',
      'Cookie': YTM_MINIMAL_COOKIE,
      'X-Goog-AuthUser': '0',
      'X-YouTube-Client-Name': profile.clientId,
      'X-YouTube-Client-Version': profile.clientVersion,
      'X-Goog-Api-Format-Version': '2',
      'Origin': profile.origin,
      'Referer': `${profile.origin}/`
    };
    if (bootstrap.visitorData.length > 0) {
      headers['X-Goog-Visitor-Id'] = bootstrap.visitorData;
    }
    return headers;
  }

  /**
   * POSTs the anonymous player request for the given profile and returns the
   * raw JSON text. Transport/HTTP failures throw YtmHttpError (httpCode 0
   * for network-layer errors) so the resolver can classify them.
   */
  static async fetchPlayerResponseText(
    profile: YtmClientProfile,
    videoId: string,
    nowMs: number
  ): Promise<string> {
    const bootstrap = await YtmStreamClient.getBootstrap(nowMs);
    const url = YtmStreamClient.buildPlayerUrl(bootstrap.apiKey, videoId);
    const headers = YtmStreamClient.buildPlayerHeaders(profile, bootstrap);
    const payload = YtmStreamClient.buildPlayerPayload(profile, videoId, bootstrap);
    try {
      return await HttpClient.postJson(url, payload, 20000, headers);
    } catch (error) {
      const e = error as Error;
      throw new YtmHttpError(YtmStreamClient.parseHttpCode(e.message), e.message);
    }
  }

  /** Extracts the status from HttpClient's "HTTP <code> for ..." messages. */
  private static parseHttpCode(message: string): number {
    if (message.startsWith('HTTP ')) {
      const rest = message.substring(5);
      let end = 0;
      while (end < rest.length && rest.charAt(end) >= '0' && rest.charAt(end) <= '9') {
        end += 1;
      }
      if (end > 0) {
        const code = Number(rest.substring(0, end));
        if (Number.isFinite(code) && code > 0) {
          return code;
        }
      }
    }
    return 0;
  }

  static resetForTest(): void {
    YtmStreamClient.bootstrap = null;
    YtmStreamClient.bootstrapFetchedAtMs = 0;
    YtmStreamClient.bootstrapInFlight = null;
  }
}

/** Default executor binding so the resolver stays a pure decision layer. */
export type YtmPlayerFetcher = (
  profile: YtmClientProfile,
  videoId: string
) => Promise<string>;

export function defaultYtmPlayerFetcher(profile: YtmClientProfile, videoId: string): Promise<string> {
  return YtmStreamClient.fetchPlayerResponseText(profile, videoId, Date.now());
}

export const YTM_CATALOG_CHAIN: YtmClientProfile[] = YtmClientCatalog.playerChain();
