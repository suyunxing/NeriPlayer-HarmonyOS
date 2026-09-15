// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Port of listentogether/invite/ListenTogetherInviteParser.kt.
 *
 * Accepts either a bare `neriplayer://listen-together/join?...` URI or a block
 * of shared text containing one. Everything an invite carries comes from an
 * untrusted source, so each field is re-validated and a non-https base URL is
 * dropped (and flagged) rather than trusted.
 *
 * Divergences from `java.net.URI` + `URLDecoder`:
 * - the path is compared raw instead of percent-decoded, so `%6Aoin` is
 *   rejected here while Android would accept it (strictly narrower);
 * - `decodeURIComponent` throws on invalid UTF-8 byte sequences where
 *   `URLDecoder` substitutes replacement characters; both end up discarding the
 *   affected key/value pair.
 */
import { ListenTogetherInvite } from './ListenTogetherInvite';
import { configuredListenTogetherInviteBaseUrlOrNull } from './ListenTogetherBaseUrlResolver';
import {
  LISTEN_TOGETHER_INVITE_HOST,
  LISTEN_TOGETHER_INVITE_JOIN_PATH,
  LISTEN_TOGETHER_INVITE_SCHEME
} from './ListenTogetherInviteBuilder';
import { hasIllegalUriCharacters } from '../network/ListenTogetherBaseUrl';
import {
  normalizeListenTogetherRoomId,
  sanitizeListenTogetherJoinSecretOrNull,
  validateListenTogetherNickname,
  validateListenTogetherRoomId
} from '../validation/ListenTogetherFieldValidation';

const LISTEN_TOGETHER_INVITE_REGEX: RegExp = /neriplayer:\/\/listen-together\/join\?[^\s]+/i;

const SCHEME_REGEX: RegExp = /^[A-Za-z][A-Za-z0-9+\-.]*$/;

class InviteUriParts {
  scheme: string = '';
  host: string = '';
  path: string = '';
  rawQuery: string | null = null;
}

function firstIndexOfAny(text: string, chars: string[], fromIndex: number): number {
  let found = -1;
  for (const ch of chars) {
    const index = text.indexOf(ch, fromIndex);
    if (index >= 0 && (found < 0 || index < found)) {
      found = index;
    }
  }
  return found;
}

/** Strips userinfo and port, mirroring `URI.getHost()` for a server authority. */
function hostOfAuthority(authority: string): string {
  const at = authority.lastIndexOf('@');
  const hostAndPort = at < 0 ? authority : authority.substring(at + 1);
  if (hostAndPort.startsWith('[')) {
    const close = hostAndPort.indexOf(']');
    return close < 0 ? hostAndPort : hostAndPort.substring(0, close + 1);
  }
  const colon = hostAndPort.indexOf(':');
  return colon < 0 ? hostAndPort : hostAndPort.substring(0, colon);
}

function parseInviteUriParts(rawText: string): InviteUriParts | null {
  if (hasIllegalUriCharacters(rawText)) {
    return null;
  }
  const schemeEnd = rawText.indexOf(':');
  if (schemeEnd <= 0) {
    return null;
  }
  const scheme = rawText.substring(0, schemeEnd);
  if (!SCHEME_REGEX.test(scheme)) {
    return null;
  }
  const afterScheme = rawText.substring(schemeEnd + 1);
  if (!afterScheme.startsWith('//')) {
    return null;
  }
  const hierarchical = afterScheme.substring(2);
  const authorityEnd = firstIndexOfAny(hierarchical, ['/', '?', '#'], 0);
  const authority = authorityEnd < 0 ? hierarchical : hierarchical.substring(0, authorityEnd);
  const parts = new InviteUriParts();
  parts.scheme = scheme;
  parts.host = hostOfAuthority(authority);
  if (authorityEnd < 0) {
    return parts;
  }
  const rest = hierarchical.substring(authorityEnd);
  const fragmentStart = rest.indexOf('#');
  const withoutFragment = fragmentStart < 0 ? rest : rest.substring(0, fragmentStart);
  const queryStart = withoutFragment.indexOf('?');
  if (queryStart < 0) {
    parts.path = withoutFragment;
  } else {
    parts.path = withoutFragment.substring(0, queryStart);
    parts.rawQuery = withoutFragment.substring(queryStart + 1);
  }
  return parts;
}

