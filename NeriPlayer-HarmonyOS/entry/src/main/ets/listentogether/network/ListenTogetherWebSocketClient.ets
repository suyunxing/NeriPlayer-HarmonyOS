/**
 * Port of listentogether/network/ws/ListenTogetherWebSocketClient.kt onto
 * `@kit.NetworkKit`'s webSocket API.
 *
 * Four documented divergences, all forced by the platform API shape:
 *
 * 1. **Identity check by generation counter, not reference.** Upstream compares
 *    `this.webSocket !== webSocket` inside each okhttp callback to drop frames
 *    from a superseded socket. HarmonyOS callbacks carry no socket argument, so
 *    each `connect()` bumps a generation counter that its callbacks capture and
 *    compare. This is also strictly safer than upstream: okhttp's
 *    `newWebSocket()` can dispatch `onOpen` before the returned reference is
 *    assigned to the field, in which case upstream drops its own `onOpen`. Here
 *    the generation is assigned before any callback can fire.
 *
 * 2. **`send`/`connect`/`disconnect` are async.** okhttp's `send` returns a
 *    synchronous "enqueued" boolean; here it is a Promise. The `== true`
 *    semantics are preserved (no live socket, or a rejected send, yields false).
 *
 * 3. **`connect()` resolves before the handshake completes.** okhttp's
 *    `newWebSocket()` hands back a socket immediately and reports the outcome on
 *    `onOpen`/`onFailure`. HarmonyOS's `connect()` returns a Promise, but that
 *    Promise settles when the netstack *accepts the request*, not when the
 *    handshake finishes. Measured on the emulator against a refused endpoint
 *    (`ws://127.0.0.1:1`): `connect()` resolved after 40 ms and the failure
 *    arrived 1 ms later on the `error` callback. So the outcome surfaces exactly
 *    where upstream surfaces it — `onOpen` / `onFailure` — and `connect()`
 *    rejects only when the platform refuses the call itself (malformed URL,
 *    unsupported scheme), a case for which no callback will ever arrive. Because
 *    those two orderings are 1 ms apart and not guaranteed either way, a failure
 *    landing before `connect()` settles is held and replayed to `onFailure`
 *    immediately after, so there is still exactly one failure signal per attempt.
 *
 * 4. **A terminal failure releases the socket eagerly.** Upstream leaves the
 *    dead okhttp socket in its field and lets the reconnect loop's next
 *    `connect()` (which calls `disconnect()` first) drop it. Here `onFailure` is
 *    preceded by detaching the handle and followed by unregistering all five
 *    callbacks: behaviourally the same for a reconnecting caller, but nothing
 *    leaks when the caller gives up instead. This also matches okhttp's contract
 *    that `onFailure` is terminal and no `onClosed` follows it.
 *
 * 5. **The failure text carries no cause, and no HTTP status.** okhttp hands
 *    `onFailure` the exception plus the `Response`, so upstream can emit
 *    `ConnectException: Connection refused (http=410 Gone)` and let
 *    `isTerminalListenTogetherReconnectError` stop retrying a closed room.
 *    HarmonyOS gives `on('error')` only a `BusinessError`, whose `message` was
 *    measured to be **empty** for a refused connection (hence the
 *    `WebSocketError` fallback in `listenTogetherWsFailureMessage`), and
 *    `on('headerReceive')` never fired at all on a failed handshake, so no
 *    `:status` pseudo-header was available either. Consequence, accepted rather
 *    than worked around: text-based terminal detection
 *    (`isTerminalListenTogetherReconnectError`) is inert for the socket layer on
 *    HarmonyOS, because a refused connection and a `410 Gone` handshake both
 *    reduce to the same `WebSocketError`. A closed room would therefore burn all
 *    15 reconnect attempts if the socket failure were the only signal. The HTTP
 *    layer does still produce the matchable `(410)` form (`ListenTogetherApi` on
 *    `/state` and `/join`), so M7.3's session manager must consult it rather than
 *    relying on the socket message alone. The `:status` path below is kept
 *    because it costs nothing if a future stack version does surface a header.
 */
