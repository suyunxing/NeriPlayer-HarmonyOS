import { AppPreferences } from '../AppPreferences';
import { Logger } from '../../app/Logger';

/**
 * Current schema version for every versioned key managed by SchemaStore.
 * Data written before versioning existed carries no envelope and is treated
 * as version 1. Bump and add a case in migrateJson when formats change.
 */
export class SchemaVersion {
  static readonly CURRENT: number = 1;
}

/**
 * Versioned, crash-resilient JSON persistence over the shared preferences
 * store, mirroring the Android atomic-write + .bak semantics:
 *
 * - write: previous value is copied to `<key>.bak` before the new value is
 *   flushed (preferences flush is atomic per put, so the pair is a
 *   best-effort snapshot);
 * - read: primary value first; on parse failure fall back to `.bak`; if both
 *   are unusable return the caller default and log (no silent data loss
 *   without a trace);
 * - writes are debounced per key so high-frequency callers (play history,
 *   stats) coalesce into one flush.
 */
export class SchemaStore {
  private static readonly BAK_SUFFIX: string = '.bak';
  private static readonly DEFAULT_DEBOUNCE_MS: number = 500;
  private static pendingTimers: Map<string, number> = new Map<string, number>();
  private static pendingWrites: Map<string, string> = new Map<string, string>();
  private static pendingBaks: Map<string, string> = new Map<string, string>();

  /**
   * Loads and parses a versioned value with backup fallback.
   *
   * @param key preferences key
   * @param fallback value returned when both primary and backup are unusable
   * @param parse parses raw JSON; return null when the payload is corrupt
   */
  static async load<T>(key: string, fallback: T, parse: (json: string) => T | null): Promise<T> {
    const primary = await AppPreferences.getString(key, '');
    if (primary.length > 0) {
      const parsed = SchemaStore.tryParse(primary, parse);
      if (parsed !== null) {
        return parsed;
      }
      Logger.warn(`SchemaStore: primary payload corrupt for key=${key}, trying backup`);
    }
    const bak = await AppPreferences.getString(key + SchemaStore.BAK_SUFFIX, '');
    if (bak.length > 0) {
      const parsed = SchemaStore.tryParse(bak, parse);
      if (parsed !== null) {
        Logger.warn(`SchemaStore: recovered key=${key} from backup`);
        await AppPreferences.putString(key, bak);
        return parsed;
      }
    }
    Logger.warn(`SchemaStore: key=${key} unusable, using default`);
    return fallback;
  }

  /**
   * Persists a value, rotating the previous payload into `.bak` first.
   */
  static async save<T>(key: string, value: T, serialize: (value: T) => string): Promise<void> {
    const json = serialize(value);
    const old = await AppPreferences.getString(key, '');
    if (old.length > 0 && old !== json) {
      await AppPreferences.putString(key + SchemaStore.BAK_SUFFIX, old);
    }
    await AppPreferences.putString(key, json);
  }

  /**
   * Debounced save: coalesces repeated writes to the same key within the
   * debounce window into one flush. Use for high-frequency updates.
   */
  static saveDebounced<T>(key: string, value: T, serialize: (value: T) => string, debounceMs: number = SchemaStore.DEFAULT_DEBOUNCE_MS): void {
    const json = serialize(value);
    const previousTimer = SchemaStore.pendingTimers.get(key);
    if (previousTimer !== undefined) {
      clearTimeout(previousTimer);
    }
    SchemaStore.pendingWrites.set(key, json);
    const timer = setTimeout(() => {
      const pending = SchemaStore.pendingWrites.get(key);
      SchemaStore.pendingTimers.delete(key);
      SchemaStore.pendingWrites.delete(key);
      if (pending !== undefined) {
        SchemaStore.saveJsonNow(key, pending);
      }
    }, debounceMs);
    SchemaStore.pendingTimers.set(key, timer);
  }

  /**
   * Flushes any pending debounced write for the given key immediately
   * (call on background/destroy paths).
   */
  static flush(key: string): void {
    const timer = SchemaStore.pendingTimers.get(key);
    if (timer !== undefined) {
      clearTimeout(timer);
    }
    const pending = SchemaStore.pendingWrites.get(key);
    SchemaStore.pendingTimers.delete(key);
    SchemaStore.pendingWrites.delete(key);
    if (pending !== undefined) {
      SchemaStore.saveJsonNow(key, pending);
    }
  }

  static flushAll(): void {
    const keys = SchemaStore.pendingWrites.keys();
    for (const key of keys) {
      SchemaStore.flush(key);
    }
  }

  private static saveJsonNow(key: string, json: string): void {
    AppPreferences.getString(key, '').then((old: string) => {
      if (old.length > 0 && old !== json) {
        AppPreferences.putString(key + SchemaStore.BAK_SUFFIX, old);
      }
      AppPreferences.putString(key, json);
    });
  }

  private static tryParse<T>(json: string, parse: (json: string) => T | null): T | null {
    try {
      return parse(json);
    } catch (error) {
      const e = error as Error;
      Logger.warn(`SchemaStore: parse failed: ${e.message}`);
      return null;
    }
  }
}
