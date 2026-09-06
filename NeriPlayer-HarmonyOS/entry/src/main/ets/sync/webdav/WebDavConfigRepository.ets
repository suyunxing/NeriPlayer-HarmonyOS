/** WebDAV configuration with credentials isolated in the Asset store. */

import { AppPreferences } from '../../data/AppPreferences';
import { CredentialStore } from '../../data/auth/CredentialStore';
import { SettingsRepository } from '../../data/SettingsRepository';
import { Logger } from '../../app/Logger';
import {
  buildWebDavRemoteFileUrl,
  normalizeWebDavBasePath,
  normalizeWebDavServerUrl
} from './WebDavTransport';

const TAG: string = 'WebDavConfigRepository';

export class WebDavSyncConfig {
  serverUrl: string = '';
  basePath: string = '';
  username: string = '';
  password: string = '';

  remoteFileUrl(): string {
    return buildWebDavRemoteFileUrl(this.serverUrl, this.basePath);
  }
}

export class WebDavConfigRepository {
  static readonly USERNAME_ALIAS: string = 'webdav_username';
  static readonly PASSWORD_ALIAS: string = 'webdav_password';
  private static readonly KEY_LAST_REMOTE_FINGERPRINT: string = 'webdav_last_remote_fingerprint';
  private static readonly KEY_LAST_SYNC_TIME: string = 'webdav_last_sync_time';

  private static cachedUsername: string = '';
  private static cachedPassword: string = '';
  private static initPromise: Promise<void> | null = null;

  static init(): Promise<void> {
    if (WebDavConfigRepository.initPromise === null) {
      WebDavConfigRepository.initPromise = WebDavConfigRepository.doInit();
    }
    return WebDavConfigRepository.initPromise;
  }

  private static async doInit(): Promise<void> {
    WebDavConfigRepository.cachedUsername =
      await CredentialStore.getString(WebDavConfigRepository.USERNAME_ALIAS);
    WebDavConfigRepository.cachedPassword =
      await CredentialStore.getString(WebDavConfigRepository.PASSWORD_ALIAS);
    if (WebDavConfigRepository.cachedUsername.length > 0 &&
      WebDavConfigRepository.cachedPassword.length > 0) {
      Logger.info(`${TAG}: credentials restored (backend=${CredentialStore.backendName()})`);
    }
  }

  static isConfigured(): boolean {
    return WebDavConfigRepository.cachedUsername.length > 0 &&
      WebDavConfigRepository.cachedPassword.length > 0 &&
      SettingsRepository.getString(SettingsRepository.KEY_WEBDAV_SERVER_URL, '').length > 0;
  }

  static usernamePreview(): string {
    return WebDavConfigRepository.cachedUsername;
  }

  static async saveConfig(serverUrl: string, basePath: string, username: string,
    password: string): Promise<boolean> {
    const normalizedServer = normalizeWebDavServerUrl(serverUrl);
    const normalizedPath = normalizeWebDavBasePath(basePath);
    const normalizedUsername = username.trim();
    if (normalizedUsername.length === 0 || password.length === 0) {
      return false;
    }
    const usernameSaved = await CredentialStore.putString(
      WebDavConfigRepository.USERNAME_ALIAS, normalizedUsername);
    const passwordSaved = await CredentialStore.putString(
      WebDavConfigRepository.PASSWORD_ALIAS, password);
    WebDavConfigRepository.cachedUsername = normalizedUsername;
    WebDavConfigRepository.cachedPassword = password;
    SettingsRepository.setString(SettingsRepository.KEY_WEBDAV_SERVER_URL, normalizedServer);
    SettingsRepository.setString(SettingsRepository.KEY_WEBDAV_BASE_PATH, normalizedPath);
    return usernameSaved && passwordSaved;
  }

  static async loadConfig(): Promise<WebDavSyncConfig | null> {
    await WebDavConfigRepository.init();
    if (!WebDavConfigRepository.isConfigured()) {
      return null;
    }
    const config = new WebDavSyncConfig();
    config.serverUrl = SettingsRepository.getString(SettingsRepository.KEY_WEBDAV_SERVER_URL, '');
    config.basePath = SettingsRepository.getString(SettingsRepository.KEY_WEBDAV_BASE_PATH, '');
    config.username = WebDavConfigRepository.cachedUsername;
    config.password = WebDavConfigRepository.cachedPassword;
    return config;
  }

  static async clear(): Promise<void> {
    await CredentialStore.remove(WebDavConfigRepository.USERNAME_ALIAS);
    await CredentialStore.remove(WebDavConfigRepository.PASSWORD_ALIAS);
    WebDavConfigRepository.cachedUsername = '';
    WebDavConfigRepository.cachedPassword = '';
    SettingsRepository.setString(SettingsRepository.KEY_WEBDAV_SERVER_URL, '');
    SettingsRepository.setString(SettingsRepository.KEY_WEBDAV_BASE_PATH, '');
    await AppPreferences.putString(WebDavConfigRepository.KEY_LAST_REMOTE_FINGERPRINT, '');
    await AppPreferences.putNumber(WebDavConfigRepository.KEY_LAST_SYNC_TIME, 0);
  }

  static async getLastRemoteFingerprint(): Promise<string> {
    return AppPreferences.getString(WebDavConfigRepository.KEY_LAST_REMOTE_FINGERPRINT, '');
  }

  static async saveLastRemoteFingerprint(fingerprint: string): Promise<void> {
    await AppPreferences.putString(WebDavConfigRepository.KEY_LAST_REMOTE_FINGERPRINT, fingerprint);
  }

  static async saveLastSyncTime(nowMs: number): Promise<void> {
    await AppPreferences.putNumber(WebDavConfigRepository.KEY_LAST_SYNC_TIME, nowMs);
  }

  static async getLastSyncTime(): Promise<number> {
    return AppPreferences.getNumber(WebDavConfigRepository.KEY_LAST_SYNC_TIME, 0);
  }
}
