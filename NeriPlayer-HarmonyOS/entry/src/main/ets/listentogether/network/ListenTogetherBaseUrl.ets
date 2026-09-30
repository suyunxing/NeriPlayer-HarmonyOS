// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Port of listentogether/network/http/ListenTogetherBaseUrl.kt.
 *
 * Android leans on `java.net.URI` for parsing; ArkTS has no URI parser in the
 * local test environment, so the accepted grammar is spelled out here. The
 * checks mirror what `URI(candidate)` would reject for realistic inputs:
 * illegal/control characters, a broken percent escape, a missing or non-http(s)
 * scheme, a missing authority, and any query or fragment.
 */

/** Characters `java.net.URI` never accepts in any component. */
const ILLEGAL_URI_CHARS: string = '"<>{}|\\^`';

const SCHEME_REGEX: RegExp = /^[A-Za-z][A-Za-z0-9+\-.]*$/;

function isHexDigit(code: number): boolean {
  return (code >= 0x30 && code <= 0x39) ||
    (code >= 0x41 && code <= 0x46) ||
    (code >= 0x61 && code <= 0x66);
}

/**
 * Rejects what the Java URI parser would throw on. Non-ASCII code points are
 * allowed: the single-argument URI constructor accepts them as "other"
 * characters, so a punycode-free host stays usable.
 *
 * Exported because the invite parser needs the same gate before it accepts a
 * `neriplayer://` URI.
 */
export function hasIllegalUriCharacters(text: string): boolean {
  for (let i = 0; i < text.length; i++) {
    const code = text.charCodeAt(i);
    if (code <= 0x20 || code === 0x7F) {
      return true;
    }
    const ch = text.charAt(i);
    if (ILLEGAL_URI_CHARS.includes(ch)) {
      return true;
    }
    if (ch === '%') {
      if (i + 2 >= text.length) {
        return true;
      }
      if (!isHexDigit(text.charCodeAt(i + 1)) || !isHexDigit(text.charCodeAt(i + 2))) {
        return true;
      }
    }
  }
  return false;
}

function trimTrailingSlashes(text: string): string {
  let end = text.length;
  while (end > 0 && text.charAt(end - 1) === '/') {
    end--;
  }
  return text.substring(0, end);
}

/**
 * `URI.normalize()` equivalent: drops `.` segments and `<segment>/..` pairs.
 * Empty segments and a leading `..` are preserved, matching the JDK (which does
 * not apply RFC 3986 remove_dot_segments to an absolute path's leading `..`).
 */
function normalizeUriPath(path: string): string {
  if (path.length === 0) {
    return '';
  }
  const segments = path.split('/');
  const out: string[] = [];
  const lastIndex = segments.length - 1;
  for (let i = 0; i <= lastIndex; i++) {
    const segment = segments[i];
    if (segment === '.') {
      if (i === lastIndex) {
        out.push('');
      }
      continue;
    }
    if (segment === '..') {
      const last = out.length > 0 ? out[out.length - 1] : '';
      if (last.length > 0 && last !== '..') {
        out.pop();
        if (i === lastIndex) {
          out.push('');
        }
      } else {
        out.push('..');
      }
      continue;
    }
    out.push(segment);
  }
  return out.join('/');
}

/**
 * Returns `scheme://authority[/path]` with the trailing slash removed, or null
 * when the input is not a usable http(s) base URL. The authority keeps its
 * original case, exactly like `URI.rawAuthority`.
 */
export function normalizedListenTogetherHttpBaseUrlOrNull(value: string): string | null {
  const candidate = trimTrailingSlashes(value.trim());
  if (candidate.length === 0) {
    return null;
  }
  if (hasIllegalUriCharacters(candidate)) {
    return null;
  }
  // A query or fragment makes URI.rawQuery / rawFragment non-null -> rejected.
  if (candidate.includes('?') || candidate.includes('#')) {
    return null;
  }
  const schemeEnd = candidate.indexOf(':');
  if (schemeEnd <= 0) {
    return null;
  }
  const scheme = candidate.substring(0, schemeEnd).toLowerCase();
  if (!SCHEME_REGEX.test(scheme)) {
    return null;
  }
  if (scheme !== 'http' && scheme !== 'https') {
    return null;
  }
  const afterScheme = candidate.substring(schemeEnd + 1);
  // Without "//" the URI is opaque and rawAuthority would be null.
  if (!afterScheme.startsWith('//')) {
    return null;
  }
  const hierarchical = afterScheme.substring(2);
  const pathStart = hierarchical.indexOf('/');
  const authority = pathStart < 0 ? hierarchical : hierarchical.substring(0, pathStart);
  if (authority.trim().length === 0) {
    return null;
  }
  const rawPath = pathStart < 0 ? '' : hierarchical.substring(pathStart);
  const normalizedPath = trimTrailingSlashes(normalizeUriPath(rawPath));
  if (normalizedPath.length === 0) {
    return `${scheme}://${authority}`;
  }
  const separator = normalizedPath.startsWith('/') ? '' : '/';
  return `${scheme}://${authority}${separator}${normalizedPath}`;
}

/** Throwing variant used where the caller has already validated the input. */
export function normalizeListenTogetherBaseUrl(value: string): string {
  const normalized = normalizedListenTogetherHttpBaseUrlOrNull(value);
  if (normalized === null) {
    throw new Error('ListenTogether baseUrl must use http or https');
  }
  return normalized;
}
