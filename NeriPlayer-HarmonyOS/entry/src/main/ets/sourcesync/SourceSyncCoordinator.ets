// SPDX-License-Identifier: GPL-3.0

import { AppPreferences } from '../data/AppPreferences';
import { SettingsRepository } from '../data/SettingsRepository';
import { LocalPlaylistRepository } from '../data/LocalPlaylistRepository';
import { NeteaseCookieRepository } from '../data/auth/NeteaseCookieRepository';
import { BiliCookieRepository } from '../data/auth/BiliCookieRepository';
import { NetworkStatus } from '../util/NetworkStatus';
import { KEY_REFRESH_TICK } from '../util/Breakpoint';
import { SyncCoordinator } from '../sync/SyncCoordinator';
import { MusicPlatform } from '../model/MusicPlatform';
import { SongItem } from '../model/SongItem';
import { PlaylistSyncSource } from './SourceSyncModels';
import { SyncSourceAdapter } from './SyncSourceAdapter';
import { NeteaseSyncSource } from './NeteaseSyncSource';
import { BiliSyncSource } from './BiliSyncSource';
import { Logger } from '../app/Logger';
import { SourceSyncDependencies, runSourceSync } from './SourceSyncRunner';

/**
 * Source playlist auto sync (网易云歌单/B站收藏夹 → 本地镜像歌单).
 *
 * Orchestration mirrors AutoSyncScheduler: gate → timestamp-first throttle →
 * silent run, triggered on every cold start. Per source: login check → cheap
 * fingerprint → skip when unchanged (full fetch at least once a day to cover
 * fingerprint blind spots) → apply through LocalPlaylistRepository.applyMirrorSync.
 *
 * All failures are silent by design (log only) — the settings page keeps the
 * manual "立即同步" recovery path. A run never races the cross-device sync:
 * the coordinator yields when SyncCoordinator.isRunning(). A no-op check
 * persists nothing beyond the repository's silent bookkeeping save, so idle
 * entries never trigger a cross-device upload.
 */
export class SourceSyncCoordinator {
  private static readonly LAST_STARTUP_KEY: string = 'np.source_sync.last_startup_at';
  private static readonly DEFAULT_THROTTLE_MINUTES: number = 30;
  private static readonly STARTUP_DELAY_MS: number = 15000;
  /** Full remote fetch at least once a day even when the fingerprint is unchanged. */
  private static running: boolean = false;
  private static startupTimer: number = -1;

  /** Cold-start entry: throttled to one run per the configured window, after a short delay. */
  static scheduleStartupSync(): void {
    if (SourceSyncCoordinator.startupTimer >= 0) {
      clearTimeout(SourceSyncCoordinator.startupTimer);
      SourceSyncCoordinator.startupTimer = -1;
    }
    SourceSyncCoordinator.startupTimer = setTimeout(() => {
      SourceSyncCoordinator.startupTimer = -1;
      SourceSyncCoordinator.runThrottled('startup');
    }, SourceSyncCoordinator.STARTUP_DELAY_MS);
  }

  /** Manual entry (settings / playlist detail): ignores the throttle window. */
  static async runNow(playlistId: string = '', sourceKey: string = ''): Promise<void> {
    await SourceSyncCoordinator.run('manual', playlistId, sourceKey);
  }

  static isRunning(): boolean {
    return SourceSyncCoordinator.running;
  }

  private static async runThrottled(trigger: string): Promise<void> {
    try {
      if (!SettingsRepository.getBoolean(SettingsRepository.KEY_SOURCE_SYNC_ENABLED, true)) {
        return;
      }
      const minutes = SettingsRepository.getNumber(
        SettingsRepository.KEY_SOURCE_SYNC_THROTTLE_MINUTES, SourceSyncCoordinator.DEFAULT_THROTTLE_MINUTES);
      if (minutes > 0) {
        const lastText = await AppPreferences.getString(SourceSyncCoordinator.LAST_STARTUP_KEY, '0');
        const last = Number(lastText);
        if (Number.isFinite(last) && Date.now() - last < minutes * 60000) {
          return;
        }
        // Timestamp first (AutoSyncScheduler pattern): a killed run still
        // counts as attempted, so a crash loop cannot hammer the platform.
        await AppPreferences.putString(SourceSyncCoordinator.LAST_STARTUP_KEY, `${Date.now()}`);
      }
      await SourceSyncCoordinator.run(trigger);
    } catch (error) {
      Logger.warn(`source sync (${trigger}) throttle check failed: ${(error as Error).message}`);
    }
  }

  private static async run(trigger: string, playlistId: string = '', sourceKey: string = ''): Promise<void> {
    const targeted = playlistId.length > 0 || sourceKey.length > 0;
    if (SourceSyncCoordinator.running) {
      if (targeted) {
        throw new Error('Source sync is already running');
      }
      return;
    }
    SourceSyncCoordinator.running = true;
    let changedAny = false;
    try {
      if (!await NetworkStatus.hasNetwork()) {
        if (targeted) {
          throw new Error('Source sync is offline');
        }
        Logger.info(`source sync (${trigger}) skipped: offline`);
        return;
      }
      if (SyncCoordinator.isRunning()) {
        if (targeted) {
          throw new Error('Cross-device sync is already running');
        }
        // The cross-device sync reads/writes the same playlist store; yield
        // and wait for the next trigger instead of racing it.
        Logger.info(`source sync (${trigger}) skipped: cross-device sync running`);
        return;
      }
      const playlists = await LocalPlaylistRepository.loadAll();
      const dependencies: SourceSyncDependencies = {
        adapterFor: (source: PlaylistSyncSource): SyncSourceAdapter | null => SourceSyncCoordinator.adapterFor(source),
        isLoggedIn: (platform: MusicPlatform): boolean => SourceSyncCoordinator.isLoggedIn(platform),
        now: (): number => Date.now(),
        apply: async (id: string, songs: SongItem[], fingerprint: string, key: string, token: string): Promise<boolean> => {
          const changed = await LocalPlaylistRepository.applyMirrorSync(id, songs, fingerprint, key, token);
          changedAny = changedAny || changed;
          return changed;
        },
        onFailure: (source: PlaylistSyncSource, error: Error): void => {
          Logger.warn(`source sync (${trigger}) failed for ${source.remoteName}: ${error.message}`);
        }
      };
      await runSourceSync(playlists, dependencies, playlistId, sourceKey, trigger === 'manual');
    } finally {
      if (changedAny) {
        // Data-layer changes do not push UI by themselves: bump the shared
        // refresh tick so the home/library tabs reload their local data.
        const current = AppStorage.get<number>(KEY_REFRESH_TICK);
        AppStorage.setOrCreate(KEY_REFRESH_TICK, (current ?? 0) + 1);
      }
      SourceSyncCoordinator.running = false;
    }
  }

  private static adapterFor(source: PlaylistSyncSource): SyncSourceAdapter | null {
    const id = Number(source.remoteId);
    if (!Number.isFinite(id) || id <= 0) {
      return null;
    }
    if (source.platform === MusicPlatform.NETEASE) {
      return new NeteaseSyncSource(id);
    }
    if (source.platform === MusicPlatform.BILIBILI) {
      return new BiliSyncSource(id);
    }
    return null;
  }

  private static isLoggedIn(platform: MusicPlatform): boolean {
    if (platform === MusicPlatform.BILIBILI) {
      return BiliCookieRepository.isLoggedIn();
    }
    return NeteaseCookieRepository.isLoggedIn();
  }
}
