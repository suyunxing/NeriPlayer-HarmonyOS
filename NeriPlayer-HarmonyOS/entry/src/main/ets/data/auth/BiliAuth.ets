/**
 * Pure Bilibili auth models and validation, ported from Android
 * data/auth/bili/BiliCookieRepository.kt. No platform imports: unit-testable
 * in the local hypium environment.
 *
 * Login semantics (mirrors Android evaluateBiliAuthHealth): only a non-blank
 * SESSDATA counts as logged in — buvid3/DedeUserID/bili_jct alone do not, and
 * saved cookies never expire by age.
 */

import { isValidCookieName, isIsoControl } from './RawCookieTextParser';

const BILI_SESSDATA_KEY: string = 'SESSDATA';

/** Keys reported by health evaluation (SESSDATA alone decides the state). */
export const BILI_LOGIN_COOKIE_KEYS: string[] = ['SESSDATA', 'DedeUserID', 'bili_jct'];

export class BiliCookieValidationResult {
  sanitizedCookies: Map<string, string> = new Map();
  rejectedKeys: string[] = [];

  get hasLoginCookie(): boolean {
    const v = this.sanitizedCookies.get(BILI_SESSDATA_KEY);
    return v !== undefined && v.length > 0;
  }

  get isAccepted(): boolean {
    return this.sanitizedCookies.size > 0 && this.hasLoginCookie;
  }
}

export function validateAndSanitizeBiliCookies(cookies: Map<string, string>): BiliCookieValidationResult {
  const result = new BiliCookieValidationResult();
  const seen = new Set<string>();
  cookies.forEach((rawValue: string, rawKey: string) => {
    const key = rawKey.trim();
    const value = rawValue.trim();
    const rejectedKey = key.length > 0 ? key : '<blank>';
    const ok = key.length > 0 && isValidCookieName(key) && value.length > 0
      && !isIsoControl(value) && value.indexOf(';') < 0;
    if (!ok) {
      if (!seen.has(rejectedKey)) {
        seen.add(rejectedKey);
        result.rejectedKeys.push(rejectedKey);
      }
      return;
    }
    result.sanitizedCookies.set(key, value);
  });
  return result;
}

export enum BiliAuthHealthState {
  MISSING = 0,
  VALID = 1
}

export class BiliAuthHealth {
  state: BiliAuthHealthState = BiliAuthHealthState.MISSING;
  savedAt: number = 0;
  checkedAt: number = 0;
  ageMs: number = 0;
  loginCookieKeys: string[] = [];
}

export class BiliAuthBundle {
  cookies: Map<string, string> = new Map();
  savedAt: number = 0;

  hasLoginCookies(): boolean {
    const v = this.cookies.get(BILI_SESSDATA_KEY);
    return v !== undefined && v.length > 0;
  }

  normalized(savedAt: number = this.savedAt): BiliAuthBundle {
    const out = new BiliAuthBundle();
    this.cookies.forEach((value: string, key: string) => {
      if (key.length > 0) {
        out.cookies.set(key, value);
      }
    });
    out.savedAt = savedAt;
    return out;
  }

  toJson(): string {
    const parts: string[] = [];
    this.cookies.forEach((value: string, key: string) => {
      parts.push(`${JSON.stringify(key)}:${JSON.stringify(value)}`);
    });
    return `{"cookies":{${parts.join(',')}},"savedAt":${this.savedAt}}`;
  }

  static fromJson(json: string): BiliAuthBundle {
    const out = new BiliAuthBundle();
    try {
      const root = JSON.parse(json) as Record<string, Object>;
      const cookiesRaw = root['cookies'];
      if (cookiesRaw !== undefined && cookiesRaw !== null) {
        const cookiesRecord = cookiesRaw as Record<string, Object>;
        for (const key of Object.keys(cookiesRecord)) {
          const v = cookiesRecord[key];
          out.cookies.set(key, v === undefined || v === null ? '' : String(v));
        }
      }
      const savedAtRaw = root['savedAt'];
      out.savedAt = savedAtRaw === undefined || savedAtRaw === null ? 0 : Number(savedAtRaw);
      return out.normalized(out.savedAt);
    } catch (error) {
      return new BiliAuthBundle();
    }
  }
}

export function evaluateBiliAuthHealth(bundle: BiliAuthBundle, now: number): BiliAuthHealth {
  const health = new BiliAuthHealth();
  const normalized = bundle.normalized(bundle.savedAt);
  if (!normalized.hasLoginCookies()) {
    health.checkedAt = now;
    health.savedAt = normalized.savedAt;
    health.state = BiliAuthHealthState.MISSING;
    return health;
  }
  const loginCookieKeys: string[] = [];
  for (const key of BILI_LOGIN_COOKIE_KEYS) {
    const v = normalized.cookies.get(key);
    if (v !== undefined && v.length > 0) {
      loginCookieKeys.push(key);
    }
  }
  health.checkedAt = now;
  health.savedAt = normalized.savedAt;
  health.state = BiliAuthHealthState.VALID;
  health.loginCookieKeys = loginCookieKeys;
  health.ageMs = normalized.savedAt > 0 ? Math.max(0, now - normalized.savedAt) : Number.MAX_SAFE_INTEGER;
  return health;
}

/**
 * Extracts the numeric user mid from DedeUserID (Android LibraryViewModel:
 * cookies["DedeUserID"].toLongOrNull() ?: 0). Returns 0 when absent/invalid.
 */
export function biliMidFromCookies(cookies: Map<string, string>): number {
  const raw = cookies.get('DedeUserID');
  if (raw === undefined) {
    return 0;
  }
  const mid = Number(raw);
  return Number.isFinite(mid) && mid > 0 ? Math.floor(mid) : 0;
}

/** Builds the Cookie header value for Bilibili requests (plain join, no fallbacks). */
export function buildBiliCookieHeader(cookies: Map<string, string>): string {
  const parts: string[] = [];
  cookies.forEach((value: string, key: string) => {
    parts.push(`${key}=${value}`);
  });
  return parts.join('; ');
}

/** Redacts a cookie map for logging: keys kept, values masked. */
export function biliCookieKeysForLog(cookies: Map<string, string>): string {
  const keys: string[] = [];
  cookies.forEach((_value: string, key: string) => {
    keys.push(key);
  });
  return keys.join(',');
}
