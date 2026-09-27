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
import { Playlist } from '../model/Playlist';
import { PlaylistSyncSource } from './SourceSyncModels';
import { SyncSourceAdapter } from './SyncSourceAdapter';
import { NeteaseSyncSource } from './NeteaseSyncSource';
import { BiliSyncSource } from './BiliSyncSource';
import { Logger } from '../app/Logger';

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
  private static readonly FULL_CHECK_INTERVAL_MS: number = 24 * 3600 * 1000;
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
  static async runNow(): Promise<void> {
    await SourceSyncCoordinator.run('manual');
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

  private static async run(trigger: string): Promise<void> {
    if (SourceSyncCoordinator.running) {
      return;
    }
    SourceSyncCoordinator.running = true;
    try {
      if (!await NetworkStatus.hasNetwork()) {
        Logger.info(`source sync (${trigger}) skipped: offline`);
        return;
      }
      if (SyncCoordinator.isRunning()) {
        // The cross-device sync reads/writes the same playlist store; yield
        // and wait for the next trigger instead of racing it.
        Logger.info(`source sync (${trigger}) skipped: cross-device sync running`);
        return;
      }
      const playlists = await LocalPlaylistRepository.loadAll();
      let changedAny = false;
      for (const playlist of playlists) {
        const source = playlist.syncSource;
        if (source === null || !source.enabled) {
          continue;
        }
        try {
          const changed = await SourceSyncCoordinator.syncOne(playlist);
          changedAny = changedAny || changed;
        } catch (error) {
          Logger.warn(`source sync (${trigger}) failed for ${source.remoteName}: ${(error as Error).message}`);
        }
      }
      if (changedAny) {
        // Data-layer changes do not push UI by themselves: bump the shared
        // refresh tick so the home/library tabs reload their local data.
        const current = AppStorage.get<number>(KEY_REFRESH_TICK);
        AppStorage.setOrCreate(KEY_REFRESH_TICK, (current ?? 0) + 1);
      }
    } finally {
      SourceSyncCoordinator.running = false;
    }
  }

  private static async syncOne(playlist: Playlist): Promise<boolean> {
    const source = playlist.syncSource;
    if (source === null) {
      return false;
    }
    const adapter = SourceSyncCoordinator.adapterFor(source);
    if (adapter === null || !SourceSyncCoordinator.isLoggedIn(source.platform)) {
      return false;
    }
    const fingerprint = await adapter.peekFingerprint();
    if (fingerprint === source.lastFingerprint
      && Date.now() - source.lastCheckedAt < SourceSyncCoordinator.FULL_CHECK_INTERVAL_MS) {
      return false;
    }
    const songs = await adapter.fetchSongs();
    if (songs.length === 0) {
      // A transient failure can surface as an empty list (the Bilibili parser
      // swallows business codes); never wipe a mirror playlist on it. A truly
      // emptied remote folder stays until the user unbinds or resets sync.
      Logger.warn(`source sync empty snapshot, skipped: ${source.remoteName}`);
      return false;
    }
    return LocalPlaylistRepository.applyMirrorSync(playlist.id, songs, fingerprint);
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
