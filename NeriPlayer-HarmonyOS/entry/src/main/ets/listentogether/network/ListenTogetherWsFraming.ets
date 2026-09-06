/**
 * Pure framing/limits half of listentogether/network/ws/ListenTogetherWebSocketClient.kt.
 *
 * Split out from the socket client so it stays importable by the local hypium
 * suite: `ListenTogetherWebSocketClient.ets` pulls in `@kit.NetworkKit`, which
 * the host-side test runner cannot load (same reasoning that isolated
 * `invite/ListenTogetherIdentity.ets` behind its UUID dependency in M7.1).
 *
 * Every string and numeric constant here is copied from upstream verbatim,
 * because they are wire-visible: the close codes reach the server, and the error
 * text reaches `isTerminalListenTogetherReconnectError`.
 */

/** Upstream: LISTEN_TOGETHER_MAX_WS_MESSAGE_CHARS (2 MiB of chars, not bytes). */
export const LISTEN_TOGETHER_MAX_WS_MESSAGE_CHARS: number = 2 * 1024 * 1024;

/** Upstream `text.take(256)` when reporting an oversize frame. */
export const LISTEN_TOGETHER_WS_ERROR_TEXT_PREVIEW_CHARS: number = 256;

/** Upstream `disconnect(code = 1000, reason = "client_closed")` defaults. */
export const LISTEN_TOGETHER_WS_CLOSE_CODE_NORMAL: number = 1000;
export const LISTEN_TOGETHER_WS_CLOSE_REASON_CLIENT_CLOSED: string = 'client_closed';

/** Upstream `disconnect(code = 1009, reason = "message_too_large")`. */
export const LISTEN_TOGETHER_WS_CLOSE_CODE_TOO_LARGE: number = 1009;
export const LISTEN_TOGETHER_WS_CLOSE_REASON_TOO_LARGE: string = 'message_too_large';

/** Upstream `sendLegacyPing()` payload, kept for pre-np_ping servers. */
export const LISTEN_TOGETHER_LEGACY_PING_FRAME: string = '{"type":"ping"}';

export function isListenTogetherWsMessageTooLarge(text: string): boolean {
  // Strictly greater than, matching upstream's `text.length > MAX`.
  return text.length > LISTEN_TOGETHER_MAX_WS_MESSAGE_CHARS;
}

/**
 * Only the first 256 chars of an offending frame are ever handed to a listener
 * or a log, so a 2 MiB payload cannot blow up the log pipeline.
 */
export function listenTogetherWsErrorTextPreview(text: string): string {
  return text.slice(0, LISTEN_TOGETHER_WS_ERROR_TEXT_PREVIEW_CHARS);
}

/** Upstream: IllegalArgumentException("WebSocket message too large: N chars"). */
export function listenTogetherWsOversizeErrorMessage(textLength: number): string {
  return `WebSocket message too large: ${textLength} chars`;
}

/**
 * Upstream: `{"type":"np_ping","t":$sentAtElapsedMs}` — hand-built rather than
 * serialized, so the exact byte layout (no spaces) is preserved. The timestamp
 * is truncated to an integer because upstream passes a `Long` from
 * `SystemClock.elapsedRealtime()`, and a fractional `t` would be a wire change.
 */
export function buildListenTogetherPingFrame(sentAtElapsedMs: number): string {
  return `{"type":"np_ping","t":${Math.trunc(sentAtElapsedMs)}}`;
}

/**
 * Upstream builds `<message> (http=<code> <reason>)` when okhttp hands the
 * failure callback a `Response`.
 *
 * HarmonyOS divergence, documented because it has a functional consequence:
 * `webSocket.on('error')` only yields a `BusinessError`, and that error's
 * `message` was measured on the emulator to be **empty** for a refused
 * connection — which is why the `WebSocketError` fallback below exists rather
 * than being defensive dead code. `on('headerReceive')` never fired for a failed
 * handshake either, so `httpStatus` is best-effort and normally absent — see
 * `ListenTogetherWebSocketClient.handshakeStatusOrNull`. When it is absent the
 * suffix is omitted entirely rather than emitted as `(http=0)`, which would
 * poison substring matching in the reconnect policy. When a reason phrase is
 * missing the trailing space is dropped, so `(http=410)` instead of
 * `(http=410 )`.
 */
export function listenTogetherWsFailureMessage(
  baseMessage: string,
  httpStatus?: number,
  httpReason?: string
): string {
  const message = baseMessage.length === 0 ? 'WebSocketError' : baseMessage;
  if (httpStatus === undefined || httpStatus <= 0) {
    return message;
  }
  const reason = (httpReason ?? '').trim();
  return reason.length === 0
    ? `${message} (http=${httpStatus})`
    : `${message} (http=${httpStatus} ${reason})`;
}
