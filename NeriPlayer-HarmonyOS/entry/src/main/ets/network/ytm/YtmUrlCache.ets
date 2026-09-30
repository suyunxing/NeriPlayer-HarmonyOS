// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Short-lived googlevideo URL cache porting Android
 * resolvePlayableAudioCacheExpiresAtMs + playableAudioCache semantics:
 *
 * - entry key is "videoId|qualityKey" so a quality change re-resolves;
 * - TTL = min(default 8min, url "expire" seconds - 90s safety margin),
 *   clamped to never outlive the fetch moment;
 * - LRU bounded at 64 entries (Map order = recency, re-get refreshes).
 *
 * The Android reader also rejects cached entries whose bitrate sits below the
 * preferred quality; that check is redundant here because the quality key is
 * part of the cache key.
 */

export const YTM_URL_CACHE_TTL_MS: number = 8 * 60 * 1000;
export const YTM_URL_EXPIRY_SAFETY_MARGIN_MS: number = 90 * 1000;
export const YTM_URL_CACHE_MAX_SIZE: number = 64;

class YtmCachedUrlEntry {
  url: string = '';
  cachedAtMs: number = 0;
  expiresAtMs: number = 0;
}

/** Reads the "expire" query parameter (unix seconds); 0 when absent/invalid. */
export function ytmUrlExpireSeconds(url: string): number {
  const marker = 'expire=';
  let searchFrom = 0;
  while (true) {
    const idx = url.indexOf(marker, searchFrom);
    if (idx < 0) {
      return 0;
    }
    const valueStart = idx + marker.length;
    let end = valueStart;
    while (end < url.length) {
      const ch = url.charAt(end);
      const isDigit = ch >= '0' && ch <= '9';
      if (!isDigit) {
        break;
      }
      end += 1;
    }
    if (end === valueStart) {
      searchFrom = idx + marker.length;
      continue;
    }
    // Reject when the match is a suffix of a longer key (e.g. xexpire=).
    const prev = idx > 0 ? url.charAt(idx - 1) : '';
    const prevIsKeyChar =
      (prev >= 'a' && prev <= 'z') || (prev >= 'A' && prev <= 'Z') || (prev >= '0' && prev <= '9');
    if (prevIsKeyChar) {
      searchFrom = idx + marker.length;
      continue;
    }
    const value = Number(url.substring(valueStart, end));
    return Number.isFinite(value) && value > 0 ? value : 0;
  }
}

/** Android resolvePlayableAudioCacheExpiresAtMs (TEST: expire - margin, floor cachedAt). */
export function computeYtmUrlExpiresAtMs(url: string, cachedAtMs: number): number {
  const defaultExpiry = cachedAtMs + YTM_URL_CACHE_TTL_MS;
  const expireSeconds = ytmUrlExpireSeconds(url);
  if (expireSeconds <= 0) {
    return defaultExpiry;
  }
  const streamExpiry = Math.max(expireSeconds * 1000 - YTM_URL_EXPIRY_SAFETY_MARGIN_MS, cachedAtMs);
  return Math.min(defaultExpiry, streamExpiry);
}

export class YtmUrlCache {
  private entries: Map<string, YtmCachedUrlEntry> = new Map<string, YtmCachedUrlEntry>();

  static cacheKey(videoId: string, qualityKey: string): string {
    return `${videoId}|${qualityKey}`;
  }

  /** Returns the cached URL or null on miss/expiry; hits refresh LRU order. */
  get(videoId: string, qualityKey: string, nowMs: number): string | null {
    const key = YtmUrlCache.cacheKey(videoId, qualityKey);
    const entry = this.entries.get(key);
    if (entry === undefined) {
      return null;
    }
    if (nowMs >= entry.expiresAtMs) {
      this.entries.delete(key);
      return null;
    }
    this.entries.delete(key);
    this.entries.set(key, entry);
    return entry.url;
  }

  put(videoId: string, qualityKey: string, url: string, nowMs: number): void {
    if (url.length === 0) {
      return;
    }
    const key = YtmUrlCache.cacheKey(videoId, qualityKey);
    const entry = new YtmCachedUrlEntry();
    entry.url = url;
    entry.cachedAtMs = nowMs;
    entry.expiresAtMs = computeYtmUrlExpiresAtMs(url, nowMs);
    this.entries.delete(key);
    this.entries.set(key, entry);
    while (this.entries.size > YTM_URL_CACHE_MAX_SIZE) {
      const oldestKeys = Array.from(this.entries.keys());
      if (oldestKeys.length === 0) {
        break;
      }
      this.entries.delete(oldestKeys[0]);
    }
  }

  clear(): void {
    this.entries.clear();
  }

  /** Drops every quality variant cached for the video (URL re-sign path). */
  evictVideo(videoId: string): void {
    const prefix = `${videoId}|`;
    const stale: string[] = [];
    this.entries.forEach((_entry, key) => {
      if (key.startsWith(prefix)) {
        stale.push(key);
      }
    });
    for (const key of stale) {
      this.entries.delete(key);
    }
  }

  size(): number {
    return this.entries.size;
  }
}
