// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Port of listentogether/mapping/ListenTogetherStreamUrlPolicy.kt.
 *
 * Stream URLs arrive from the room server and from other members, so a
 * candidate only reaches the player when its host is on the per-channel
 * whitelist: an attacker-controlled direct link would otherwise be fetched with
 * this client's identity and headers.
 *
 * Divergences from okhttp `toHttpUrlOrNull()`:
 * - control characters are rejected anywhere in the candidate, while
 *   `" < > { } | \ ^ \`` are only rejected inside the host (okhttp
 *   percent-encodes them in the path/query instead of failing);
 * - the host is not IDN/percent-decoded, so a punycode-escaped or
 *   percent-escaped host is rejected rather than normalized. Strictly narrower:
 *   a blocked candidate just falls back to local stream resolution;
 * - the channel id is normalized first, because this app stores the YouTube
 *   Music channel locally as "youtube_music" while the wire value is
 *   "youtubeMusic" (Android only ever holds the wire value).
 *
 * A blocked candidate is reported through an optional listener instead of
 * NPLogger so the policy keeps zero platform imports and stays loadable in the
 * local unit tests. Only the host is reported, never the full URL, which may
 * carry signed query parameters.
 */
import { ListenTogetherChannels, normalizedListenTogetherChannelId } from '../protocol/ListenTogetherChannels';

export const MAX_LISTEN_TOGETHER_STREAM_URL_CANDIDATES: number = 3;

/** `(channelId, host)`; mirrors the Android warning without the URL itself. */
export type ListenTogetherBlockedStreamUrlListener = (channelId: string, host: string) => void;

const STREAM_URL_HOST_REGEX: RegExp = /^[A-Za-z0-9._-]+$/;

function hasControlCharacters(text: string): boolean {
  for (let i = 0; i < text.length; i++) {
    const code = text.charCodeAt(i);
    if (code <= 0x20 || code === 0x7F) {
      return true;
    }
  }
  return false;
}

function firstIndexOfAny(text: string, chars: string[]): number {
  let found = -1;
  for (const ch of chars) {
    const index = text.indexOf(ch);
    if (index >= 0 && (found < 0 || index < found)) {
      found = index;
    }
  }
  return found;
}

/** okhttp `HttpUrl.host` equivalent: lower-cased, userinfo and port stripped. */
function streamUrlHostOrNull(candidate: string): string | null {
  if (hasControlCharacters(candidate)) {
    return null;
  }
  const schemeEnd = candidate.indexOf('://');
  if (schemeEnd <= 0) {
    return null;
  }
  const scheme = candidate.substring(0, schemeEnd).toLowerCase();
  if (scheme !== 'https' && scheme !== 'http') {
    return null;
  }
  const hierarchical = candidate.substring(schemeEnd + 3);
  const authorityEnd = firstIndexOfAny(hierarchical, ['/', '?', '#']);
  const authority = authorityEnd < 0 ? hierarchical : hierarchical.substring(0, authorityEnd);
  // Must take what follows the LAST '@': "https://music.126.net@evil.com/x"
  // has host "evil.com", and reading the userinfo instead would let any URL
  // claim a whitelisted host.
  const at = authority.lastIndexOf('@');
  const hostAndPort = at < 0 ? authority : authority.substring(at + 1);
  const colon = hostAndPort.indexOf(':');
  const host = (colon < 0 ? hostAndPort : hostAndPort.substring(0, colon)).toLowerCase();
  if (host.length === 0 || !STREAM_URL_HOST_REGEX.test(host)) {
    return null;
  }
  return host;
}

function matchesHost(host: string, domain: string): boolean {
  return host === domain || host.endsWith(`.${domain}`);
}

function isTrustedStreamUrlHost(channelId: string, host: string): boolean {
  const channel = normalizedListenTogetherChannelId(channelId);
  if (channel === ListenTogetherChannels.NETEASE) {
    return matchesHost(host, 'music.126.net');
  }
  if (channel === ListenTogetherChannels.BILIBILI) {
    return matchesHost(host, 'bilivideo.com') ||
      matchesHost(host, 'bilivideo.cn') ||
      matchesHost(host, 'hdslb.com');
  }
  if (channel === ListenTogetherChannels.YOUTUBE_MUSIC) {
    return matchesHost(host, 'googlevideo.com') ||
      matchesHost(host, 'youtube.com') ||
      matchesHost(host, 'youtube-nocookie.com');
  }
  return false;
}

/** Returns the trimmed candidate unchanged when its host is whitelisted. */
export function trustedListenTogetherStreamUrl(
  channelId: string,
  streamUrl: string | null,
  onBlocked: ListenTogetherBlockedStreamUrlListener | null = null
): string | null {
  const candidate = streamUrl === null ? '' : streamUrl.trim();
  if (candidate.length === 0) {
    return null;
  }
  const host = streamUrlHostOrNull(candidate);
  if (host === null) {
    return null;
  }
  if (!isTrustedStreamUrlHost(channelId, host)) {
    if (onBlocked !== null) {
      onBlocked(channelId, host);
    }
    return null;
  }
  return candidate;
}

/** Kotlin `buildList { ... }.distinct().take(maxCount)`; legacy value goes last. */
export function trustedListenTogetherStreamUrls(
  channelId: string,
  streamUrls: string[] | null,
  legacyStreamUrl: string | null = null,
  maxCount: number = MAX_LISTEN_TOGETHER_STREAM_URL_CANDIDATES,
  onBlocked: ListenTogetherBlockedStreamUrlListener | null = null
): string[] {
  if (maxCount <= 0) {
    return [];
  }
  const candidates: string[] = [];
  if (streamUrls !== null) {
    for (const candidate of streamUrls) {
      const trusted = trustedListenTogetherStreamUrl(channelId, candidate, onBlocked);
      if (trusted !== null) {
        candidates.push(trusted);
      }
    }
  }
  const trustedLegacy = trustedListenTogetherStreamUrl(channelId, legacyStreamUrl, onBlocked);
  if (trustedLegacy !== null) {
    candidates.push(trustedLegacy);
  }
  const distinct: string[] = [];
  for (const candidate of candidates) {
    if (distinct.indexOf(candidate) < 0) {
      distinct.push(candidate);
      if (distinct.length >= maxCount) {
        break;
      }
    }
  }
  return distinct;
}
