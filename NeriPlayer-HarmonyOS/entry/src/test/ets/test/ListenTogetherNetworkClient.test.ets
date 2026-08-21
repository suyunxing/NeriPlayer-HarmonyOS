import { describe, it, expect } from '@ohos/hypium';
import {
  LISTEN_TOGETHER_MAX_RECONNECT_ATTEMPTS,
  isTerminalListenTogetherReconnectError,
  listenTogetherReconnectDelayBaseMs,
  listenTogetherReconnectDelayMs,
  listenTogetherReconnectDelayMsWithRandom
} from '../../../main/ets/listentogether/network/ListenTogetherReconnectPolicy';
import {
  LISTEN_TOGETHER_LEGACY_PING_FRAME,
  LISTEN_TOGETHER_MAX_WS_MESSAGE_CHARS,
  LISTEN_TOGETHER_WS_CLOSE_CODE_NORMAL,
  LISTEN_TOGETHER_WS_CLOSE_CODE_TOO_LARGE,
  LISTEN_TOGETHER_WS_CLOSE_REASON_CLIENT_CLOSED,
  LISTEN_TOGETHER_WS_CLOSE_REASON_TOO_LARGE,
  LISTEN_TOGETHER_WS_ERROR_TEXT_PREVIEW_CHARS,
  buildListenTogetherPingFrame,
  isListenTogetherWsMessageTooLarge,
  listenTogetherWsErrorTextPreview,
  listenTogetherWsFailureMessage,
  listenTogetherWsOversizeErrorMessage
} from '../../../main/ets/listentogether/network/ListenTogetherWsFraming';
import {
  LISTEN_TOGETHER_HEALTHZ_MARKER,
  LISTEN_TOGETHER_MAX_HTTP_RESPONSE_BYTES,
  LISTEN_TOGETHER_TEST_INVALID_BASE_URL,
  LISTEN_TOGETHER_TEST_INVALID_RESPONSE,
  LISTEN_TOGETHER_TEST_REACHABLE,
  isListenTogetherResponseTooLarge,
  listenTogetherBearerHeaderOrNull,
  listenTogetherControlUrl,
  listenTogetherCreateRoomUrl,
  listenTogetherHealthResultForBody,
  listenTogetherHealthzUrlOrNull,
  listenTogetherHttpErrorMessage,
  listenTogetherJoinRoomUrl,
  listenTogetherLeaveRoomUrl,
  listenTogetherOversizeResponseMessage,
  listenTogetherRoomStateUrl,
  listenTogetherServerTestResult
} from '../../../main/ets/listentogether/network/ListenTogetherApiRequests';
import {
  listenTogetherSavedCustomServer,
  listenTogetherSavedServerInput,
  listenTogetherServerSettingForSave
} from '../../../main/ets/listentogether/network/ListenTogetherServerSetting';
import {
  DEFAULT_LISTEN_TOGETHER_BASE_URL
} from '../../../main/ets/listentogether/invite/ListenTogetherBaseUrlResolver';

const NORMALIZED_DEFAULT_SERVER: string = 'https://neriplayer.hancat.work';

const WORKER_BASE_URL: string = 'https://worker.example';

/** hypium has no assertThrow in this version, so throwing is probed manually. */
function throwsFor(action: () => void): boolean {
  try {
    action();
    return false;
  } catch (error) {
    return true;
  }
}

/** Doubling instead of appending, so a 2 MiB probe stays O(log n) allocations. */
function repeatChar(char: string, count: number): string {
  let text = char;
  while (text.length < count) {
    text += text;
  }
  return text.slice(0, count);
}

