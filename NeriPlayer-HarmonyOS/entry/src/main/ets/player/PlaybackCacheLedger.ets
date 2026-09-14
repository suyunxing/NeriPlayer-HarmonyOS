// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Pure LRU ledger for the playback cache (PlaybackCacheManager). Maps a
 * stable song key to the system-managed offline cache directory an
 * AVDownloaderManager task produced, with a size cap and least-recently-
 * played eviction. No @ohos imports so the eviction rules stay unit-testable.
 */
export class PlaybackCacheEntry {
  // Field initializers are required: ArkTS JSON.stringify of a class
  // instance without them serializes type defaults, not constructor values.
  stableKey: string = '';
  taskId: string = '';
  cacheDir: string = '';
  createdAt: number = 0;
  lastPlayedAt: number = 0;

  constructor(stableKey: string, taskId: string, cacheDir: string, createdAt: number) {
    this.stableKey = stableKey;
    this.taskId = taskId;
    this.cacheDir = cacheDir;
    this.createdAt = createdAt;
    this.lastPlayedAt = createdAt;
  }
}

export class PlaybackCacheLedger {
  private entries: PlaybackCacheEntry[] = [];

  static fromJson(json: string): PlaybackCacheLedger | null {
    let raw: Record<string, Object>;
    try {
      raw = JSON.parse(json) as Record<string, Object>;
    } catch (error) {
      return null;
    }
    const ledger = new PlaybackCacheLedger();
    const list = raw['entries'];
    if (list === undefined || !Array.isArray(list)) {
      return ledger;
    }
    for (const item of list as Object[]) {
      const record = item as Record<string, Object>;
      const key = String(record['stableKey'] ?? '');
      if (key.length === 0) {
        continue;
      }
      const entry = new PlaybackCacheEntry(
        key,
        String(record['taskId'] ?? ''),
        String(record['cacheDir'] ?? ''),
        Number(record['createdAt'] ?? 0)
      );
      entry.lastPlayedAt = Number(record['lastPlayedAt'] ?? entry.createdAt);
      ledger.entries.push(entry);
    }
    return ledger;
  }

  toJson(): string {
    return JSON.stringify({ entries: this.entries });
  }

  size(): number {
    return this.entries.length;
  }

  find(stableKey: string): PlaybackCacheEntry | null {
    for (const entry of this.entries) {
      if (entry.stableKey === stableKey) {
        return entry;
      }
    }
    return null;
  }

  /**
   * Cache-hit lookup; a hit refreshes the LRU clock (the caller persists).
   * The entry is returned as-is, so callers must not retain it across
   * mutations.
   */
  lookup(stableKey: string, nowMs: number): PlaybackCacheEntry | null {
    const entry = this.find(stableKey);
    if (entry === null) {
      return null;
    }
    entry.lastPlayedAt = nowMs;
    return entry;
  }

  /**
   * Records (or refreshes) a completed cache and returns the stable keys
   * evicted to honor maxEntries — least-recently-used first, where "use" is
   * max(lastPlayedAt, createdAt). The caller owns cleanup of the evicted
   * cache directories.
   */
  record(stableKey: string, taskId: string, cacheDir: string, nowMs: number, maxEntries: number): string[] {
    const existing = this.find(stableKey);
    if (existing !== null) {
      existing.taskId = taskId;
      existing.cacheDir = cacheDir;
      existing.lastPlayedAt = nowMs;
      return [];
    }
    this.entries.push(new PlaybackCacheEntry(stableKey, taskId, cacheDir, nowMs));
    const evicted: string[] = [];
    while (this.entries.length > maxEntries) {
      let oldestIndex = 0;
      for (let i = 1; i < this.entries.length; i++) {
        const champion = Math.max(this.entries[oldestIndex].lastPlayedAt, this.entries[oldestIndex].createdAt);
        const candidate = Math.max(this.entries[i].lastPlayedAt, this.entries[i].createdAt);
        if (candidate < champion) {
          oldestIndex = i;
        }
      }
      evicted.push(this.entries[oldestIndex].stableKey);
      this.entries.splice(oldestIndex, 1);
    }
    return evicted;
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
}
