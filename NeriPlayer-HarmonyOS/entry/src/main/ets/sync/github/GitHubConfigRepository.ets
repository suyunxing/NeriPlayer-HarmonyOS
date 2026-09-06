/**
 * GitHub sync configuration (Android SecureTokenStorage subset).
 *
 * Storage split (project red line: only credentials need the asset store):
 * - token -> asset alias "github_token" (same key name as Android for
 *   cross-device migration guidance; never logged, never in preferences);
 * - owner / repo / data-saver -> settings preferences (not secrets);
 * - lastRemoteSha / lastSyncTime -> plain preferences (runtime state);
 * - deviceId -> SyncDeletionStore (shared with the deletion tombstones).
 *
 * Android defaults data saver to true (uploads GZIP+proto); this port uploads
 * JSON while the compact writer is unimplemented (M5.2b record) and reads all
 * three formats, so the default here is false.
 */

import { util } from '@kit.ArkTS';
import { CredentialStore } from '../../data/auth/CredentialStore';
import { SettingsRepository } from '../../data/SettingsRepository';
import { AppPreferences } from '../../data/AppPreferences';
import { Logger } from '../../app/Logger';
import { SyncDeletionStore } from '../SyncDeletionStore';

const TAG: string = 'GitHubConfigRepository';

export class GitHubSyncConfig {
  token: string = '';
  owner: string = '';
  repo: string = '';
  dataSaver: boolean = false;
}

export class GitHubConfigRepository {
  /** Asset alias aligned with the Android secure-prefs key. */
  static readonly TOKEN_ALIAS: string = 'github_token';
  private static readonly KEY_LAST_REMOTE_SHA: string = 'github_last_remote_sha';
  private static readonly KEY_LAST_SYNC_TIME: string = 'github_last_sync_time';

  private static cachedToken: string = '';
  private static initPromise: Promise<void> | null = null;

  /** Idempotent; call from EntryAbility.onCreate so isConfigured() is sync-safe. */
  static init(): Promise<void> {
    if (GitHubConfigRepository.initPromise !== null) {
      return GitHubConfigRepository.initPromise;
    }
    GitHubConfigRepository.initPromise = GitHubConfigRepository.doInit();
    return GitHubConfigRepository.initPromise;
  }

  private static async doInit(): Promise<void> {
    GitHubConfigRepository.cachedToken = await CredentialStore.getString(GitHubConfigRepository.TOKEN_ALIAS);
    if (GitHubConfigRepository.cachedToken.length > 0) {
      Logger.info(`${TAG}: token restored (backend=${CredentialStore.backendName()})`);
    }
  }

  /** Sync-safe configured check for UI subtitles; token needs init() first. */
  static isConfigured(): boolean {
    return GitHubConfigRepository.cachedToken.length > 0 &&
      SettingsRepository.getString(SettingsRepository.KEY_GITHUB_OWNER, '').length > 0 &&
      SettingsRepository.getString(SettingsRepository.KEY_GITHUB_REPO, '').length > 0;
  }

  /** Token only (for dialogs that prefill); empty string when absent. */
  static tokenPreview(): string {
    return GitHubConfigRepository.cachedToken;
  }

  /**
   * Persists the full config. Token goes to the asset store; owner/repo/data
   * saver go to settings. Returns false when the token could not be persisted
   * (asset failure - UI should warn that the token will not survive restart).
   */
  static async saveConfig(token: string, owner: string, repo: string): Promise<boolean> {
    const trimmedToken = token.trim();
    if (trimmedToken.length === 0) {
      return false;
    }
    const persisted = await CredentialStore.putString(GitHubConfigRepository.TOKEN_ALIAS, trimmedToken);
    GitHubConfigRepository.cachedToken = trimmedToken;
    SettingsRepository.setString(SettingsRepository.KEY_GITHUB_OWNER, owner.trim());
    SettingsRepository.setString(SettingsRepository.KEY_GITHUB_REPO, repo.trim());
    if (!persisted) {
      Logger.warn(`${TAG}: token not persisted (session-only), owner/repo saved`);
    }
    return persisted;
  }

  /** Loads the full config; null until token/owner/repo are all present. */
  static async loadConfig(): Promise<GitHubSyncConfig | null> {
    let token = GitHubConfigRepository.cachedToken;
    if (token.length === 0) {
      token = await CredentialStore.getString(GitHubConfigRepository.TOKEN_ALIAS);
      GitHubConfigRepository.cachedToken = token;
    }
    const owner = SettingsRepository.getString(SettingsRepository.KEY_GITHUB_OWNER, '').trim();
    const repo = SettingsRepository.getString(SettingsRepository.KEY_GITHUB_REPO, '').trim();
    if (token.length === 0 || owner.length === 0 || repo.length === 0) {
      return null;
    }
    const config = new GitHubSyncConfig();
    config.token = token;
    config.owner = owner;
    config.repo = repo;
    config.dataSaver = SettingsRepository.getBoolean(SettingsRepository.KEY_GITHUB_DATA_SAVER, false);
    return config;
  }

  /** Drops token + owner/repo + runtime state; keeps deviceId (still this install). */
  static async clear(): Promise<void> {
    await CredentialStore.remove(GitHubConfigRepository.TOKEN_ALIAS);
    GitHubConfigRepository.cachedToken = '';
    SettingsRepository.setString(SettingsRepository.KEY_GITHUB_OWNER, '');
    SettingsRepository.setString(SettingsRepository.KEY_GITHUB_REPO, '');
    await AppPreferences.putString(GitHubConfigRepository.KEY_LAST_REMOTE_SHA, '');
    await AppPreferences.putNumber(GitHubConfigRepository.KEY_LAST_SYNC_TIME, 0);
  }

  static async getLastRemoteSha(): Promise<string> {
    return AppPreferences.getString(GitHubConfigRepository.KEY_LAST_REMOTE_SHA, '');
  }

  static async saveLastRemoteSha(sha: string): Promise<void> {
    await AppPreferences.putString(GitHubConfigRepository.KEY_LAST_REMOTE_SHA, sha);
  }

  static async getLastSyncTime(): Promise<number> {
    return AppPreferences.getNumber(GitHubConfigRepository.KEY_LAST_SYNC_TIME, 0);
  }

  static async saveLastSyncTime(nowMs: number): Promise<void> {
    await AppPreferences.putNumber(GitHubConfigRepository.KEY_LAST_SYNC_TIME, nowMs);
  }

  /** Stable per-install UUID shared with the deletion tombstone store. */
  static async getDeviceId(): Promise<string> {
    return SyncDeletionStore.getOrCreateDeviceId((): string => util.generateRandomUUID(false));
  }
}
