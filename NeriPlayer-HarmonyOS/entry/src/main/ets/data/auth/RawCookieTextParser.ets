// SPDX-License-Identifier: GPL-3.0

/**
 * Shared cookie-text helpers, extracted from Android
 * data/auth/common/RawCookieTextParser.kt plus the RFC cookie-name character
 * check used by both platform auth validators. No platform imports so the
 * local hypium environment can unit-test them.
 */

const COOKIE_NAME_CHARS: string = "!#$%&'*+.^_`|~0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-";

export function isValidCookieName(key: string): boolean {
  if (key.length === 0) {
    return false;
  }
  for (const ch of key) {
    if (COOKIE_NAME_CHARS.indexOf(ch) < 0) {
      return false;
    }
  }
  return true;
}

export function isIsoControl(value: string): boolean {
  for (const ch of value) {
    const code = ch.charCodeAt(0);
    if (code < 0x20 || (code >= 0x7f && code <= 0x9f)) {
      return true;
    }
  }
  return false;
}

/**
 * Parses pasted cookie text ("k1=v1; k2=v2" possibly across lines) into a
 * map, mirroring Android parseRawCookieText.
 */
export function parseRawCookieText(raw: string): Map<string, string> {
  const out = new Map<string, string>();
  const segments = raw.split(/[;\r\n]+/);
  for (const rawSegment of segments) {
    const segment = rawSegment.trim();
    if (segment.length === 0) {
      continue;
    }
    const eq = segment.indexOf('=');
    if (eq <= 0) {
      continue;
    }
    const key = segment.substring(0, eq).trim();
    const value = segment.substring(eq + 1).trim();
    if (key.length > 0 && value.length > 0) {
      out.set(key, value);
    }
  }
  return out;
}