/** `URLDecoder.decode(value, "UTF-8")`: `+` means space, malformed input fails. */
function decodeInviteQueryComponent(value: string): string | null {
  try {
    return decodeURIComponent(value.split('+').join(' '));
  } catch (error) {
    return null;
  }
}

function decodeInviteQuery(rawQuery: string | null): Map<string, string> {
  const query = new Map<string, string>();
  if (rawQuery === null || rawQuery.trim().length === 0) {
    return query;
  }
  for (const pair of rawQuery.split('&')) {
    const separatorIndex = pair.indexOf('=');
    const rawKey = separatorIndex >= 0 ? pair.substring(0, separatorIndex) : pair;
    const rawValue = separatorIndex >= 0 ? pair.substring(separatorIndex + 1) : '';
    const decodedKey = decodeInviteQueryComponent(rawKey);
    if (decodedKey === null) {
      continue;
    }
    const key = decodedKey.trim();
    if (key.length === 0) {
      continue;
    }
    const decodedValue = decodeInviteQueryComponent(rawValue);
    if (decodedValue !== null) {
      query.set(key, decodedValue);
    }
  }
  return query;
}

function queryValue(query: Map<string, string>, key: string): string | null {
  const value = query.get(key);
  return value === undefined ? null : value;
}

function parseListenTogetherInviteInternal(rawText: string): ListenTogetherInvite | null {
  const parts = parseInviteUriParts(rawText);
  if (parts === null) {
    return null;
  }
  if (parts.scheme.toLowerCase() !== LISTEN_TOGETHER_INVITE_SCHEME) {
    return null;
  }
  if (parts.host.toLowerCase() !== LISTEN_TOGETHER_INVITE_HOST) {
    return null;
  }
  const pathSegments = parts.path.split('/').filter((segment: string): boolean => {
    return segment.trim().length > 0;
  });
  if (pathSegments.length === 0 || pathSegments[0] !== LISTEN_TOGETHER_INVITE_JOIN_PATH) {
    return null;
  }
  const query = decodeInviteQuery(parts.rawQuery);
  const rawRoomId = queryValue(query, 'roomId');
  const roomId = normalizeListenTogetherRoomId(rawRoomId === null ? '' : rawRoomId);
  if (validateListenTogetherRoomId(roomId) !== null) {
    return null;
  }
  let inviterNickname: string | null = null;
  const rawInviter = queryValue(query, 'inviter');
  if (rawInviter !== null) {
    const trimmed = rawInviter.trim();
    if (trimmed.length > 0 && validateListenTogetherNickname(trimmed) === null) {
      inviterNickname = trimmed;
    }
  }
  const rawBaseUrlValue = queryValue(query, 'baseUrl');
  const rawBaseUrl = rawBaseUrlValue === null ? '' : rawBaseUrlValue.trim();
  const normalizedBaseUrl = configuredListenTogetherInviteBaseUrlOrNull(rawBaseUrl);
  const joinSecret = sanitizeListenTogetherJoinSecretOrNull(queryValue(query, 'secret'));
  if (joinSecret === null) {
    return null;
  }
  return new ListenTogetherInvite(
    roomId,
    inviterNickname,
    normalizedBaseUrl,
    joinSecret,
    rawBaseUrl.length > 0 && normalizedBaseUrl === null
  );
}

/** Parses a bare invite URI, or finds one inside shared text. */
export function parseListenTogetherInvite(rawText: string | null): ListenTogetherInvite | null {
  const text = rawText === null ? '' : rawText.trim();
  if (text.length === 0) {
    return null;
  }
  const direct = parseListenTogetherInviteInternal(text);
  if (direct !== null) {
    return direct;
  }
  const match = LISTEN_TOGETHER_INVITE_REGEX.exec(text);
  if (match === null) {
    return null;
  }
  return parseListenTogetherInviteInternal(match[0]);
}
