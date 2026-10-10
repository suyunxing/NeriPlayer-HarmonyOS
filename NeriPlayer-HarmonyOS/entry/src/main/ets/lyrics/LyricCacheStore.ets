// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer),
// persistent lyrics caching (#349), adapted to the SchemaStore-backed table
// model used by the playback cache ledger.

import { LyricLine } from '../model/LyricLine';

/** Where a lyric result came from; persisted with the entry so a cache hit
 * still knows which source-level baseline offset applies. */
export enum LyricSourceTag {
  MATCHED = 'matched',
  NETEASE = 'netease',
  LRCLIB = 'lrclib'
}

/** Parses a stored source tag; unknown values fall back to LRCLIB. */
export function parseLyricSourceTag(raw: string): LyricSourceTag {
  if (raw === LyricSourceTag.MATCHED) {
    return LyricSourceTag.MATCHED;
  }
  if (raw === LyricSourceTag.NETEASE) {
    return LyricSourceTag.NETEASE;
  }
  return LyricSourceTag.LRCLIB;
}

export class LyricCacheEntry {
  stableKey: string = '';
  source: LyricSourceTag = LyricSourceTag.LRCLIB;
  lines: LyricLine[] = [];
  lastUsedAt: number = 0;

  constructor(stableKey: string, source: LyricSourceTag, lines: LyricLine[], lastUsedAt: number) {
    this.stableKey = stableKey;
    this.source = source;
    this.lines = lines;
    this.lastUsedAt = lastUsedAt;
  }
}

/** Fixed LRU capacity; the user-facing control is the on/off toggle. */
export const DEFAULT_LYRIC_CACHE_ENTRIES: number = 200;

/** Declared JSON shapes so toJson() object literals satisfy strict ArkTS. */
class LyricCacheEntryJson {
  k: string = '';
  s: string = LyricSourceTag.LRCLIB;
  l: Object[] = [];
  u: number = 0;
}

class LyricCacheTableJson {
  entries: LyricCacheEntryJson[] = [];
}

/**
 * Pure LRU table of resolved lyric lines per song stable key (upstream #349:
 * replays and offline sessions show lyrics without re-fetching). Lines are
 * stored as compact [timeMs, text, translated, phonetic, endTimeMs] tuples;
 * word timings are not persisted (the word-karaoke renderer is gone and the
 * payload would double). No @ohos imports so eviction stays unit-testable.
 */
export class LyricCacheStore {
  private entries: LyricCacheEntry[] = [];

  static fromJson(json: string): LyricCacheStore | null {
    let raw: Record<string, Object>;
    try {
      raw = JSON.parse(json) as Record<string, Object>;
    } catch (error) {
      return null;
    }
    const store = new LyricCacheStore();
    const list = raw['entries'];
    if (list === undefined || !Array.isArray(list)) {
      return store;
    }
    for (const item of list as Object[]) {
      const record = item as Record<string, Object>;
      const key = String(record['k'] ?? '');
      if (key.length === 0) {
        continue;
      }
      const entry = new LyricCacheEntry(
        key,
        parseLyricSourceTag(String(record['s'] ?? LyricSourceTag.LRCLIB)),
        LyricCacheStore.parseLines(record['l']),
        Number(record['u'] ?? 0)
      );
      if (entry.lines.length > 0) {
        store.entries.push(entry);
      }
    }
    return store;
  }

  private static parseLines(raw: Object | undefined): LyricLine[] {
    const lines: LyricLine[] = [];
    if (raw === undefined || !Array.isArray(raw)) {
      return lines;
    }
    for (const tuple of raw as Object[]) {
      if (!Array.isArray(tuple)) {
        continue;
      }
      const parts = tuple as Object[];
      if (parts.length < 2) {
        continue;
      }
      const timeMs = Number(parts[0] ?? 0);
      const text = String(parts[1] ?? '');
      if (!Number.isFinite(timeMs) || text.length === 0) {
        continue;
      }
      const line = new LyricLine(timeMs, text, String(parts[2] ?? ''), String(parts[3] ?? ''));
      line.endTimeMs = Number(parts[4] ?? 0);
      lines.push(line);
    }
    return lines;
  }

  toJson(): string {
    const compact: LyricCacheEntryJson[] = [];
    for (const entry of this.entries) {
      const tuples: Object[] = [];
      for (const line of entry.lines) {
        const tuple: Object[] = [line.timeMs, line.text, line.translated, line.phonetic, line.endTimeMs];
        tuples.push(tuple);
      }
      const item: LyricCacheEntryJson = {
        k: entry.stableKey,
        s: entry.source,
        l: tuples,
        u: entry.lastUsedAt
      };
      compact.push(item);
    }
    const table: LyricCacheTableJson = { entries: compact };
    return JSON.stringify(table);
  }

  size(): number {
    return this.entries.length;
  }

  find(stableKey: string): LyricCacheEntry | null {
    for (const entry of this.entries) {
      if (entry.stableKey === stableKey) {
        return entry;
      }
    }
    return null;
  }

  /** Cache-hit lookup; a hit refreshes the LRU clock (the caller persists). */
  lookup(stableKey: string, nowMs: number): LyricCacheEntry | null {
    const entry = this.find(stableKey);
    if (entry === null) {
      return null;
    }
    entry.lastUsedAt = nowMs;
    return entry;
  }

  /**
   * Records a resolved lyric and evicts least-recently-used entries beyond
   * maxEntries. Returns true when the table changed and the caller should
   * persist; an empty lines array is ignored (never cache a miss).
   */
  record(stableKey: string, source: LyricSourceTag, lines: LyricLine[], nowMs: number, maxEntries: number): boolean {
    if (stableKey.length === 0 || lines.length === 0) {
      return false;
    }
    const existing = this.find(stableKey);
    if (existing !== null) {
      existing.source = source;
      existing.lines = lines;
      existing.lastUsedAt = nowMs;
      return true;
    }
    this.entries.push(new LyricCacheEntry(stableKey, source, lines, nowMs));
    while (this.entries.length > maxEntries) {
      let oldestIndex = 0;
      for (let i = 1; i < this.entries.length; i++) {
        if (this.entries[i].lastUsedAt < this.entries[oldestIndex].lastUsedAt) {
          oldestIndex = i;
        }
      }
      this.entries.splice(oldestIndex, 1);
    }
    return true;
  }

  remove(stableKey: string): boolean {
    for (let i = 0; i < this.entries.length; i++) {
      if (this.entries[i].stableKey === stableKey) {
        this.entries.splice(i, 1);
        return true;
      }
    }
    return false;
  }

  clear(): void {
    this.entries = [];
  }
}
