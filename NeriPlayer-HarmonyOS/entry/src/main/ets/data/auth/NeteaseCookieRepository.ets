import { Logger } from '../../app/Logger';
import { Constants } from '../../app/Constants';
import { SettingsRepository } from '../SettingsRepository';
import { HttpClient } from '../../network/HttpClient';
import { CredentialStore } from './CredentialStore';
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
    if (NeteaseCookieRepository.bundle.hasLoginCookies()) {
      NeteaseCookieRepository.seedHttpClient();
    }
    // Sync the settings flag with the actually-restored bundle so the UI
    // reflects reality after a cold start (a failed credential restore also
    // clears a stale logged-in flag instead of showing a logged-out backend).
    SettingsRepository.setBoolean(
      SettingsRepository.KEY_NETEASE_LOGGED,
      NeteaseCookieRepository.bundle.hasLoginCookies()
    );
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
  static saveFromQrLogin(cookies: Map<string, string>): boolean {
    return NeteaseCookieRepository.saveInternal(cookies);
  }

  /** Saves cookies parsed from user-pasted text (backup import path). */
  static saveFromPastedText(raw: string): boolean {
    return NeteaseCookieRepository.saveInternal(parseRawCookieText(raw));
  }

  private static saveInternal(cookies: Map<string, string>): boolean {
    const validation = validateAndSanitizeNeteaseCookies(cookies);
    if (!validation.isAccepted) {
      Logger.warn(`netease cookie save rejected: rejectedKeys=${validation.rejectedKeys.join(',')} hasMusicU=${validation.hasLoginCookie}`);
      return false;
    }
    const next = new NeteaseAuthBundle();
    next.cookies = validation.sanitizedCookies;
    next.savedAt = Date.now();
    NeteaseCookieRepository.bundle = next.normalized(next.savedAt);
    CredentialStore.putString(NeteaseCookieRepository.ALIAS, NeteaseCookieRepository.bundle.toJson())
      .then((ok: boolean) => {
        if (!ok) {
          Logger.warn('netease auth bundle not persisted (credential backend failed)');
        }
      });
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