import { webSocket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '../../app/Logger';
import { SettingsRepository } from '../../data/SettingsRepository';
import { ListenTogetherEvent, listenTogetherEventToRecord } from '../protocol/ListenTogetherEventModels';
import {
  ListenTogetherSocketEnvelope,
  listenTogetherSocketEnvelopeFromJson
} from '../protocol/ListenTogetherSocketEnvelope';
import { redactListenTogetherWsUrlForLog } from './ListenTogetherWsUrl';
import {
  LISTEN_TOGETHER_LEGACY_PING_FRAME,
  LISTEN_TOGETHER_WS_CLOSE_CODE_NORMAL,
  LISTEN_TOGETHER_WS_CLOSE_CODE_TOO_LARGE,
  LISTEN_TOGETHER_WS_CLOSE_REASON_CLIENT_CLOSED,
  LISTEN_TOGETHER_WS_CLOSE_REASON_TOO_LARGE,
  buildListenTogetherPingFrame,
  isListenTogetherWsMessageTooLarge,
  listenTogetherWsErrorTextPreview,
  listenTogetherWsFailureMessage,
  listenTogetherWsOversizeErrorMessage
} from './ListenTogetherWsFraming';

/** Upstream: ListenTogetherWebSocketClient.Listener. */
export interface ListenTogetherWebSocketListener {
  onOpen(): void;
  onMessage(message: ListenTogetherSocketEnvelope): void;
  onClosed(code: number, reason: string): void;
  onFailure(error: Error): void;
  onProtocolError(rawText: string, error: Error): void;
}

const HANDSHAKE_STATUS_HEADER_KEYS: string[] = [':status', 'status'];

export class ListenTogetherWebSocketClient {
  private socket: webSocket.WebSocket | null = null;
  /** Bumped by every connect/disconnect; stale callbacks compare against it. */
  private generation: number = 0;
  private connectSettled: boolean = true;
  private pendingHandshakeError: string | null = null;
  private handshakeStatus: number | null = null;

  /**
   * Upstream `connect(wsUrl, listener)`: closes any existing socket first, so a
   * reconnect can never leave two sockets feeding the same listener.
   *
   * Resolving does NOT mean the handshake succeeded — see divergence 3. Success
   * arrives on `listener.onOpen()`, failure on `listener.onFailure()`, exactly
   * once per attempt. `connect()` rejects only when the platform refuses the
   * call outright, in which case no callback will follow and the socket handle
   * and all of its listeners are already released.
   */
  async connect(wsUrl: string, listener: ListenTogetherWebSocketListener): Promise<void> {
    await this.disconnect();
    this.generation += 1;
    const generation = this.generation;
    this.connectSettled = false;
    this.pendingHandshakeError = null;
    this.handshakeStatus = null;

    const socket = webSocket.createWebSocket();
    this.socket = socket;
    this.registerCallbacks(socket, generation, listener);

    Logger.info(`ListenTogether ws connect ${redactListenTogetherWsUrlForLog(wsUrl)}`);
    try {
      await socket.connect(wsUrl, this.buildRequestOptions());
    } catch (error) {
      const err = error as BusinessError;
      const detail = this.pendingHandshakeError
        ?? listenTogetherWsFailureMessage(err.message ?? '', this.handshakeStatus ?? undefined);
      this.pendingHandshakeError = null;
      this.connectSettled = true;
      this.detach(generation);
      // Failure path must release the handle too, not just the success path.
      await ListenTogetherWebSocketClient.closeAndUnregister(socket);
      throw new Error(`${detail} (errno=${err.code})`);
    }
    this.connectSettled = true;
    const heldError = this.pendingHandshakeError;
    if (heldError !== null) {
      // Arrived before connect() resolved; surface it now that nothing else will.
      this.pendingHandshakeError = null;
      this.failAndRelease(socket, generation, listener, heldError);
    }
  }

  /** Upstream `sendEvent`: false when there is no live socket. */
  async sendEvent(event: ListenTogetherEvent): Promise<boolean> {
    return await this.sendText(JSON.stringify(listenTogetherEventToRecord(event)));
  }

  /** Upstream `sendPing(sentAtElapsedMs)`. */
  async sendPing(sentAtElapsedMs: number): Promise<boolean> {
    return await this.sendText(buildListenTogetherPingFrame(sentAtElapsedMs));
  }

  /** Upstream `sendLegacyPing()`. */
  async sendLegacyPing(): Promise<boolean> {
    return await this.sendText(LISTEN_TOGETHER_LEGACY_PING_FRAME);
  }

  /**
   * Upstream `disconnect(code = 1000, reason = "client_closed")`. The generation
   * bump happens before the close, so — matching upstream's `webSocket = null`
   * before the identity check — a client-initiated close produces no `onClosed`
   * callback.
   */
  async disconnect(
    code: number = LISTEN_TOGETHER_WS_CLOSE_CODE_NORMAL,
    reason: string = LISTEN_TOGETHER_WS_CLOSE_REASON_CLIENT_CLOSED
  ): Promise<void> {
    const socket = this.socket;
    if (socket === null) {
      return;
    }
    this.socket = null;
    this.generation += 1;
    const options: webSocket.WebSocketCloseOptions = { code: code, reason: reason };
    await ListenTogetherWebSocketClient.closeAndUnregister(socket, options);
  }

  private async sendText(text: string): Promise<boolean> {
    const socket = this.socket;
    if (socket === null) {
      return false;
    }
    try {
      return await socket.send(text);
    } catch (error) {
      const err = error as BusinessError;
      Logger.warn(`ListenTogether ws send failed: ${err.message} (errno=${err.code})`);
      return false;
    }
  }

  private registerCallbacks(
    socket: webSocket.WebSocket,
    generation: number,
    listener: ListenTogetherWebSocketListener
  ): void {
    socket.on('headerReceive', (headers: webSocket.ResponseHeaders): void => {
      if (this.generation !== generation) {
        return;
      }
      this.handshakeStatus = ListenTogetherWebSocketClient.handshakeStatusOrNull(headers);
    });

    socket.on('open', (error: BusinessError, _value: Object): void => {
      if (this.generation !== generation) {
        return;
      }
      if (error !== undefined && error !== null) {
        this.reportFailure(
          socket,
          generation,
          listener,
          listenTogetherWsFailureMessage(error.message ?? '', this.handshakeStatus ?? undefined)
        );
        return;
      }
      listener.onOpen();
    });

    socket.on('message', (error: BusinessError, value: string | ArrayBuffer): void => {
      if (this.generation !== generation) {
        return;
      }
      if (error !== undefined && error !== null) {
        this.reportFailure(socket, generation, listener, listenTogetherWsFailureMessage(error.message ?? ''));
        return;
      }
      if (typeof value !== 'string') {
        // The room protocol is text-only; a binary frame is a protocol error,
        // and its bytes are deliberately not decoded for the report.
        listener.onProtocolError('', new Error('WebSocket binary frame is not supported'));
        return;
      }
      const text = value as string;
      if (isListenTogetherWsMessageTooLarge(text)) {
        listener.onProtocolError(
          listenTogetherWsErrorTextPreview(text),
          new Error(listenTogetherWsOversizeErrorMessage(text.length))
        );
        this.disconnect(LISTEN_TOGETHER_WS_CLOSE_CODE_TOO_LARGE, LISTEN_TOGETHER_WS_CLOSE_REASON_TOO_LARGE)
          .catch((err: Object): void => {
            Logger.warn(`ListenTogether ws oversize disconnect failed: ${err}`);
          });
        return;
      }
      const envelope = listenTogetherSocketEnvelopeFromJson(text);
      if (envelope === null) {
        listener.onProtocolError(text, new Error('Malformed ListenTogether socket envelope'));
        return;
      }
      listener.onMessage(envelope);
    });

    socket.on('close', (error: BusinessError, value: webSocket.CloseResult): void => {
      if (this.generation !== generation) {
        return;
      }
      if (error !== undefined && error !== null) {
        this.reportFailure(socket, generation, listener, listenTogetherWsFailureMessage(error.message ?? ''));
        return;
      }
      listener.onClosed(value.code, value.reason);
    });

    socket.on('error', (error: BusinessError): void => {
      if (this.generation !== generation) {
        return;
      }
      this.reportFailure(
        socket,
        generation,
        listener,
        listenTogetherWsFailureMessage(error.message ?? '', this.handshakeStatus ?? undefined)
      );
    });
  }

  /**
   * Routes a failure either to the listener or into the pending slot, so a
   * failure landing before `connect()` settles is reported exactly once — see
   * divergence 3.
   */
  private reportFailure(
    socket: webSocket.WebSocket,
    generation: number,
    listener: ListenTogetherWebSocketListener,
    message: string
  ): void {
    if (!this.connectSettled) {
      this.pendingHandshakeError = message;
      return;
    }
    this.failAndRelease(socket, generation, listener, message);
  }

  /**
   * Reports a terminal failure and releases the socket — divergence 4. The
   * handle is detached *before* `onFailure` so a listener that reconnects from
   * inside the callback sees a clean client and cannot double-close this socket;
   * the close itself is fire-and-forget because callers must not wait on it.
   */
  private failAndRelease(
    socket: webSocket.WebSocket,
    generation: number,
    listener: ListenTogetherWebSocketListener,
    message: string
  ): void {
    if (this.generation !== generation) {
      return;
    }
    this.detach(generation);
    listener.onFailure(new Error(message));
    ListenTogetherWebSocketClient.closeAndUnregister(socket).catch((error: Object): void => {
      Logger.warn(`ListenTogether ws failure release failed: ${error}`);
    });
  }

  /** Drops the client's reference to the current socket and invalidates its callbacks. */
  private detach(generation: number): void {
    if (this.generation !== generation) {
      return;
    }
    this.socket = null;
    this.generation += 1;
  }

  /**
   * Closes a socket and removes every listener registered in
   * `registerCallbacks`. Never rejects: a close on an already-dead socket is
   * expected, and the `off` calls must run either way.
   */
  private static async closeAndUnregister(
    socket: webSocket.WebSocket,
    options?: webSocket.WebSocketCloseOptions
  ): Promise<void> {
    try {
      if (options === undefined) {
        await socket.close();
      } else {
        await socket.close(options);
      }
    } catch (error) {
      const err = error as BusinessError;
      Logger.warn(`ListenTogether ws close failed: ${err.message} (errno=${err.code})`);
    } finally {
      ListenTogetherWebSocketClient.unregisterCallbacks(socket);
    }
  }

  /** Every listener registered in registerCallbacks is removed here. */
  private static unregisterCallbacks(socket: webSocket.WebSocket): void {
    try {
      socket.off('headerReceive');
      socket.off('open');
      socket.off('message');
      socket.off('close');
      socket.off('error');
    } catch (error) {
      const err = error as BusinessError;
      Logger.warn(`ListenTogether ws off failed: ${err.message} (errno=${err.code})`);
    }
  }

  /**
   * Best-effort HTTP status of the handshake response — see divergence 5 in the
   * file header. Only an explicit numeric `:status`/`status` header counts. On
   * the emulator this callback did not fire at all for a refused handshake, so
   * treat the status as normally absent.
   */
  private static handshakeStatusOrNull(headers: webSocket.ResponseHeaders): number | null {
    for (const key of HANDSHAKE_STATUS_HEADER_KEYS) {
      const raw = headers[key];
      const text = typeof raw === 'string' ? raw as string : null;
      if (text === null) {
        continue;
      }
      const parsed = Number.parseInt(text.trim(), 10);
      if (!Number.isNaN(parsed) && parsed > 0) {
        return parsed;
      }
    }
    return null;
  }

  /**
   * Mirrors HttpClient's proxy handling: the media/netstack layer does not pick
   * up `setAppHttpProxy` for websockets, so the configured proxy is passed
   * explicitly. Without a configured proxy the platform default ('system') is
   * kept by omitting the field.
   */
  private buildRequestOptions(): webSocket.WebSocketRequestOptions {
    const host = SettingsRepository.getString(SettingsRepository.KEY_PROXY_HOST, '').trim();
    const port = SettingsRepository.getNumber(SettingsRepository.KEY_PROXY_PORT, 0);
    if (host.length === 0 || port <= 0) {
      return {};
    }
    const proxy: webSocket.HttpProxy = { host: host, port: port, exclusionList: [] };
    const options: webSocket.WebSocketRequestOptions = { proxy: proxy };
    return options;
  }
}
