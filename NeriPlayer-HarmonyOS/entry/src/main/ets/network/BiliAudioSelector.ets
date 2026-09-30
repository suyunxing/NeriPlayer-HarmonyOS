// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Pure Bilibili DASH audio-track selection, ported from Android
 * data/platform/bili/BiliAudioSelector.kt (simplified: the HarmonyOS client
 * only parses the regular dash.audio group — no dolby/flac tag groups yet).
 *
 * Blindly taking the highest-bandwidth track (e.g. ~320kbps or a lossless
 * stream) starves the buffer on slow networks and the player audibly
 * stutters/loops fragments; instead the preferred quality maps to a bitrate
 * band and degrades down the chain until a track fits. No platform imports.
 */

export class BiliAudioOption {
  bandwidth: number = 0; // bits per second, as reported by playurl
  baseUrl: string = '';
  backupUrl: string[] = [];

  get bitrateKbps(): number {
    return Math.round(this.bandwidth / 1000);
  }
}

enum BiliQuality {
  HIRES = 0,
  LOSSLESS = 1,
  HIGH = 2,
  MEDIUM = 3,
  LOW = 4
}

const QUALITY_MIN_KBPS: number[] = [1000, 500, 180, 120, 60]; // index = BiliQuality
/** np.audio_quality setting key -> Bilibili preference (Android fromKey). */
const QUALITY_BY_SETTING_KEY: Map<string, BiliQuality> = new Map<string, BiliQuality>([
  ['hires', BiliQuality.HIRES],
  ['lossless', BiliQuality.LOSSLESS],
  ['exhigh', BiliQuality.HIGH],
  ['high', BiliQuality.MEDIUM],
  ['standard', BiliQuality.LOW]
]);

function degradeChain(from: BiliQuality): BiliQuality[] {
  const chain: BiliQuality[] = [];
  for (let q = from; q <= BiliQuality.LOW; q++) {
    chain.push(q);
  }
  return chain;
}

/**
 * Picks the audio track for the preferred quality: the highest track inside
 * the quality's bitrate band, degrading down the chain when the band has no
 * track; falls back to the highest overall (Android selectStreamByPreference).
 */
export function selectBiliAudioStream(
  options: BiliAudioOption[],
  preferredSettingKey: string
): BiliAudioOption | null {
  if (options.length === 0) {
    return null;
  }
  const sorted = options.slice(0, options.length).sort((a: BiliAudioOption, b: BiliAudioOption) => b.bandwidth - a.bandwidth);
  const preferred = QUALITY_BY_SETTING_KEY.get(preferredSettingKey) ?? BiliQuality.LOW;
  for (const quality of degradeChain(preferred)) {
    const lower = QUALITY_MIN_KBPS[quality];
    // Band is [min, next-higher-tier min); HIRES tops out unbounded.
    const upper = quality === BiliQuality.HIRES ? Number.MAX_SAFE_INTEGER : QUALITY_MIN_KBPS[quality - 1];
    for (const option of sorted) {
      if (option.bitrateKbps >= lower && option.bitrateKbps < upper) {
        return option;
      }
    }
  }
  return sorted[0];
}

function hostOf(url: string): string {
  const start = url.indexOf('://');
  const rest = start >= 0 ? url.substring(start + 3) : url;
  const slash = rest.indexOf('/');
  return (slash >= 0 ? rest.substring(0, slash) : rest).toLowerCase();
}

function scoreBiliStreamUrl(url: string): number {
  const host = hostOf(url);
  if (host.startsWith('upos-') && host.indexOf('bilivideo.com') >= 0) {
    return 3;
  }
  if (host.indexOf('bilivideo.com') >= 0) {
    return 2;
  }
  if (host.endsWith('.mountaintoys.cn')) {
    return 1;
  }
  return 0;
}

class UrlScoreEntry {
  url: string = '';
  index: number = 0;
}

/**
 * Orders the primary + backup CDN URLs: upos bilivideo mirrors first (the
 * stable primary CDN), other bilivideo hosts next, mountaintoys edge last;
 * original relative order kept inside each tier (Android
 * prioritizeBiliStreamUrls).
 */
export function prioritizeBiliStreamUrls(primaryUrl: string, backupUrls: string[]): string[] {
  const seen = new Set<string>();
  const entries: UrlScoreEntry[] = [];
  const candidates: string[] = [primaryUrl, ...backupUrls];
  for (const url of candidates) {
    const trimmed = url.trim();
    if (trimmed.length === 0 || seen.has(trimmed)) {
      continue;
    }
    seen.add(trimmed);
    const entry = new UrlScoreEntry();
    entry.url = trimmed;
    entry.index = entries.length;
    entries.push(entry);
  }
  entries.sort((a: UrlScoreEntry, b: UrlScoreEntry) =>
    scoreBiliStreamUrl(b.url) - scoreBiliStreamUrl(a.url) || a.index - b.index);
  const out: string[] = [];
  for (const entry of entries) {
    out.push(entry.url);
  }
  return out;
}