export default function listenTogetherNetworkClientTest(): void {
  describe('ListenTogetherReconnectPolicy', () => {
    it('caps reconnect attempts at the upstream 15', 0, () => {
      expect(LISTEN_TOGETHER_MAX_RECONNECT_ATTEMPTS).assertEqual(15);
    });

    it('follows the upstream backoff table', 0, () => {
      expect(listenTogetherReconnectDelayBaseMs(1)).assertEqual(1500);
      expect(listenTogetherReconnectDelayBaseMs(2)).assertEqual(3000);
      expect(listenTogetherReconnectDelayBaseMs(3)).assertEqual(5000);
      expect(listenTogetherReconnectDelayBaseMs(4)).assertEqual(8000);
      expect(listenTogetherReconnectDelayBaseMs(5)).assertEqual(12000);
      expect(listenTogetherReconnectDelayBaseMs(15)).assertEqual(12000);
    });

    it('treats out-of-range attempts as the plateau, matching Kotlin else', 0, () => {
      // A caller bug (0-based attempt, or a negative) must not produce a
      // zero-delay hot reconnect loop.
      expect(listenTogetherReconnectDelayBaseMs(0)).assertEqual(12000);
      expect(listenTogetherReconnectDelayBaseMs(-3)).assertEqual(12000);
    });

    it('maps the random draw onto +/-20% jitter', 0, () => {
      expect(listenTogetherReconnectDelayMsWithRandom(1, 0.5)).assertEqual(1500);
      expect(listenTogetherReconnectDelayMsWithRandom(1, 0)).assertEqual(1200);
      expect(listenTogetherReconnectDelayMsWithRandom(1, 1)).assertEqual(1800);
      expect(listenTogetherReconnectDelayMsWithRandom(5, 0)).assertEqual(9600);
      expect(listenTogetherReconnectDelayMsWithRandom(5, 1)).assertEqual(14400);
    });

    it('truncates fractional jitter toward zero like Kotlin toLong()', 0, () => {
      // Both sides are IEEE754 doubles truncated toward zero, so the exact
      // rounding artefacts match Kotlin's `(baseMs * 0.2 * x).toLong()`:
      //   1500 * 0.2 * (0.3 * 2 - 1) = -120.00000000000001 -> -120
      expect(listenTogetherReconnectDelayMsWithRandom(1, 0.3)).assertEqual(1380);
      //   5000 * 0.2 * (0.7 * 2 - 1) =  399.99999999999991 ->  399
      // (not 400 — 0.7 * 2 - 1 lands just below 0.4 in binary floating point)
      expect(listenTogetherReconnectDelayMsWithRandom(3, 0.7)).assertEqual(5399);
    });

    it('keeps the live delay inside the jitter band for every attempt', 0, () => {
      for (let attempt = 1; attempt <= LISTEN_TOGETHER_MAX_RECONNECT_ATTEMPTS; attempt++) {
        const base = listenTogetherReconnectDelayBaseMs(attempt);
        const delay = listenTogetherReconnectDelayMs(attempt);
        expect(delay >= Math.trunc(base * 0.8)).assertTrue();
        expect(delay <= Math.trunc(base * 1.2)).assertTrue();
      }
    });

    it('does not treat a blank or missing message as terminal', 0, () => {
      expect(isTerminalListenTogetherReconnectError(null)).assertFalse();
      expect(isTerminalListenTogetherReconnectError(undefined)).assertFalse();
      expect(isTerminalListenTogetherReconnectError('')).assertFalse();
      expect(isTerminalListenTogetherReconnectError('   \n ')).assertFalse();
    });

    it('detects an unauthorized room token regardless of case', 0, () => {
      expect(isTerminalListenTogetherReconnectError('Unauthorized')).assertTrue();
      expect(isTerminalListenTogetherReconnectError('  UNAUTHORIZED  ')).assertTrue();
      expect(isTerminalListenTogetherReconnectError('{"error":"unauthorized"}')).assertTrue();
    });

    it('detects a closed room in both the HTTP and socket message shapes', 0, () => {
      expect(isTerminalListenTogetherReconnectError('room closed')).assertTrue();
      expect(isTerminalListenTogetherReconnectError(
        'ListenTogether GET failed (410): {"error":"room closed"}'
      )).assertTrue();
      expect(isTerminalListenTogetherReconnectError('handshake failed (http=410 Gone)')).assertTrue();
    });

    it('detects a missing durable object', 0, () => {
      expect(isTerminalListenTogetherReconnectError('room not initialized')).assertTrue();
      expect(isTerminalListenTogetherReconnectError('{"error":"Room Not Initialized"}')).assertTrue();
      expect(isTerminalListenTogetherReconnectError('{"error":"Not found in DO"}')).assertTrue();
    });

    it('keeps retryable failures retryable', 0, () => {
      expect(isTerminalListenTogetherReconnectError('Failed to connect to worker.example')).assertFalse();
      expect(isTerminalListenTogetherReconnectError('ListenTogether GET failed (500): oops')).assertFalse();
      expect(isTerminalListenTogetherReconnectError('timeout')).assertFalse();
      // Guard against a sloppy substring match: (4100) must not read as (410).
      expect(isTerminalListenTogetherReconnectError('weird status (4100)')).assertFalse();
    });
  });

  describe('ListenTogetherWsFraming', () => {
    it('keeps the upstream 2 MiB char ceiling', 0, () => {
      expect(LISTEN_TOGETHER_MAX_WS_MESSAGE_CHARS).assertEqual(2097152);
      expect(LISTEN_TOGETHER_WS_ERROR_TEXT_PREVIEW_CHARS).assertEqual(256);
    });

    it('rejects only frames strictly above the ceiling', 0, () => {
      expect(isListenTogetherWsMessageTooLarge('')).assertFalse();
      expect(isListenTogetherWsMessageTooLarge('{"type":"state"}')).assertFalse();
      // The real boundary, not an approximation: a frame exactly at the limit
      // must still be processed, or a legitimate large queue snapshot would be
      // dropped as an attack.
      const atLimit = repeatChar('a', LISTEN_TOGETHER_MAX_WS_MESSAGE_CHARS);
      expect(atLimit.length).assertEqual(LISTEN_TOGETHER_MAX_WS_MESSAGE_CHARS);
      expect(isListenTogetherWsMessageTooLarge(atLimit)).assertFalse();
      expect(isListenTogetherWsMessageTooLarge(`${atLimit}a`)).assertTrue();
    });

    it('truncates the error preview to 256 chars', 0, () => {
      const long = repeatChar('x', 1000);
      expect(listenTogetherWsErrorTextPreview(long).length).assertEqual(256);
      expect(listenTogetherWsErrorTextPreview('short')).assertEqual('short');
      expect(listenTogetherWsErrorTextPreview('')).assertEqual('');
    });

    it('reports the oversize frame length in the upstream wording', 0, () => {
      expect(listenTogetherWsOversizeErrorMessage(2097153))
        .assertEqual('WebSocket message too large: 2097153 chars');
    });

    it('builds the np_ping frame byte-for-byte', 0, () => {
      expect(buildListenTogetherPingFrame(12345)).assertEqual('{"type":"np_ping","t":12345}');
      expect(buildListenTogetherPingFrame(0)).assertEqual('{"type":"np_ping","t":0}');
      // A fractional timestamp would be a wire change versus Kotlin's Long.
      expect(buildListenTogetherPingFrame(1234.99)).assertEqual('{"type":"np_ping","t":1234}');
    });

    it('keeps the legacy ping frame for older servers', 0, () => {
      expect(LISTEN_TOGETHER_LEGACY_PING_FRAME).assertEqual('{"type":"ping"}');
    });

    it('keeps the wire-visible close codes', 0, () => {
      expect(LISTEN_TOGETHER_WS_CLOSE_CODE_NORMAL).assertEqual(1000);
      expect(LISTEN_TOGETHER_WS_CLOSE_REASON_CLIENT_CLOSED).assertEqual('client_closed');
      expect(LISTEN_TOGETHER_WS_CLOSE_CODE_TOO_LARGE).assertEqual(1009);
      expect(LISTEN_TOGETHER_WS_CLOSE_REASON_TOO_LARGE).assertEqual('message_too_large');
    });

    it('shapes the failure message like okhttp did', 0, () => {
      expect(listenTogetherWsFailureMessage('Connection reset')).assertEqual('Connection reset');
      expect(listenTogetherWsFailureMessage('Connection reset', 410, 'Gone'))
        .assertEqual('Connection reset (http=410 Gone)');
      expect(listenTogetherWsFailureMessage('Connection reset', 410))
        .assertEqual('Connection reset (http=410)');
      expect(listenTogetherWsFailureMessage('Connection reset', 410, '   '))
        .assertEqual('Connection reset (http=410)');
    });

    it('never emits a fake http status', 0, () => {
      // (http=0) would be noise in the log and could confuse substring matching.
      expect(listenTogetherWsFailureMessage('boom', 0)).assertEqual('boom');
      expect(listenTogetherWsFailureMessage('boom', -1)).assertEqual('boom');
      expect(listenTogetherWsFailureMessage('', undefined)).assertEqual('WebSocketError');
    });

    it('produces a message the reconnect policy can classify as terminal', 0, () => {
      // Cross-module contract: the framing layer is the producer and the
      // reconnect policy the consumer, so the punctuation must line up.
      const closed = listenTogetherWsFailureMessage('handshake failed', 410, 'Gone');
      expect(isTerminalListenTogetherReconnectError(closed)).assertTrue();
      const transient = listenTogetherWsFailureMessage('handshake failed', 503, 'Service Unavailable');
      expect(isTerminalListenTogetherReconnectError(transient)).assertFalse();
    });
  });

  describe('ListenTogetherApiRequests', () => {
    it('builds every room endpoint upstream defines', 0, () => {
      expect(listenTogetherCreateRoomUrl(WORKER_BASE_URL)).assertEqual('https://worker.example/api/rooms');
      expect(listenTogetherJoinRoomUrl(WORKER_BASE_URL, 'ABC234'))
        .assertEqual('https://worker.example/api/rooms/ABC234/join');
      expect(listenTogetherRoomStateUrl(WORKER_BASE_URL, 'ABC234'))
        .assertEqual('https://worker.example/api/rooms/ABC234/state');
      expect(listenTogetherLeaveRoomUrl(WORKER_BASE_URL, 'ABC234'))
        .assertEqual('https://worker.example/api/rooms/ABC234/leave');
      expect(listenTogetherControlUrl(WORKER_BASE_URL, 'ABC234'))
        .assertEqual('https://worker.example/api/rooms/ABC234/control');
    });

    it('normalizes trailing slashes and keeps a path prefix', 0, () => {
      expect(listenTogetherCreateRoomUrl('https://worker.example///'))
        .assertEqual('https://worker.example/api/rooms');
      // Unlike the ws URL (which drops the path to match encodedPath), the HTTP
      // endpoints are appended to the base path.
      expect(listenTogetherCreateRoomUrl('https://worker.example/lt/'))
        .assertEqual('https://worker.example/lt/api/rooms');
    });

    it('fails loudly on an unusable room base URL', 0, () => {
      expect(throwsFor(() => listenTogetherCreateRoomUrl(''))).assertTrue();
      expect(throwsFor(() => listenTogetherCreateRoomUrl('worker.example'))).assertTrue();
      expect(throwsFor(() => listenTogetherJoinRoomUrl('ftp://worker.example', 'ABC234'))).assertTrue();
    });

    it('returns null instead of throwing for the health probe', 0, () => {
      expect(listenTogetherHealthzUrlOrNull(WORKER_BASE_URL)).assertEqual('https://worker.example/healthz');
      expect(listenTogetherHealthzUrlOrNull('https://worker.example/')).assertEqual('https://worker.example/healthz');
      expect(listenTogetherHealthzUrlOrNull('not a url')).assertNull();
      expect(listenTogetherHealthzUrlOrNull('')).assertNull();
    });

    it('omits Authorization for a blank token', 0, () => {
      expect(listenTogetherBearerHeaderOrNull(null)).assertNull();
      expect(listenTogetherBearerHeaderOrNull(undefined)).assertNull();
      expect(listenTogetherBearerHeaderOrNull('')).assertNull();
      expect(listenTogetherBearerHeaderOrNull('   ')).assertNull();
      expect(listenTogetherBearerHeaderOrNull('leave-token')).assertEqual('Bearer leave-token');
      expect(listenTogetherBearerHeaderOrNull('  leave-token  ')).assertEqual('Bearer leave-token');
    });

    it('shapes the HTTP error exactly as the reconnect policy expects', 0, () => {
      expect(listenTogetherHttpErrorMessage('GET', 410, '{"error":"room closed"}'))
        .assertEqual('ListenTogether GET failed (410): {"error":"room closed"}');
      expect(listenTogetherHttpErrorMessage('post', 500, 'oops'))
        .assertEqual('ListenTogether POST failed (500): oops');
      // Cross-module contract, same as the ws framing case above.
      expect(isTerminalListenTogetherReconnectError(
        listenTogetherHttpErrorMessage('GET', 410, '{"error":"room closed"}')
      )).assertTrue();
      expect(isTerminalListenTogetherReconnectError(
        listenTogetherHttpErrorMessage('POST', 404, '{"error":"not found in DO"}')
      )).assertTrue();
      expect(isTerminalListenTogetherReconnectError(
        listenTogetherHttpErrorMessage('GET', 502, 'bad gateway')
      )).assertFalse();
    });

    it('keeps the 2 MiB response ceiling and its wording', 0, () => {
      expect(LISTEN_TOGETHER_MAX_HTTP_RESPONSE_BYTES).assertEqual(2097152);
      expect(isListenTogetherResponseTooLarge(2097152)).assertFalse();
      expect(isListenTogetherResponseTooLarge(2097153)).assertTrue();
      expect(listenTogetherOversizeResponseMessage(2097153))
        .assertEqual('ListenTogether response too large: 2097153 bytes');
    });

    it('accepts a health body only when it carries the worker marker', 0, () => {
      // Same fixture body as Android's ListenTogetherApiTest.
      const reachable = listenTogetherHealthResultForBody(
        '{"ok":true,"service":"neriplayer-listen-together-worker"}'
      );
      expect(reachable.ok).assertTrue();
      expect(reachable.message).assertEqual(LISTEN_TOGETHER_TEST_REACHABLE);
      const mixedCase = listenTogetherHealthResultForBody('NeriPlayer-Listen-Together-Worker OK');
      expect(mixedCase.ok).assertTrue();
    });

    it('rejects a 200 from an unrelated server', 0, () => {
      // A captive portal or a proxy default page must not read as reachable.
      const portal = listenTogetherHealthResultForBody('<html><title>Login</title></html>');
      expect(portal.ok).assertFalse();
      expect(portal.message).assertEqual(LISTEN_TOGETHER_TEST_INVALID_RESPONSE);
      const empty = listenTogetherHealthResultForBody('');
      expect(empty.ok).assertFalse();
      expect(empty.message).assertEqual(LISTEN_TOGETHER_TEST_INVALID_RESPONSE);
    });

    it('keeps the UI-facing result strings stable', 0, () => {
      expect(LISTEN_TOGETHER_TEST_INVALID_BASE_URL).assertEqual('invalid_base_url');
      expect(LISTEN_TOGETHER_TEST_REACHABLE).assertEqual('reachable');
      expect(LISTEN_TOGETHER_TEST_INVALID_RESPONSE).assertEqual('invalid_response');
      expect(LISTEN_TOGETHER_HEALTHZ_MARKER).assertEqual('neriplayer-listen-together-worker');
      const custom = listenTogetherServerTestResult(false, 'boom');
      expect(custom.ok).assertFalse();
      expect(custom.message).assertEqual('boom');
    });
  });

  describe('ListenTogetherServerSetting', () => {
    it('pins the normalized form of the built-in default', 0, () => {
      // The rest of this suite compares against the normalized spelling, so a
      // change to the default host must fail here first rather than silently
      // turning the "is default" checks below into no-ops.
      expect(DEFAULT_LISTEN_TOGETHER_BASE_URL).assertEqual('https://neriplayer.hancat.work/');
    });

    it('clears both keys for a blank address', 0, () => {
      const blank = listenTogetherServerSettingForSave('');
      expect(blank !== null).assertTrue();
      expect(blank?.server).assertEqual('');
      expect(blank?.input).assertEqual('');
      const spaces = listenTogetherServerSettingForSave('   \n ');
      expect(spaces?.server).assertEqual('');
      expect(spaces?.input).assertEqual('');
    });

    it('stores absence rather than the default address', 0, () => {
      // Persisting the default URL verbatim would pin this install to today's
      // host forever, which is the whole reason upstream removes the key.
      const typedDefault = listenTogetherServerSettingForSave(DEFAULT_LISTEN_TOGETHER_BASE_URL);
      expect(typedDefault?.server).assertEqual('');
      expect(typedDefault?.input).assertEqual('');
      const noSlash = listenTogetherServerSettingForSave(NORMALIZED_DEFAULT_SERVER);
      expect(noSlash?.server).assertEqual('');
      expect(noSlash?.input).assertEqual('');
    });

    it('stores a custom address in both keys, normalized', 0, () => {
      const saved = listenTogetherServerSettingForSave('  https://worker.example///  ');
      expect(saved?.server).assertEqual(WORKER_BASE_URL);
      expect(saved?.input).assertEqual(WORKER_BASE_URL);
      const withPath = listenTogetherServerSettingForSave('http://192.168.1.9:8787/lt/');
      expect(withPath?.server).assertEqual('http://192.168.1.9:8787/lt');
    });

    it('refuses a non-blank address it cannot normalize', 0, () => {
      // Must be distinguishable from "cleared": falling back to the default
      // silently would hide the user's typo behind working playback.
      expect(listenTogetherServerSettingForSave('worker.example')).assertNull();
      expect(listenTogetherServerSettingForSave('ftp://worker.example')).assertNull();
      expect(listenTogetherServerSettingForSave('https://worker.example/?x=1')).assertNull();
    });

    it('reads back only a usable custom server', 0, () => {
      expect(listenTogetherSavedCustomServer('')).assertEqual('');
      expect(listenTogetherSavedCustomServer('https://worker.example')).assertEqual(WORKER_BASE_URL);
      // A stored default (from an older build) still resolves to "use default".
      expect(listenTogetherSavedCustomServer(DEFAULT_LISTEN_TOGETHER_BASE_URL)).assertEqual('');
      // Garbage that predates a normalizer change must not be dialed.
      expect(listenTogetherSavedCustomServer('worker.example')).assertEqual('');
    });

    it('falls back to the server when no input was stored', 0, () => {
      expect(listenTogetherSavedServerInput('', 'https://worker.example')).assertEqual(WORKER_BASE_URL);
      expect(listenTogetherSavedServerInput('  ', 'https://worker.example')).assertEqual(WORKER_BASE_URL);
      expect(listenTogetherSavedServerInput('', '')).assertEqual('');
      // Input wins when both are present, so an in-progress edit is not undone.
      expect(listenTogetherSavedServerInput('https://other.example', 'https://worker.example'))
        .assertEqual('https://other.example');
    });

    it('round-trips what the dialog shows', 0, () => {
      const saved = listenTogetherServerSettingForSave('https://worker.example/');
      expect(listenTogetherSavedServerInput(saved?.input ?? '', saved?.server ?? ''))
        .assertEqual(WORKER_BASE_URL);
      const reset = listenTogetherServerSettingForSave('');
      expect(listenTogetherSavedServerInput(reset?.input ?? '', reset?.server ?? '')).assertEqual('');
    });
  });
}
