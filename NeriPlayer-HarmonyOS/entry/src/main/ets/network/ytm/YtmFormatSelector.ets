import { YtmAudioCandidate } from './YtmPlayerParser';

/**
 * Quality-tier audio format selection, porting Android
 * YouTubeMusicPlaybackRepository semantics:
 *
 * - candidates sort by bitrate desc, sampleRate desc, mime preference
 *   (m4a=2 > webm=1 > other) desc, contentLength desc;
 * - the preferred quality tier reorders the sorted list: LOW prefers the
 *   lowest bitrate, MEDIUM/HIGH prioritize the first candidate at/above
 *   96/128 kbps, VERY_HIGH keeps the highest first;
 * - selection considers only direct-URL candidates (the IOS primary path);
 *   cipher-only responses surface a needsDecrypt flag instead (M6.2 seam).
 */

export enum YtmQualityTier {
  LOW = 0,
  MEDIUM = 1,
  HIGH = 2,
  VERY_HIGH = 3
}

/** Android YouTubeMusicPlaybackQuality.fromSetting (np.audio_quality values). */
export function ytmQualityTierFromSetting(settingKey: string | null): YtmQualityTier {
  const key = (settingKey ?? '').toLowerCase();
  if (key === 'low' || key === 'standard') {
    return YtmQualityTier.LOW;
  }
  if (key === 'medium') {
    return YtmQualityTier.MEDIUM;
  }
  if (key === 'high' || key === 'higher') {
    return YtmQualityTier.HIGH;
  }
  return YtmQualityTier.VERY_HIGH;
}

/** Minimum bitrate (kbps) a candidate must reach for the tier; 0 = none. */
export function ytmTierMinBitrateKbps(tier: YtmQualityTier): number {
  switch (tier) {
    case YtmQualityTier.LOW:
      return 0;
    case YtmQualityTier.MEDIUM:
      return 96;
    case YtmQualityTier.HIGH:
      return 128;
    case YtmQualityTier.VERY_HIGH:
    default:
      return 160;
  }
}

/** Android satisfiesYouTubePlaybackQuality. */
export function satisfiesYtmQualityTier(candidate: YtmAudioCandidate, tier: YtmQualityTier): boolean {
  const minKbps = ytmTierMinBitrateKbps(tier);
  if (minKbps === 0) {
    return true;
  }
  return Math.round(candidate.bitrate / 1000) >= minKbps;
}

export function ytmMimePreferenceScore(mimeType: string): number {
  const lower = mimeType.toLowerCase();
  if (lower.startsWith('audio/mp4')) {
    return 2;
  }
  if (lower.startsWith('audio/webm')) {
    return 1;
  }
  return 0;
}

function compareCandidatesDescending(a: YtmAudioCandidate, b: YtmAudioCandidate): number {
  if (a.bitrate !== b.bitrate) {
    return b.bitrate - a.bitrate;
  }
  if (a.audioSampleRateHz !== b.audioSampleRateHz) {
    return b.audioSampleRateHz - a.audioSampleRateHz;
  }
  const mimeScoreA = ytmMimePreferenceScore(a.mimeType);
  const mimeScoreB = ytmMimePreferenceScore(b.mimeType);
  if (mimeScoreA !== mimeScoreB) {
    return mimeScoreB - mimeScoreA;
  }
  return b.contentLength - a.contentLength;
}

/**
 * Android prioritizeThresholdCandidate: within the ascending list, move the
 * first candidate at/above the threshold to the front; when none qualifies,
 * return the descending order.
 */
function prioritizeThresholdCandidate(
  sortedAscending: YtmAudioCandidate[],
  thresholdBitrate: number
): YtmAudioCandidate[] {
  let preferredIndex = -1;
  for (let i = 0; i < sortedAscending.length; i++) {
    if (sortedAscending[i].bitrate >= thresholdBitrate) {
      preferredIndex = i;
      break;
    }
  }
  if (preferredIndex < 0) {
    return sortedAscending.slice().reverse();
  }
  const head = sortedAscending.slice(preferredIndex);
  const tail = sortedAscending.slice(0, preferredIndex).reverse();
  return head.concat(tail);
}

/** Android orderCandidatesByQualityTier. */
export function orderYtmCandidatesByQualityTier(
  candidates: YtmAudioCandidate[],
  tier: YtmQualityTier
): YtmAudioCandidate[] {
  if (candidates.length === 0) {
    return [];
  }
  const sortedDescending = candidates.slice().sort(compareCandidatesDescending);
  switch (tier) {
    case YtmQualityTier.LOW:
      return sortedDescending.slice().reverse();
    case YtmQualityTier.MEDIUM:
      return prioritizeThresholdCandidate(sortedDescending.slice().reverse(), 96000);
    case YtmQualityTier.HIGH:
      return prioritizeThresholdCandidate(sortedDescending.slice().reverse(), 128000);
    case YtmQualityTier.VERY_HIGH:
    default:
      return sortedDescending;
  }
}

export class YtmFormatSelection {
  selected: YtmAudioCandidate | null = null;
  /** True when only signatureCipher candidates exist (needs the M6.2 solver). */
  needsDecrypt: boolean = false;
}

/**
 * Picks the best direct-URL audio candidate for the preferred quality.
 * Mirrors resolveFormatUrl's direct-url-first rule; cipher candidates are
 * never selected on this path.
 */
export function selectYtmDirectAudioCandidate(
  candidates: YtmAudioCandidate[],
  tier: YtmQualityTier
): YtmFormatSelection {
  const result = new YtmFormatSelection();
  const direct: YtmAudioCandidate[] = [];
  for (const candidate of candidates) {
    if (candidate.directUrl.length > 0) {
      direct.push(candidate);
    }
  }
  if (direct.length === 0) {
    for (const candidate of candidates) {
      if (candidate.hasCipher) {
        result.needsDecrypt = true;
        break;
      }
    }
    return result;
  }
  const ordered = orderYtmCandidatesByQualityTier(direct, tier);
  result.selected = ordered.length > 0 ? ordered[0] : null;
  return result;
}
