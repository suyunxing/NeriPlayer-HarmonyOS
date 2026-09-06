/**
 * Port of listentogether/network/ws/ListenTogetherWsUrl.kt.
 *
 * Upstream builds the URL with okhttp: `encodedPath("/api/rooms/<id>/ws")`
 * replaces whatever path the base URL carried, so a base URL with a path prefix
 * still connects at the server root. That behaviour is reproduced verbatim.
 *
 * Two deliberate, documented divergences from okhttp:
 * - the token is percent-encoded with `encodeURIComponent`, which also escapes
 *   `+`, `/` and `=`. Every conformant server decodes them back, and it removes
 *   the `+`-decoded-as-space ambiguity okhttp leaves in place;
 * - the host case is preserved instead of lower-cased (DNS is case-insensitive,
 *   and the server-provided `wsUrl` is preferred whenever it is present).
 */
import { normalizeListenTogetherBaseUrl } from './ListenTogetherBaseUrl';

const LISTEN_TOGETHER_WS_TOKEN_PARAM: string = 'token';
const LISTEN_TOGETHER_REDACTED_TOKEN: string = '<redacted>';

export function listenTogetherRoomWsPath(roomId: string): string {
  return `/api/rooms/${roomId}/ws`;
}

export function buildListenTogetherWsUrl(baseUrl: string, roomId: string, token: string): string {
  const normalizedBase = normalizeListenTogetherBaseUrl(baseUrl);
  const schemeEnd = normalizedBase.indexOf('://');
  const scheme = normalizedBase.substring(0, schemeEnd);
  // The path from the base URL is intentionally dropped, matching encodedPath().
  const authority = normalizedBase.substring(schemeEnd + 3).split('/')[0];
  const wsScheme = scheme === 'https' ? 'wss' : 'ws';
  const query = `${LISTEN_TOGETHER_WS_TOKEN_PARAM}=${encodeURIComponent(token)}`;
  return `${wsScheme}://${authority}${listenTogetherRoomWsPath(roomId)}?${query}`;
}

/** Rebuilds worker-internal websocket placeholders from the public base URL. */
export function resolveListenTogetherWsUrl(
  baseUrl: string,
  roomId: string,
  token: string | null,
  serverWsUrl: string | null
): string | null {
  const candidate = serverWsUrl === null ? '' : serverWsUrl.trim();
  const lowered = candidate.toLowerCase();
  const internal = lowered.includes('://room.internal/') ||
    lowered.includes('://room.internal?') ||
    lowered.includes('://room.internal:');
  if (candidate.length > 0 && !internal) {
    return candidate;
  }
  const resolvedToken = token === null ? '' : token.trim();
  return resolvedToken.length === 0 ? null : buildListenTogetherWsUrl(baseUrl, roomId, resolvedToken);
}

/**
 * Log-safe form of a room socket URL: the token never reaches the log.
 *
 * Android hands http(s) URLs to okhttp and falls back to truncation for
 * anything else; since every URL built here is ws/wss (which okhttp rejects),
 * both platforms take the truncate-and-append path.
 */
export function redactListenTogetherWsUrlForLog(url: string | null): string | null {
  if (url === null) {
    return null;
  }
  const queryStart = url.indexOf('?');
  const base = queryStart < 0 ? url : url.substring(0, queryStart);
  return `${base}?${LISTEN_TOGETHER_WS_TOKEN_PARAM}=${LISTEN_TOGETHER_REDACTED_TOKEN}`;
}
