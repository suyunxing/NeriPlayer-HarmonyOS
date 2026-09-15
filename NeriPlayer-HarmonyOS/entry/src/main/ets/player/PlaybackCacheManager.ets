// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';
import { Logger } from '../app/Logger';
import { SongItem } from '../model/SongItem';
import { stableKeyOf } from '../model/SongIdentity';
import { SettingsRepository } from '../data/SettingsRepository';
import { SchemaStore } from '../data/schema/SchemaStore';
import { PlaybackCacheLedger } from './PlaybackCacheLedger';

const CACHE_CALL_TIMEOUT_MS = 8000;
const LEDGER_KEY = 'playback_cache';
const MAX_ENTRIES = 24;
/** Purge a pending enqueue whose task never reported a terminal state. */
const PENDING_GHOST_MS = 5 * 60 * 1000;

/**
 * Playback cache over the API 26 AVDownloaderManager (createAVDownloaderManager
 * / addAVDownloadTask, @since 26): an opt-in (np.playback_cache) accelerator
 * that stores system-managed offline copies of online streams, so replays
 * play from disk through createMediaSourceWithDirectory instead of hitting
 * the platform APIs again. It complements — never replaces — the download
 * engine: no user-visible files, no custom directory, Wi-Fi only (the system
 * default), bounded by an LRU ledger (evicted dirs removed best-effort).
 *
 * Every call is timeout-guarded (a hung stub must not pin playback); manager
 * creation failure latches the feature off for the process. The ledger is a
 * separate pure class so eviction stays unit-testable.
 */
export class PlaybackCacheManager {
  private static manager: media.AVDownloaderManager | null = null;
  private static managerFailed: boolean = false;
  private static ledger: PlaybackCacheLedger | null = null;
  private static ledgerReady: Promise<void> | null = null;
  private static pendingByTask: Map<string, string> = new Map();
  private static pendingSince: Map<string, number> = new Map();

  static isEnabled(): boolean {
    return SettingsRepository.getBoolean(SettingsRepository.KEY_PLAYBACK_CACHE, false);
  }

  private static ensureLedger(): Promise<void> {
    if (PlaybackCacheManager.ledgerReady === null) {
      PlaybackCacheManager.ledgerReady = SchemaStore.load(
        LEDGER_KEY,
        new PlaybackCacheLedger(),
        (json: string): PlaybackCacheLedger | null => PlaybackCacheLedger.fromJson(json)
      ).then((loaded: PlaybackCacheLedger) => {
        PlaybackCacheManager.ledger = loaded;
      }).catch((error: Error) => {
        Logger.warn(`PlaybackCacheManager ledger load failed: ${error.message}`);
        PlaybackCacheManager.ledger = new PlaybackCacheLedger();
      });
    }
    return PlaybackCacheManager.ledgerReady;
  }

  private static ensureManager(): Promise<media.AVDownloaderManager | null> {
    if (PlaybackCacheManager.managerFailed) {
      return Promise.resolve(null);
    }
    if (PlaybackCacheManager.manager !== null) {
      return Promise.resolve(PlaybackCacheManager.manager);
    }
    return new Promise<media.AVDownloaderManager | null>((resolve) => {
      const creation = media.createAVDownloaderManager();
      const timer = setTimeout(() => {
        PlaybackCacheManager.managerFailed = true;
        Logger.warn('PlaybackCacheManager: createAVDownloaderManager timed out');
        resolve(null);
      }, CACHE_CALL_TIMEOUT_MS);
      creation.then((manager: media.AVDownloaderManager) => {
        clearTimeout(timer);
        manager.onStatusChange((taskId: string, state: media.AVDownloadTaskState) => {
          PlaybackCacheManager.onTaskState(taskId, state);
        });
        PlaybackCacheManager.manager = manager;
        resolve(manager);
      }, (error: Error) => {
        clearTimeout(timer);
        PlaybackCacheManager.managerFailed = true;
        Logger.warn(`PlaybackCacheManager: createAVDownloaderManager failed: ${error.message}`);
        resolve(null);
      });
    });
  }

  /**
   * Cache-hit path for loadSong: a ready-to-play directory MediaSource, or
   * null (disabled, miss, listen-together session, or any failure — the
   * caller then resolves the stream online exactly as before). A hit whose
   * directory no longer loads drops the ledger entry so the miss self-heals.
   */
  static async takeSourceFor(song: SongItem, listenTogetherActive: boolean): Promise<media.MediaSource | null> {
    if (!PlaybackCacheManager.isEnabled() || listenTogetherActive) {
      return null;
    }
    await PlaybackCacheManager.ensureLedger();
    const ledger = PlaybackCacheManager.ledger;
    if (ledger === null) {
      return null;
    }
    const key = stableKeyOf(song);
    const entry = ledger.lookup(key, Date.now());
    if (entry === null || entry.cacheDir.length === 0) {
      return null;
    }
    try {
      const source = await PlaybackCacheManager.withTimeout(
        media.createMediaSourceWithDirectory(entry.cacheDir)
      );
      if (source === undefined || source === null) {
        throw new Error('createMediaSourceWithDirectory returned no source');
      }
      PlaybackCacheManager.persistLedger();
      Logger.info(`PlaybackCacheManager: cache hit for ${song.displayName}`);
      return source;
    } catch (error) {
      const e = error as Error;
      Logger.warn(`PlaybackCacheManager: cache hit unusable, dropping: ${e.message}`);
      ledger.remove(key);
      PlaybackCacheManager.persistLedger();
      return null;
    }
  }

