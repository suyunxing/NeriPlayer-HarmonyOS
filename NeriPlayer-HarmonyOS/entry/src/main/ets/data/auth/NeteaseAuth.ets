// SPDX-License-Identifier: GPL-3.0

/**
 * Pure NetEase auth models and validation, ported from Android
 * data/auth/netease/NeteaseCookieRepository.kt and data/auth/common/RawCookieTextParser.kt.
 * No platform imports: unit-testable in the local hypium environment.
 */

import { isValidCookieName, isIsoControl, parseRawCookieText } from './RawCookieTextParser';

export { parseRawCookieText };

export const NETEASE_FALLBACK_OS: string = 'pc';
export const NETEASE_FALLBACK_APPVER: string = '8.10.35';

const NETEASE_LOGIN_COOKIE_KEYS: string[] = ['MUSIC_U'];

export class NeteaseCookieValidationResult {
  sanitizedCookies: Map<string, string> = new Map();
  rejectedKeys: string[] = [];

  get hasLoginCookie(): boolean {
    for (const key of NETEASE_LOGIN_COOKIE_KEYS) {
      const v = this.sanitizedCookies.get(key);
      if (v !== undefined && v.length > 0) {
        return true;
      }
    }
    return false;
  }

  get isAccepted(): boolean {
    return this.sanitizedCookies.size > 0 && this.hasLoginCookie;
  }
}

export function validateAndSanitizeNeteaseCookies(
  cookies: Map<string, string>,
  includeFallbackCookies: boolean = true
): NeteaseCookieValidationResult {
  const result = new NeteaseCookieValidationResult();
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
    if (!seen.has(key)) {
      seen.add(key);
    }
    result.sanitizedCookies.set(key, value);
  });
  if (includeFallbackCookies && result.sanitizedCookies.size > 0) {
    if (!result.sanitizedCookies.has('os')) {
      result.sanitizedCookies.set('os', NETEASE_FALLBACK_OS);
    }
    if (!result.sanitizedCookies.has('appver')) {
      result.sanitizedCookies.set('appver', NETEASE_FALLBACK_APPVER);
    }
  }
  return result;
}

export enum NeteaseAuthHealthState {
  MISSING = 0,
  VALID = 1
}

export class NeteaseAuthHealth {
  state: NeteaseAuthHealthState = NeteaseAuthHealthState.MISSING;
  savedAt: number = 0;
  checkedAt: number = 0;
  ageMs: number = 0;
  loginCookieKeys: string[] = [];
}

export class NeteaseAuthBundle {
  cookies: Map<string, string> = new Map();
  savedAt: number = 0;

  hasLoginCookies(): boolean {
    for (const key of NETEASE_LOGIN_COOKIE_KEYS) {
      const v = this.cookies.get(key);
      if (v !== undefined && v.length > 0) {
        return true;
      }
    }
    return false;
  }

  normalized(savedAt: number = this.savedAt): NeteaseAuthBundle {
    const out = new NeteaseAuthBundle();
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

  static fromJson(json: string): NeteaseAuthBundle {
    const out = new NeteaseAuthBundle();
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
      return new NeteaseAuthBundle();
    }
  }
}

export function evaluateNeteaseAuthHealth(bundle: NeteaseAuthBundle, now: number): NeteaseAuthHealth {
  const health = new NeteaseAuthHealth();
  const normalized = bundle.normalized(bundle.savedAt);
  const loginCookieKeys: string[] = [];
  for (const key of NETEASE_LOGIN_COOKIE_KEYS) {
    const v = normalized.cookies.get(key);
    if (v !== undefined && v.length > 0) {
      loginCookieKeys.push(key);
    }
  }
  health.checkedAt = now;
  health.savedAt = normalized.savedAt;
  if (loginCookieKeys.length === 0) {
    health.state = NeteaseAuthHealthState.MISSING;
    return health;
  }
  health.state = NeteaseAuthHealthState.VALID;
  health.loginCookieKeys = loginCookieKeys;
  health.ageMs = normalized.savedAt > 0 ? Math.max(0, now - normalized.savedAt) : Number.MAX_SAFE_INTEGER;
  return health;
}

/**
 * Builds the Cookie header value for NetEase requests, adding the os/appver
 * fallbacks when missing (mirrors NeteaseClient.buildPersistedCookieHeader).
 */
export function buildNeteaseCookieHeader(cookies: Map<string, string>): string {
  const merged = new Map<string, string>();
  cookies.forEach((value: string, key: string) => {
    merged.set(key, value);
  });
  if (merged.size > 0) {
    if (!merged.has('os')) {
      merged.set('os', NETEASE_FALLBACK_OS);
    }
    if (!merged.has('appver')) {
      merged.set('appver', NETEASE_FALLBACK_APPVER);
    }
  }
  const parts: string[] = [];
  merged.forEach((value: string, key: string) => {
    parts.push(`${key}=${value}`);
  });
  return parts.join('; ');
}

/** Redacts a cookie map for logging: keys kept, values masked. */
export function cookieKeysForLog(cookies: Map<string, string>): string {
  const keys: string[] = [];
  cookies.forEach((_value: string, key: string) => {
    keys.push(key);
  });
  return keys.join(',');
}
