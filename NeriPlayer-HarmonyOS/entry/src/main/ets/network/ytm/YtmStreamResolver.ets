// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

import { Logger } from '../../app/Logger';
import {
  YtmPlayerResponseNode,
  collectYtmAudioCandidates,
  parseYtmPlayability
} from './YtmPlayerParser';
import {
  YtmFormatSelection,
  YtmQualityTier,
  selectYtmDirectAudioCandidate,
  ytmQualityTierFromSetting
} from './YtmFormatSelector';
import { YtmUrlCache } from './YtmUrlCache';
import { YtmClientHealthTracker } from './YtmClientHealthTracker';
import { YtmClientCatalog, YtmClientProfile, YTM_IOS_DOWNGRADED_VERSION } from './YtmClientCatalog';
import { YtmHttpError, YtmPlayerFetcher, defaultYtmPlayerFetcher } from './YtmStreamClient';

/**
 * M6 chain facade: health-filtered client chain (IOS -> tvhtml5_downgraded)
 * with a one-shot version-drift downgrade retry, playability/format error
 * classification and the M6.1 short cache. The decision core takes an
 * injected fetcher so the local hypium suite can drive the whole chain.
 *
 * Error kinds: login_required / unplayable / needs_decrypt (cipher-only
 * response, solver deferred to M6.3) / network / parse / empty. Age/region/
 * bot-wall shapes are surfaced as restriction hints inside the message.
 */

export type YtmStreamErrorKind =
  | 'network'
  | 'login_required'
  | 'unplayable'
  | 'needs_decrypt'
  | 'empty'
  | 'parse';

export class YtmStreamError extends Error {
  readonly kind: YtmStreamErrorKind;

  constructor(kind: YtmStreamErrorKind, message: string) {
    super(`[${kind}] ${message}`);
    this.kind = kind;
  }
}

/** Maps playability status+reason onto a human restriction hint ('' = none). */
export function classifyYtmRestriction(status: string, reason: string): string {
  const text = `${status} ${reason}`.toLowerCase();
  if (text.includes('age')) {
    return 'age-restricted content requires sign-in';
  }
  if (text.includes('country') || text.includes('region') || text.includes('location')) {
    return 'content unavailable in this region';
  }
  if (text.includes('bot') || text.includes('confirm you')) {
    return 'bot verification wall (client rotation may help)';
  }
  if (text.includes('private')) {
    return 'private video';
  }
  if (text.includes('embed')) {
    return 'embedded playback disabled';
  }
  return '';
}

function isNonRetryableClientError(httpCode: number): boolean {
  if (httpCode < 400 || httpCode >= 500) {
    return false;
  }
  return httpCode !== 408 && httpCode !== 429;
}

export class YtmStreamResolver {
  private static cache: YtmUrlCache = new YtmUrlCache();
  private static health: YtmClientHealthTracker = new YtmClientHealthTracker();

  /** Resolves a playable direct audio URL for a videoId; throws YtmStreamError. */
  static async resolveStreamUrl(
    videoId: string,
    qualitySettingKey: string | null
  ): Promise<string> {
    if (videoId.length === 0) {
      throw new YtmStreamError('empty', 'videoId is empty');
    }
    const tier = ytmQualityTierFromSetting(qualitySettingKey);
    const qualityKey = qualitySettingKey ?? '';
    const nowMs = Date.now();
    const cached = YtmStreamResolver.cache.get(videoId, qualityKey, nowMs);
    if (cached !== null) {
      return cached;
    }
    const url = await YtmStreamResolver.resolveWithClientChain(
      videoId,
      tier,
      defaultYtmPlayerFetcher,
      Date.now()
    );
    YtmStreamResolver.cache.put(videoId, qualityKey, url, Date.now());
    return url;
  }

  /**
   * Decision core: walk the health-filtered chain, retry an HTTP-400 IOS
   * attempt once on the downgraded version, and aggregate per-client
   * failures into a single YtmStreamError (kind of the deepest attempt).
   */
  static async resolveWithClientChain(
    videoId: string,
    tier: YtmQualityTier,
    fetcher: YtmPlayerFetcher,
    nowMs: number
  ): Promise<string> {
    const chain = YtmStreamResolver.health.selectUsableChain(
      YtmClientCatalog.playerChain(),
      (profile: YtmClientProfile) => profile.key,
      nowMs
    );
    const failures: string[] = [];
    let lastKind: YtmStreamErrorKind = 'network';
    let lastMessage = `no usable player client for ${videoId}`;
    for (const profile of chain) {
      try {
        return await YtmStreamResolver.attemptWithProfile(profile, videoId, tier, fetcher, nowMs);
      } catch (error) {
        const e = error as YtmStreamError;
        failures.push(`${profile.key}@${profile.clientVersion}: ${e.message}`);
        lastKind = e.kind;
        lastMessage = e.message;
      }
    }
    throw new YtmStreamError(lastKind, `${videoId} failed all clients (${failures.join(' ; ')})`);
  }