  /**
   * Fire-and-forget enqueue after a successful online play: caches the
   * stream that was just consumed so replays go offline. Never awaited by
   * the playback path.
   */
  static scheduleCache(song: SongItem, url: string, headers: Record<string, string>): void {
    if (!PlaybackCacheManager.isEnabled() || url.length === 0) {
      return;
    }
    const lowered = url.toLowerCase();
    if (!lowered.startsWith('http://') && !lowered.startsWith('https://')) {
      return;
    }
    void PlaybackCacheManager.cacheAsync(song, url, headers);
  }

  private static async cacheAsync(song: SongItem, url: string, headers: Record<string, string>): Promise<void> {
    try {
      PlaybackCacheManager.sweepGhostPending();
      await PlaybackCacheManager.ensureLedger();
      const ledger = PlaybackCacheManager.ledger;
      if (ledger === null) {
        return;
      }
      const key = stableKeyOf(song);
      if (ledger.find(key) !== null || PlaybackCacheManager.pendingSince.has(key)) {
        return;
      }
      const manager = await PlaybackCacheManager.ensureManager();
      if (manager === null) {
        return;
      }
      const source = Object.keys(headers).length > 0
        ? media.createMediaSourceWithUrl(url, headers)
        : media.createMediaSourceWithUrl(url);
      const taskId = manager.addAVDownloadTask(source);
      PlaybackCacheManager.pendingByTask.set(taskId, key);
      PlaybackCacheManager.pendingSince.set(key, Date.now());
      Logger.info(`PlaybackCacheManager: caching ${song.displayName} (task ${taskId})`);
    } catch (error) {
      const e = error as Error;
      // Transient (task add rejected); no latch — the next song retries.
      Logger.debug(`PlaybackCacheManager enqueue failed: ${e.message}`);
    }
  }

  /**
   * Terminal-state bookkeeping. 'completed' promotes the task's cache
   * directory into the LRU ledger (evicting the stalest entries and
   * best-effort deleting their directories); error/removing just drop the
   * pending marker so the song can be retried later.
   */
  private static onTaskState(taskId: string, state: media.AVDownloadTaskState): void {
    const key = PlaybackCacheManager.pendingByTask.get(taskId);
    if (key === undefined) {
      return;
    }
    const ledger = PlaybackCacheManager.ledger;
    const manager = PlaybackCacheManager.manager;
    if (state === 'completed' && ledger !== null && manager !== null) {
      PlaybackCacheManager.pendingByTask.delete(taskId);
      PlaybackCacheManager.pendingSince.delete(key);
      let cacheDir = '';
      try {
        cacheDir = manager.getTaskCacheDirectory(taskId);
      } catch (error) {
        const e = error as Error;
        Logger.warn(`PlaybackCacheManager getTaskCacheDirectory failed: ${e.message}`);
        return;
      }
      const evicted = ledger.record(key, taskId, cacheDir, Date.now(), MAX_ENTRIES);
      for (const evictedKey of evicted) {
        PlaybackCacheManager.removeEvicted(ledger, evictedKey);
      }
      PlaybackCacheManager.persistLedger();
      Logger.info(`PlaybackCacheManager: cached ${key}, ledger size ${ledger.size()}`);
      return;
    }
    if (state === 'error' || state === 'removing') {
      PlaybackCacheManager.pendingByTask.delete(taskId);
      PlaybackCacheManager.pendingSince.delete(key);
    }
  }

  private static removeEvicted(ledger: PlaybackCacheLedger, key: string): void {
    const entry = ledger.find(key);
    if (entry === null) {
      return;
    }
    const dir = entry.cacheDir;
    ledger.remove(key);
    if (dir.length === 0) {
      return;
    }
    try {
      fileIo.rmdirSync(dir);
    } catch (error) {
      // The dir is system-managed; failing to delete it costs disk space,
      // not correctness — the ledger entry is gone so it will never be hit.
      const e = error as Error;
      Logger.debug(`PlaybackCacheManager evict rmdir failed: ${e.message}`);
    }
  }

  /**
   * Drops pending markers whose task never reported a terminal state, so a
   * zombie task cannot block re-caching that song forever.
   */
  private static sweepGhostPending(): void {
    const now = Date.now();
    const ghosted: string[] = [];
    PlaybackCacheManager.pendingSince.forEach((since: number, key: string) => {
      if (now - since > PENDING_GHOST_MS) {
        ghosted.push(key);
      }
    });
    for (const key of ghosted) {
      PlaybackCacheManager.pendingSince.delete(key);
      const orphanTasks: string[] = [];
      PlaybackCacheManager.pendingByTask.forEach((taskKey: string, taskId: string) => {
        if (taskKey === key) {
          orphanTasks.push(taskId);
        }
      });
      for (const taskId of orphanTasks) {
        PlaybackCacheManager.pendingByTask.delete(taskId);
      }
    }
  }

  private static persistLedger(): void {
    const ledger = PlaybackCacheManager.ledger;
    if (ledger === null) {
      return;
    }
    SchemaStore.save(LEDGER_KEY, ledger, (value: PlaybackCacheLedger): string => value.toJson())
      .catch((error: Error) => {
        Logger.warn(`PlaybackCacheManager persist failed: ${error.message}`);
      });
  }

  private static withTimeout<T>(promise: Promise<T>): Promise<T> {
    return new Promise<T>((resolve: (value: T) => void, reject: (reason: Error) => void) => {
      const timer = setTimeout(() => {
        reject(new Error('playback cache call timed out'));
      }, CACHE_CALL_TIMEOUT_MS);
      promise.then((value: T) => {
        clearTimeout(timer);
        resolve(value);
      }, (reason: Error) => {
        clearTimeout(timer);
        reject(reason);
      });
    });
  }
}
