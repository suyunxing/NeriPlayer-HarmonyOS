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
import { YtmStreamClient } from './YtmStreamClient';

/**
 * Facade of the M6.1 primary path: IOS client -> playability check ->
 * direct-URL format selection -> short cache. Zero JS runtime dependency
 * (D2 decision, docs/YTMUSIC_M60_SPIKE.md).
 *
 * Error kinds follow the porting plan: login_required / unplayable cover
 * playability rejections, needs_decrypt marks cipher-only responses (M6.2
 * fallback seam), plus network/parse/empty.
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

export class YtmStreamResolver {
  private static cache: YtmUrlCache = new YtmUrlCache();

  /** Resolves a playable direct audio URL for a videoId; throws YtmStreamError. */
  static async resolveStreamUrl(videoId: string, qualitySettingKey: string | null): Promise<string> {
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
    let root: YtmPlayerResponseNode;
    let text: string;
    try {
      text = await YtmStreamClient.fetchPlayerResponseText(videoId, nowMs);
    } catch (error) {
      const e = error as Error;
      throw new YtmStreamError('network', `player request failed for ${videoId}: ${e.message}`);
    }
    try {
      root = JSON.parse(text) as YtmPlayerResponseNode;
    } catch (error) {
      const e = error as Error;
      throw new YtmStreamError('parse', `player response is not JSON: ${e.message}`);
    }
    const playability = parseYtmPlayability(root);
    if (!playability.ok) {
      const suffix = playability.reason.length > 0 ? `: ${playability.reason}` : '';
      const kind: YtmStreamErrorKind =
        playability.status === 'LOGIN_REQUIRED' ? 'login_required' : 'unplayable';
      throw new YtmStreamError(kind, `player not playable (${playability.status})${suffix}`);
    }
    const candidates = collectYtmAudioCandidates(root);
    const selection: YtmFormatSelection = selectYtmDirectAudioCandidate(candidates, tier);
    if (selection.needsDecrypt) {
      throw new YtmStreamError(
        'needs_decrypt',
        'only signatureCipher formats returned; the tvhtml5_downgraded decrypt fallback is not implemented (M6.2)'
      );
    }
    const selected = selection.selected;
    if (selected === null || selected.directUrl.length === 0) {
      throw new YtmStreamError('empty', `no audio formats for ${videoId}`);
    }
    // Never log the URL itself: googlevideo links carry auth tokens.
    Logger.info(
      `YtmStreamResolver: ${videoId} -> itag ${selected.itag} ${Math.round(selected.bitrate / 1000)}kbps (${qualityKey})`
    );
    YtmStreamResolver.cache.put(videoId, qualityKey, selected.directUrl, Date.now());
    return selected.directUrl;
  }

  static resetForTest(): void {
    YtmStreamResolver.cache.clear();
    YtmStreamClient.resetForTest();
  }
}