  private static async attemptWithProfile(
    profile: YtmClientProfile,
    videoId: string,
    tier: YtmQualityTier,
    fetcher: YtmPlayerFetcher,
    nowMs: number
  ): Promise<string> {
    let text: string;
    try {
      text = await YtmStreamResolver.fetchWithVersionDriftRetry(profile, videoId, fetcher);
    } catch (error) {
      const e = error as YtmHttpError;
      if (isNonRetryableClientError(e.httpCode)) {
        YtmStreamResolver.health.recordRejection(profile.key, nowMs);
      }
      throw new YtmStreamError('network', `player request failed via ${profile.key}: ${e.message}`);
    }
    YtmStreamResolver.health.recordSuccess(profile.key);
    return YtmStreamResolver.parseAndSelect(profile, text, videoId, tier);
  }

  /**
   * HTTP 400 on the current IOS version is treated as version drift and
   * retried once on the pinned downgrade (probe-style trick); any other
   * failure (including the retry) propagates as YtmHttpError.
   */
  private static async fetchWithVersionDriftRetry(
    profile: YtmClientProfile,
    videoId: string,
    fetcher: YtmPlayerFetcher
  ): Promise<string> {
    try {
      return await fetcher(profile, videoId);
    } catch (error) {
      const e = error as YtmHttpError;
      const isDriftSignal = e instanceof YtmHttpError && e.httpCode === 400;
      if (!isDriftSignal || profile.clientName !== 'IOS') {
        throw e;
      }
      Logger.warn(
        `YtmStreamResolver: ${profile.key}@${profile.clientVersion} rejected (400), retrying on ${YTM_IOS_DOWNGRADED_VERSION}`
      );
      return fetcher(profile.withVersion(YTM_IOS_DOWNGRADED_VERSION), videoId);
    }
  }

  private static parseAndSelect(
    profile: YtmClientProfile,
    text: string,
    videoId: string,
    tier: YtmQualityTier
  ): string {
    let root: YtmPlayerResponseNode;
    try {
      root = JSON.parse(text) as YtmPlayerResponseNode;
    } catch (error) {
      const e = error as Error;
      throw new YtmStreamError(
        'parse',
        `player response via ${profile.key} is not JSON: ${e.message}`
      );
    }
    const playability = parseYtmPlayability(root);
    if (!playability.ok) {
      const hint = classifyYtmRestriction(playability.status, playability.reason);
      const hintSuffix = hint.length > 0 ? ` [${hint}]` : '';
      const suffix = playability.reason.length > 0 ? `: ${playability.reason}` : '';
      const kind: YtmStreamErrorKind =
        playability.status === 'LOGIN_REQUIRED' ? 'login_required' : 'unplayable';
      throw new YtmStreamError(
        kind,
        `player not playable via ${profile.key} (${playability.status})${suffix}${hintSuffix}`
      );
    }
    const candidates = collectYtmAudioCandidates(root);
    const selection: YtmFormatSelection = selectYtmDirectAudioCandidate(candidates, tier);
    if (selection.needsDecrypt) {
      throw new YtmStreamError(
        'needs_decrypt',
        `${profile.key} returned signatureCipher-only formats; decryption fallback is not implemented (M6.3 seam)`
      );
    }
    const selected = selection.selected;
    if (selected === null || selected.directUrl.length === 0) {
      throw new YtmStreamError('empty', `no audio formats for ${videoId} via ${profile.key}`);
    }
    // Never log the URL itself: googlevideo links carry auth tokens.
    Logger.info(
      `YtmStreamResolver: ${videoId} via ${profile.key}@${profile.clientVersion} -> itag ${selected.itag} ${Math.round(selected.bitrate / 1000)}kbps`
    );
    return selected.directUrl;
  }

  static resetForTest(): void {
    YtmStreamResolver.cache.clear();
    YtmStreamResolver.health.resetForTest();
  }
}
