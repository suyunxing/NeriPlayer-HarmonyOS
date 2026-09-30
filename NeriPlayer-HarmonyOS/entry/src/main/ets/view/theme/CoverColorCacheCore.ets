// SPDX-License-Identifier: GPL-3.0

/**
 * In-memory LRU + single-flight dedup cache for cover seed colors, mirroring
 * CoverArtColorCache.kt: LruCache(64), no TTL, no disk persistence, and
 * concurrent loads of the same URL join the first flight. Pure ArkTS with an
 * injected loader so the eviction/dedup semantics are unit-testable without
 * @ohos APIs; the network+decode loader lives in CoverArtColorCache.ets.
 */
export type CoverSeedLoader = (coverUrl: string) => Promise<string | null>;

export class CoverColorCacheCore {
  private readonly capacity: number;
  private readonly loader: CoverSeedLoader;
  // Map iteration order tracks recency: most recent at the end.
  private readonly cached: Map<string, string | null> = new Map<string, string | null>();
  private readonly inFlight: Map<string, Promise<string | null>> = new Map<string, Promise<string | null>>();

  constructor(loader: CoverSeedLoader, capacity: number = 64) {
    this.loader = loader;
    this.capacity = Math.max(1, capacity);
  }

  /** Cached value without loading; undefined means "not cached". */
  peek(coverUrl: string): string | null | undefined {
    const key = coverUrl.trim();
    const hit = this.cached.get(key);
    if (hit !== undefined) {
      this.touch(key, hit);
    }
    return hit;
  }

  async getOrLoad(coverUrl: string): Promise<string | null> {
    const key = coverUrl.trim();
    const hit = this.peek(key);
    if (hit !== undefined) {
      return hit;
    }
    const pending = this.inFlight.get(key);
    if (pending !== undefined) {
      return pending;
    }
    const flight = this.load(key);
    this.inFlight.set(key, flight);
    try {
      return await flight;
    } finally {
      this.inFlight.delete(key);
    }
  }

  private async load(key: string): Promise<string | null> {
    let outcome: string | null = null;
    try {
      outcome = await Promise.resolve(this.loader(key));
    } catch (error) {
      // Android runCatching { ... }.getOrNull(): failures degrade to null,
      // callers fall back to their stock theme colors.
      outcome = null;
      void error;
    }
    this.put(key, outcome);
    return outcome;
  }

  private put(key: string, value: string | null): void {
    if (this.cached.size >= this.capacity && !this.cached.has(key)) {
      const oldest = this.cached.keys().next();
      if (!oldest.done) {
        this.cached.delete(oldest.value);
      }
    }
    this.cached.delete(key);
    this.cached.set(key, value);
  }

  private touch(key: string, value: string | null): void {
    this.cached.delete(key);
    this.cached.set(key, value);
  }
}
