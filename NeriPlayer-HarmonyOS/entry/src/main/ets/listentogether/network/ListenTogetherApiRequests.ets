/**
 * Pure URL/header/error-shaping half of
 * listentogether/network/http/ListenTogetherApi.kt.
 *
 * Split from `ListenTogetherApi.ets` (which needs `@kit.NetworkKit`) so the
 * wire-visible parts stay unit-testable on the host: the endpoint paths, the
 * Bearer rule, the response-size ceiling and — most importantly — the exact
 * error-message shape, because `isTerminalListenTogetherReconnectError` matches
 * `(410)` inside it by substring. Changing the message punctuation silently
 * breaks terminal-error detection, so it is pinned by tests here.
 */
import { normalizedListenTogetherHttpBaseUrlOrNull, normalizeListenTogetherBaseUrl } from './ListenTogetherBaseUrl';

/** Upstream: LISTEN_TOGETHER_MAX_HTTP_RESPONSE_BYTES. */
export const LISTEN_TOGETHER_MAX_HTTP_RESPONSE_BYTES: number = 2 * 1024 * 1024;

/**
 * `/healthz` marker the server echoes. Upstream matches it case-insensitively,
 * so a body of `NeriPlayer-Listen-Together-Worker OK` still counts as reachable.
 */
export const LISTEN_TOGETHER_HEALTHZ_MARKER: string = 'neriplayer-listen-together-worker';

/** Upstream message strings for `testServerAvailability`; the UI maps on them. */
export const LISTEN_TOGETHER_TEST_INVALID_BASE_URL: string = 'invalid_base_url';
export const LISTEN_TOGETHER_TEST_REACHABLE: string = 'reachable';
export const LISTEN_TOGETHER_TEST_INVALID_RESPONSE: string = 'invalid_response';

/** Upstream: data class ListenTogetherServerTestResult(ok, message). */
export class ListenTogetherServerTestResult {
  ok: boolean = false;
  message: string = '';
}

export function listenTogetherServerTestResult(ok: boolean, message: string): ListenTogetherServerTestResult {
  const result = new ListenTogetherServerTestResult();
  result.ok = ok;
  result.message = message;
  return result;
}

// Room endpoints use the throwing normalizer, matching upstream's
// `baseUrl.normalizeBaseUrl()`: a malformed address must fail loudly rather than
// silently hit a default host.
export function listenTogetherCreateRoomUrl(baseUrl: string): string {
  return `${normalizeListenTogetherBaseUrl(baseUrl)}/api/rooms`;
}

export function listenTogetherJoinRoomUrl(baseUrl: string, roomId: string): string {
  return `${normalizeListenTogetherBaseUrl(baseUrl)}/api/rooms/${roomId}/join`;
}

export function listenTogetherRoomStateUrl(baseUrl: string, roomId: string): string {
  return `${normalizeListenTogetherBaseUrl(baseUrl)}/api/rooms/${roomId}/state`;
}

export function listenTogetherLeaveRoomUrl(baseUrl: string, roomId: string): string {
  return `${normalizeListenTogetherBaseUrl(baseUrl)}/api/rooms/${roomId}/leave`;
}

export function listenTogetherControlUrl(baseUrl: string, roomId: string): string {
  return `${normalizeListenTogetherBaseUrl(baseUrl)}/api/rooms/${roomId}/control`;
}

/**
 * Health probe URL, or null for an unusable address. Upstream deliberately uses
 * the non-throwing normalizer here so the settings dialog can report
 * `invalid_base_url` instead of crashing on user input.
 */
export function listenTogetherHealthzUrlOrNull(baseUrl: string): string | null {
  const normalized = normalizedListenTogetherHttpBaseUrlOrNull(baseUrl);
  return normalized === null ? null : `${normalized}/healthz`;
}

/**
 * Upstream: `bearerToken?.takeIf { it.isNotBlank() }`. A blank token must not
 * produce a `Bearer ` header — the server would reject the request outright
 * instead of treating it as anonymous.
 */
export function listenTogetherBearerHeaderOrNull(bearerToken: string | null | undefined): string | null {
  const token = (bearerToken ?? '').trim();
  return token.length === 0 ? null : `Bearer ${token}`;
}

/**
 * Upstream: IOException("ListenTogether GET/POST failed (<code>): <body>").
 *
 * The `(<code>)` parenthesised form is load-bearing: the reconnect policy looks
 * for the literal `(410)` to detect a closed room. `method` is upper-cased so a
 * caller passing 'get' cannot change the message shape.
 */
export function listenTogetherHttpErrorMessage(method: string, statusCode: number, body: string): string {
  return `ListenTogether ${method.toUpperCase()} failed (${statusCode}): ${body}`;
}

/** Upstream: IOException("ListenTogether response too large: N bytes"). */
export function listenTogetherOversizeResponseMessage(byteCount: number): string {
  return `ListenTogether response too large: ${byteCount} bytes`;
}

export function isListenTogetherResponseTooLarge(byteCount: number): boolean {
  // Strictly greater than, matching upstream's `> LISTEN_TOGETHER_MAX_...`.
  return byteCount > LISTEN_TOGETHER_MAX_HTTP_RESPONSE_BYTES;
}

/**
 * Maps a `/healthz` body to the test result. A 200 from an unrelated server (a
 * captive portal, a reverse proxy default page) must read as `invalid_response`
 * rather than success, which is why the marker check exists at all.
 */
export function listenTogetherHealthResultForBody(body: string): ListenTogetherServerTestResult {
  const looksLikeListenTogetherService = body.toLowerCase().includes(LISTEN_TOGETHER_HEALTHZ_MARKER);
  return looksLikeListenTogetherService
    ? listenTogetherServerTestResult(true, LISTEN_TOGETHER_TEST_REACHABLE)
    : listenTogetherServerTestResult(false, LISTEN_TOGETHER_TEST_INVALID_RESPONSE);
}
