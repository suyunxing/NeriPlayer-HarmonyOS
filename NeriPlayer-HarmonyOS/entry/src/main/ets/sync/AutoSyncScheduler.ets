// SPDX-License-Identifier: GPL-3.0

import { workScheduler } from '@kit.BackgroundTasksKit';
import { AppPreferences } from '../data/AppPreferences';
import { SettingsRepository } from '../data/SettingsRepository';
import { GitHubConfigRepository } from './github/GitHubConfigRepository';
import { WebDavConfigRepository } from './webdav/WebDavConfigRepository';
import { SyncReport } from './SyncReport';
import { Logger } from '../app/Logger';

/**
 * Automatic silent sync (backlog §1.5, Android GitHubSyncWorker equivalent).
 *
 * Three trigger layers, all gated by np.sync_auto + a configured transport
 * (Android's auto sync also defaults off):
 *  1. debounced sync 5s after local mutations (repositories call
 *     scheduleMutationSync directly — the dominant Android path too);
 *  2. throttled sync on app launch (1h window);
 *  3. a periodic background delayed task (@ohos.resourceschedule.workScheduler,
 *     >=2h cadence, network permitted, 2-min callback cap per official docs —
 *     the only compliant WorkManager-style channel on API 26).
 *
 * Failures are silent by design: they land in the log; the manual sync entry
 * in settings stays the user-facing recovery path. The runner is injected by
 * the ability entry to keep this module free of the repository import graph.
 */

export type SilentSyncRunner = () => Promise<SyncReport | null>;

export class AutoSyncScheduler {
  private static readonly LAST_STARTUP_SYNC_KEY: string = 'np.auto_sync.last_startup_at';
  private static readonly STARTUP_THROTTLE_MS: number = 3600000;
  private static readonly MUTATION_DELAY_MS: number = 5000;
  // Song skips fire flushPlaybackStats on every transition; coalesce bursts
  // into at most one silent sync per window (Android lets WorkManager's
  // APPEND_OR_REPLACE do the same job).
  private static readonly MUTATION_MIN_INTERVAL_MS: number = 600000;
  private static readonly WORK_ID: number = 1001;
  private static readonly WORK_ABILITY_NAME: string = 'SyncWorkSchedulerAbility';
  // Official minimum repeat is 2h (active group); 6h matches the sync cadence
  // goals and stays cheap on battery.
  private static readonly WORK_REPEAT_MS: number = 6 * 3600 * 1000;
  private static runner: SilentSyncRunner | null = null;
  private static bundleName: string = '';
  private static mutationTimer: number = -1;
  private static mutationCatchUpTimer: number = -1;
  private static mutationPending: boolean = false;
  private static mutationRunning: boolean = false;
  private static lastMutationSyncAt: number = 0;

  static setRunner(runner: SilentSyncRunner): void {
    AutoSyncScheduler.runner = runner;
  }

  static setBundleName(bundleName: string): void {
    AutoSyncScheduler.bundleName = bundleName;
  }

  static async isConfiguredAndEnabled(): Promise<boolean> {
    if (!SettingsRepository.getBoolean(SettingsRepository.KEY_SYNC_AUTO, false)) {
      return false;
    }
    const github = await GitHubConfigRepository.loadConfig();
    if (github !== null) {
      return true;
    }
    const webDav = await WebDavConfigRepository.loadConfig();
    return webDav !== null;
  }

  /** App-launch sync, at most once per STARTUP_THROTTLE_MS. */
  static async scheduleStartupSync(): Promise<void> {
    try {
      if (!await AutoSyncScheduler.isConfiguredAndEnabled()) {
        return;
      }
      const lastText = await AppPreferences.getString(AutoSyncScheduler.LAST_STARTUP_SYNC_KEY, '0');
      const last = Number(lastText);
      if (Number.isFinite(last) && Date.now() - last < AutoSyncScheduler.STARTUP_THROTTLE_MS) {
        return;
      }
      await AppPreferences.putString(AutoSyncScheduler.LAST_STARTUP_SYNC_KEY, `${Date.now()}`);
      await AutoSyncScheduler.runSilently('startup');
    } catch (error) {
      Logger.warn(`startup sync scheduling failed: ${(error as Error).message}`);
    }
  }

