import { Logger } from '../../app/Logger';
import { Constants } from '../../app/Constants';
import { SettingsRepository } from '../SettingsRepository';
import { HttpClient } from '../../network/HttpClient';
import { CredentialStore } from './CredentialStore';
import { parseRawCookieText } from './RawCookieTextParser';
import {
  BiliAuthBundle,
  validateAndSanitizeBiliCookies,
  evaluateBiliAuthHealth,
  BiliAuthHealth,
  biliMidFromCookies,
  buildBiliCookieHeader,
  biliCookieKeysForLog
} from './BiliAuth';

const BILI_PASSPORT_ORIGIN: string = 'https://passport.bilibili.com/';

/**
 * Bilibili login cookie repository: persists the auth bundle through
 * CredentialStore (asset-backed), exposes login state through the
 * np.bilibili_logged setting, and seeds the shared HttpClient cookie jar for
 * api.bilibili.com / passport.bilibili.com (mirrors Android
 * BiliCookieRepository + BiliClient.getEffectiveCookies).
 */
export class BiliCookieRepository {
  static readonly ALIAS: string = 'bili_auth_bundle'; // aligned with the Android prefs key
  private static bundle: BiliAuthBundle = new BiliAuthBundle();
  private static initPromise: Promise<void> | null = null;

  static init(): Promise<void> {
    if (BiliCookieRepository.initPromise !== null) {
      return BiliCookieRepository.initPromise;
    }
    BiliCookieRepository.initPromise = BiliCookieRepository.doInit();
    return BiliCookieRepository.initPromise;
  }

  private static async doInit(): Promise<void> {
    const raw = await CredentialStore.getString(BiliCookieRepository.ALIAS);
    if (raw.length > 0) {
      BiliCookieRepository.bundle = BiliAuthBundle.fromJson(raw);
      if (BiliCookieRepository.bundle.cookies.size > 0) {
        Logger.info(`bili auth restored: keys=${biliCookieKeysForLog(BiliCookieRepository.bundle.cookies)}`);
      }
    }
    if (BiliCookieRepository.bundle.hasLoginCookies()) {
      BiliCookieRepository.seedHttpClient();
      SettingsRepository.setBoolean(SettingsRepository.KEY_BILIBILI_LOGGED, true);
    }
  }

  static isLoggedIn(): boolean {
    return BiliCookieRepository.bundle.hasLoginCookies();
  }

  static getCookies(): Map<string, string> {
    return BiliCookieRepository.bundle.cookies;
  }

  static getHealth(now: number = Date.now()): BiliAuthHealth {
    return evaluateBiliAuthHealth(BiliCookieRepository.bundle, now);
  }

  /** Numeric user mid from the persisted DedeUserID cookie (0 when unknown). */
  static getMid(): number {
    return biliMidFromCookies(BiliCookieRepository.bundle.cookies);
  }

  /**
   * Saves cookies obtained from the QR login flow (accumulated from passport
   * Set-Cookie responses). Returns false when validation rejects the set
   * (no usable SESSDATA).
   */
  static saveFromQrLogin(cookies: Map<string, string>): boolean {
    return BiliCookieRepository.saveInternal(cookies);
  }

  /** Saves cookies parsed from user-pasted text (backup import path). */
  static saveFromPastedText(raw: string): boolean {
    return BiliCookieRepository.saveInternal(parseRawCookieText(raw));
  }

  private static saveInternal(cookies: Map<string, string>): boolean {
    const validation = validateAndSanitizeBiliCookies(cookies);
    if (!validation.isAccepted) {
      Logger.warn(`bili cookie save rejected: rejectedKeys=${validation.rejectedKeys.join(',')} hasSessdata=${validation.hasLoginCookie}`);
      return false;
    }
    const next = new BiliAuthBundle();
    next.cookies = validation.sanitizedCookies;
    next.savedAt = Date.now();
    BiliCookieRepository.bundle = next.normalized(next.savedAt);
    CredentialStore.putString(BiliCookieRepository.ALIAS, BiliCookieRepository.bundle.toJson())
      .then((ok: boolean) => {
        if (!ok) {
          Logger.warn('bili auth bundle not persisted (credential backend failed)');
        }
      });
    BiliCookieRepository.seedHttpClient();
    SettingsRepository.setBoolean(SettingsRepository.KEY_BILIBILI_LOGGED, true);
    Logger.info(`bili login saved: keys=${biliCookieKeysForLog(BiliCookieRepository.bundle.cookies)}`);
    return true;
  }

  static async clear(): Promise<void> {
    await CredentialStore.remove(BiliCookieRepository.ALIAS);
    BiliCookieRepository.bundle = new BiliAuthBundle();
    HttpClient.clearCookies(`${Constants.BILI_BASE}/`);
    HttpClient.clearCookies(BILI_PASSPORT_ORIGIN);
    SettingsRepository.setBoolean(SettingsRepository.KEY_BILIBILI_LOGGED, false);
    Logger.info('bili login cleared');
  }

  static backendName(): string {
    return CredentialStore.backendName();
  }

  /** Injects the persisted cookies into the shared HTTP cookie jar (api + passport hosts). */
  static seedHttpClient(): void {
    if (BiliCookieRepository.bundle.cookies.size === 0) {
      return;
    }
    const header = buildBiliCookieHeader(BiliCookieRepository.bundle.cookies);
    HttpClient.seedCookies(`${Constants.BILI_BASE}/`, header);
    HttpClient.seedCookies(BILI_PASSPORT_ORIGIN, header);
  }
}
