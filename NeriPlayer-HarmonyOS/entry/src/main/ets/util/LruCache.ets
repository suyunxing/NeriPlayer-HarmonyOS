// SPDX-License-Identifier: GPL-3.0

/**
 * 进程内 LRU 缓存（纯逻辑，无平台 API，可单测）。利用 Map 的插入序实现
 * 淘汰：get/peek 命中即移到队尾，put 超容时从队头淘汰最久未用项。
 */
export class LruCache<K, V> {
  private readonly maxEntries: number;
  private entries: Map<K, V> = new Map<K, V>();

  constructor(maxEntries: number) {
    this.maxEntries = maxEntries < 1 ? 1 : maxEntries;
  }

  /** 取值并提升为最近使用。 */
  get(key: K): V | undefined {
    const value = this.entries.get(key);
    if (value !== undefined) {
      this.entries.delete(key);
      this.entries.set(key, value);
    }
    return value;
  }

  /** 只读不提升（近线检查用）。 */
  peek(key: K): V | undefined {
    return this.entries.get(key);
  }

  put(key: K, value: V): void {
    this.entries.delete(key);
    this.entries.set(key, value);
    while (this.entries.size > this.maxEntries) {
      const oldest = LruCache.firstKey<K, V>(this.entries);
      if (oldest === undefined) {
        break;
      }
      this.entries.delete(oldest);
    }
  }

  size(): number {
    return this.entries.size;
  }

  clear(): void {
    this.entries.clear();
  }

  private static firstKey<K, V>(map: Map<K, V>): K | undefined {
    for (const key of map.keys()) {
      return key;
    }
    return undefined;
  }
}
