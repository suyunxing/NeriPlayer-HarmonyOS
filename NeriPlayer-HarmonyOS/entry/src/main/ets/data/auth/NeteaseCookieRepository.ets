// SPDX-License-Identifier: GPL-3.0

import { Logger } from '../../app/Logger';
import { Constants } from '../../app/Constants';
import { SettingsRepository } from '../SettingsRepository';
import { HttpClient } from '../../network/HttpClient';
import { CredentialStore } from './CredentialStore';
import { NeteaseApi } from '../../network/NeteaseApi';
import {
  NeteaseAuthBundle,
  validateAndSanitizeNeteaseCookies,
  parseRawCookieText,
  buildNeteaseCookieHeader,
  evaluateNeteaseAuthHealth,
  NeteaseAuthHealth,
  cookieKeysForLog
} from './NeteaseAuth';

/**
 * NetEase login cookie repository: persists the auth bundle through
 * CredentialStore (asset-backed), exposes login state via the
 * np.netease_logged setting, and seeds the shared HttpClient cookie jar so
 * weapi calls carry MUSIC_U/__csrf (mirrors Android NeteaseCookieRepository +
 * NeteaseClient.setPersistedCookies).
 */
export class NeteaseCookieRepository {
  static readonly ALIAS: string = 'netease_auth_bundle'; // aligned with the Android prefs key
  private static bundle: NeteaseAuthBundle = new NeteaseAuthBundle();
  private static initPromise: Promise<void> | null = null;

  static init(): Promise<void> {
    if (NeteaseCookieRepository.initPromise !== null) {
      return NeteaseCookieRepository.initPromise;
    }
    NeteaseCookieRepository.initPromise = NeteaseCookieRepository.doInit();
    return NeteaseCookieRepository.initPromise;
  }

  private static async doInit(): Promise<void> {
    const raw = await CredentialStore.getString(NeteaseCookieRepository.ALIAS);
    if (raw.length > 0) {
      NeteaseCookieRepository.bundle = NeteaseAuthBundle.fromJson(raw);
      if (NeteaseCookieRepository.bundle.cookies.size > 0) {
        Logger.info(`netease auth restored: keys=${cookieKeysForLog(NeteaseCookieRepository.bundle.cookies)}`);
      }
    }
    const restored = NeteaseCookieRepository.bundle.hasLoginCookies();
    if (restored) {
      NeteaseCookieRepository.seedHttpClient();
    }
    // Re-derive the settings flag from the restored bundle. The in-memory
    // CredentialStore fallback is by design process-lifetime-only, so a cold
    // start always re-reads from the real backend: a false flag here reflects
    // an actually-missing bundle (logged out, expired, or cleared) and must
    // overwrite a stale true, never the other way round.
    SettingsRepository.setBoolean(
      SettingsRepository.KEY_NETEASE_LOGGED,
      restored
    );
    if (restored) {
      // The restored MUSIC_U must be part of the next weapi session; if an
      // anonymous session somehow started before this point, discard it.
      NeteaseApi.resetSession();
    }
  }

  static isLoggedIn(): boolean {
    return NeteaseCookieRepository.bundle.hasLoginCookies();
  }

  static getCookies(): Map<string, string> {
    return NeteaseCookieRepository.bundle.cookies;
  }

  static getHealth(now: number = Date.now()): NeteaseAuthHealth {
    return evaluateNeteaseAuthHealth(NeteaseCookieRepository.bundle, now);
  }

  /**
   * Saves cookies obtained from the QR login flow (already accumulated from
   * response Set-Cookie headers). Returns false when validation rejects the
   * set (no usable MUSIC_U etc.).
   */
  static async saveFromQrLogin(cookies: Map<string, string>): Promise<boolean> {
    return NeteaseCookieRepository.saveInternal(cookies);
  }

  /** Saves cookies parsed from user-pasted text (backup import path). */
  static async saveFromPastedText(raw: string): Promise<boolean> {
    return NeteaseCookieRepository.saveInternal(parseRawCookieText(raw));
  }

  /** Saves cookies harvested from the embedded web login page. */
  static async saveFromWebLogin(cookies: Map<string, string>): Promise<boolean> {
    return NeteaseCookieRepository.saveInternal(cookies);
  }

  /**
   * Validation is synchronous, but the credential write must be awaited:
   * returning before `putString` settles is exactly how a process kill right
   * after login lost the bundle (login toast shown, nothing on disk).
   */
  private static async saveInternal(cookies: Map<string, string>): Promise<boolean> {
    const validation = validateAndSanitizeNeteaseCookies(cookies);
    if (!validation.isAccepted) {
      Logger.warn(`netease cookie save rejected: rejectedKeys=${validation.rejectedKeys.join(',')} hasMusicU=${validation.hasLoginCookie}`);
      return false;
    }
    const next = new NeteaseAuthBundle();
    next.cookies = validation.sanitizedCookies;
    next.savedAt = Date.now();
    NeteaseCookieRepository.bundle = next.normalized(next.savedAt);
    const persisted = await CredentialStore.putString(NeteaseCookieRepository.ALIAS, NeteaseCookieRepository.bundle.toJson());
    if (!persisted) {
      // Refuse to report success: the bundle would vanish on process death.
      NeteaseCookieRepository.bundle = new NeteaseAuthBundle();
      Logger.error('netease login not saved: credential backend rejected the write');
      return false;
    }
    NeteaseCookieRepository.seedHttpClient();
    SettingsRepository.setBoolean(SettingsRepository.KEY_NETEASE_LOGGED, true);
    Logger.info(`netease login saved: keys=${cookieKeysForLog(NeteaseCookieRepository.bundle.cookies)}`);
    return true;
  }

  static async clear(): Promise<void> {
    await CredentialStore.remove(NeteaseCookieRepository.ALIAS);
    NeteaseCookieRepository.bundle = new NeteaseAuthBundle();
    HttpClient.clearCookies(`${Constants.NETEASE_BASE}/`);
    SettingsRepository.setBoolean(SettingsRepository.KEY_NETEASE_LOGGED, false);
    Logger.info('netease login cleared');
  }

  static backendName(): string {
    return CredentialStore.backendName();
  }

  /** Injects the persisted cookies into the shared HTTP cookie jar. */
  static seedHttpClient(): void {
    if (NeteaseCookieRepository.bundle.cookies.size === 0) {
      return;
    }
    const header = buildNeteaseCookieHeader(NeteaseCookieRepository.bundle.cookies);
    HttpClient.seedCookies(`${Constants.NETEASE_BASE}/`, header);
  }
}