  /** Mutation sync: 5s debounce, burst-coalesced to one run per 10 minutes. */
  static scheduleMutationSync(): void {
    AutoSyncScheduler.mutationPending = true;
    if (AutoSyncScheduler.mutationCatchUpTimer >= 0) {
      // Inside the min-interval window: the armed catch-up will pick this up.
      return;
    }
    const sinceLast = Date.now() - AutoSyncScheduler.lastMutationSyncAt;
    if (sinceLast < AutoSyncScheduler.MUTATION_MIN_INTERVAL_MS) {
      AutoSyncScheduler.mutationCatchUpTimer = setTimeout(() => {
        AutoSyncScheduler.mutationCatchUpTimer = -1;
        if (AutoSyncScheduler.mutationPending) {
          AutoSyncScheduler.scheduleMutationSync();
        }
      }, AutoSyncScheduler.MUTATION_MIN_INTERVAL_MS - sinceLast + 50);
      return;
    }
    if (AutoSyncScheduler.mutationTimer >= 0) {
      clearTimeout(AutoSyncScheduler.mutationTimer);
    }
    AutoSyncScheduler.mutationTimer = setTimeout(() => {
      AutoSyncScheduler.mutationTimer = -1;
      AutoSyncScheduler.runMutationSync();
    }, AutoSyncScheduler.MUTATION_DELAY_MS);
  }

  /** Entry point for the WorkSchedulerExtensionAbility callback (no throttle — the system already paced it). */
  static async runScheduledWork(): Promise<void> {
    try {
      if (!await AutoSyncScheduler.isConfiguredAndEnabled()) {
        return;
      }
      await AutoSyncScheduler.runSilently('workScheduler');
    } catch (error) {
      Logger.warn(`scheduled work sync failed: ${(error as Error).message}`);
    }
  }

  /** (Re)registers or cancels the periodic background delayed task. Idempotent. */
  static async updateDelayedWorkRegistration(): Promise<void> {
    if (AutoSyncScheduler.bundleName.length === 0) {
      return;
    }
    const work: workScheduler.WorkInfo = {
      workId: AutoSyncScheduler.WORK_ID,
      bundleName: AutoSyncScheduler.bundleName,
      abilityName: AutoSyncScheduler.WORK_ABILITY_NAME,
      networkType: workScheduler.NetworkType.NETWORK_TYPE_ANY,
      isRepeat: true,
      repeatCycleTime: AutoSyncScheduler.WORK_REPEAT_MS,
      isPersisted: true
    };
    try {
      const enabled = await AutoSyncScheduler.isConfiguredAndEnabled();
      if (enabled) {
        try {
          workScheduler.startWork(work);
        } catch (error) {
          // Already-registered duplicates raise here; that is the happy path
          // for repeated startup calls.
          Logger.debug(`delayed work startWork tolerated: ${(error as Error).message}`);
        }
      } else {
        try {
          workScheduler.stopWork(work);
        } catch (error) {
          Logger.debug(`delayed work stopWork tolerated: ${(error as Error).message}`);
        }
      }
    } catch (error) {
      Logger.warn(`delayed work registration failed: ${(error as Error).message}`);
    }
  }

  private static async runMutationSync(): Promise<void> {
    if (AutoSyncScheduler.mutationRunning || !AutoSyncScheduler.mutationPending) {
      return;
    }
    AutoSyncScheduler.mutationRunning = true;
    try {
      if (!await AutoSyncScheduler.isConfiguredAndEnabled()) {
        AutoSyncScheduler.mutationPending = false;
        return;
      }
      await AutoSyncScheduler.runSilently('mutation');
      AutoSyncScheduler.mutationPending = false;
      AutoSyncScheduler.lastMutationSyncAt = Date.now();
    } finally {
      AutoSyncScheduler.mutationRunning = false;
    }
  }

  private static async runSilently(trigger: string): Promise<void> {
    if (AutoSyncScheduler.runner === null) {
      return;
    }
    try {
      const pending: Promise<SyncReport | null> = AutoSyncScheduler.runner();
      const report = await pending;
      if (report !== null && !report.success) {
        // Silent by design: failures land in the log, the manual sync entry
        // in settings stays the user-facing recovery path.
        Logger.warn(`auto sync (${trigger}) failed: ${report.message}`);
      }
    } catch (error) {
      Logger.warn(`auto sync (${trigger}) error: ${(error as Error).message}`);
    }
  }
}
