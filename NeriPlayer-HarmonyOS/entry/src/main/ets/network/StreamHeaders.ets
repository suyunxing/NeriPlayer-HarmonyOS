// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Pure stream request-header logic, ported from Android
 * core/player/engine/datasource/ConditionalHttpDataSourceFactory.kt.
 *
 * Bilibili CDN hosts reject audio stream requests without a web Referer and a
 * desktop User-Agent (HTTP 403), so headers must be attached when the
 * AVPlayer fetches the stream itself. Other platforms (NetEase) accept bare
 * requests. No platform imports: unit-testable in the local hypium
 * environment.
 */

export const BILI_STREAM_REFERER: string = 'https://www.bilibili.com';
export const BILI_STREAM_USER_AGENT: string =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

function hostOf(url: string): string {
  const start = url.indexOf('://');
  const rest = start >= 0 ? url.substring(start + 3) : url;
  const slash = rest.indexOf('/');
  const hostPort = slash >= 0 ? rest.substring(0, slash) : rest;
  const colon = hostPort.lastIndexOf(':');
  if (colon > 0 && hostPort.substring(colon + 1).match(/^\d+$/) !== null) {
    return hostPort.substring(0, colon);
  }
  return hostPort;
}

/** Bilibili stream CDN hosts (Android BiliAudioSelector.isBiliStreamHost). */
export function isBiliStreamUrl(url: string): boolean {
  const host = hostOf(url).toLowerCase();
  // Bilibili returns both bilivideo.com and bilivideo.cn/mcdn.bilivideo.cn
  // mirrors. Keep parity with Android's host predicate instead of assuming
  // every CDN URL ends in .bilivideo.com.
  // Match a complete bilivideo label (including .bilivideo.cn and
  // .mcdn.bilivideo.cn), while rejecting look-alike names such as
  // notbilivideo.com that merely contain the same characters.
  return host === 'bilivideo.com' || host === 'bilivideo.cn'
    || host.indexOf('.bilivideo.') >= 0
    || host.endsWith('.mountaintoys.cn');
}

/**
 * Headers required while the player fetches a Bilibili stream. Referer and
 * User-Agent are always forced; the cookie header (login state) is appended
 * only when the caller passes a non-blank value (Android buildBiliHeaders).
 */
export function buildBiliStreamHeaders(cookieHeader: string): Record<string, string> {
  const headers: Record<string, string> = {};
  headers['Referer'] = BILI_STREAM_REFERER;
  headers['User-Agent'] = BILI_STREAM_USER_AGENT;
  if (cookieHeader.trim().length > 0) {
    headers['Cookie'] = cookieHeader.trim();
  }
  return headers;
}

/**
 * Headers to attach to a network playback URL; empty record keeps the
 * current header-less behavior for every other source.
 */
export function streamHeadersFor(url: string, biliCookieHeader: string): Record<string, string> {
  if (!isBiliStreamUrl(url)) {
    return {};
  }
  return buildBiliStreamHeaders(biliCookieHeader);
}
