import { http, socket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { Logger } from '../../app/Logger';
import { HttpClient } from '../HttpClient';
import {
  buildYtmServedResponseHeaders,
  normalizeYtmRange,
  parseYtmContentRangeTotal,
  parseYtmLoopbackRequest,
  planYtmUpstreamChunks,
  readYtmHeader,
  resolveYtmServedRange,
  serializeYtmLoopbackResponseHeaders,
  summarizeYtmLoopbackHeaders,
  YTM_UPSTREAM_CHUNK_BYTES,
  YtmLoopbackRequest
} from './YtmLoopbackHttp';

const LOOPBACK_ADDRESS = '127.0.0.1';
const AUDIO_PATH = '/ytm-stream';
const UPSTREAM_CONNECT_TIMEOUT = 30000;
const UPSTREAM_READ_TIMEOUT = 30000;
const MAX_REQUEST_BYTES = 64 * 1024;

/** What the sizing request learned about the upstream entity. */
interface YtmEntityInfo {
  total: number;
  contentType: string;
}

/** Per-connection cancellation state, so a closed socket stops the chunk loop. */
interface YtmConnectionState {
  aborted: boolean;
  upstream: http.HttpRequest | null;
}

/**
 * Serves one resolved googlevideo URL through a local HTTP socket. AVPlayer's
 * media service can reach loopback, while the upstream NetworkKit request
 * explicitly uses the app proxy.
 *
 * The bridge does not forward AVPlayer's Range verbatim. An anonymous direct URL
 * only serves an opening prefix of the entity — roughly the first minute — and
 * refuses both open-ended ranges and anything past that prefix; AVPlayer
 * meanwhile asks for 2 MiB at a time, so a verbatim range yields one 403 and no
 * audio at all. See YTM_UPSTREAM_CHUNK_BYTES for the measurements. Instead each
 * AVPlayer request is answered with one synthesized header block describing the
 * full interval it asked for, then filled by stitching bounded upstream chunks
 * together, so every chunk inside the reachable prefix still reaches AVPlayer.
 * No full-track pre-download is required.
 *
 * This cannot make a whole track playable: the prefix is an upstream
 * restriction, not a protocol detail the bridge can work around.
 */
export class YtmLoopbackStreamBridge {
  private server: socket.TCPSocketServer | null = null;
  private sourceUrl: string = '';
  private listenPort: number = 0;
  private connections: socket.TCPSocketConnection[] = [];
  private entityInfo: Promise<YtmEntityInfo> | null = null;
  private stopped: boolean = false;

  async start(sourceUrl: string): Promise<string> {
    await this.stop();
    if (sourceUrl.length === 0) {
      throw new Error('YTM loopback source URL is empty');
    }
    const server = socket.constructTCPSocketServerInstance();
    this.sourceUrl = sourceUrl;
    this.server = server;
    this.entityInfo = null;
    this.stopped = false;
    server.on('connect', (connection: socket.TCPSocketConnection) => {
      this.connections.push(connection);
      this.handleConnection(connection);
    });
    await server.listen({ address: LOOPBACK_ADDRESS, port: 0, family: 1 });
    const address = await server.getLocalAddress();
    if (address.port === undefined || address.port <= 0) {
      await this.stop();
      throw new Error('YTM loopback did not allocate a port');
    }
    this.listenPort = address.port;
    return `http://${LOOPBACK_ADDRESS}:${this.listenPort}${AUDIO_PATH}`;
  }

  async stop(): Promise<void> {
    this.stopped = true;
    for (const connection of this.connections) {
      try {
        await connection.close();
      } catch (_) {
        // The media service may already have closed the connection.
      }
    }
    this.connections = [];
    if (this.server !== null) {
      try {
        await this.server.close();
      } catch (_) {
        // Closing an already-closed listener is harmless.
      }
    }
    this.server = null;
    this.listenPort = 0;
    this.sourceUrl = '';
    this.entityInfo = null;
  }

  private handleConnection(connection: socket.TCPSocketConnection): void {
    let requestBytes = new Uint8Array(0);
    let handled = false;
    const decoder = util.TextDecoder.create('utf-8');
    const state: YtmConnectionState = { aborted: false, upstream: null };
    connection.on('close', () => {
      this.abort(state);
    });
    connection.on('error', () => {
      this.abort(state);
    });
    connection.on('message', (info: socket.SocketMessageInfo) => {
      if (handled) {
        return;
      }
      const incoming = new Uint8Array(info.message);
      const merged = new Uint8Array(requestBytes.length + incoming.length);
      merged.set(requestBytes, 0);
      merged.set(incoming, requestBytes.length);
      requestBytes = merged;
      const text = decoder.decodeToString(requestBytes);
      const end = text.indexOf('\r\n\r\n');
      if (end < 0 && requestBytes.length < MAX_REQUEST_BYTES) {
        return;
      }
      handled = true;
      const parsed = parseYtmLoopbackRequest(text.substring(0, end >= 0 ? end : text.length));
      this.serve(connection, state, parsed).catch((error: Error) => {
        Logger.warn(`YTM loopback connection failed: ${error.message}`);
      });
    });
  }

  /** Answers one AVPlayer request from end to end, then closes the socket. */
  private async serve(
    connection: socket.TCPSocketConnection,
    state: YtmConnectionState,
    parsed: YtmLoopbackRequest | null
  ): Promise<void> {
    if (parsed !== null) {
      Logger.info(`YTM loopback request method=${parsed.method} path=${parsed.path} range=${parsed.range.length > 0 ? parsed.range : 'none'}`);
    }
    if (parsed === null || parsed.path !== AUDIO_PATH || (parsed.method !== 'GET' && parsed.method !== 'HEAD')) {
      await this.sendStatus(connection, state, '404 Not Found');
      return;
    }
    let entity: YtmEntityInfo;
    try {
      entity = await this.describeEntity();
    } catch (error) {
      const failure = error as Error;
      Logger.warn(`YTM loopback could not size the upstream entity: ${failure.message}`);
      await this.sendStatus(connection, state, '502 Bad Gateway');
      return;
    }
    const served = resolveYtmServedRange(normalizeYtmRange(parsed.range), entity.total);
    if (served === null) {
      Logger.warn(`YTM loopback rejecting unsatisfiable range against total ${entity.total}`);
      await this.sendStatus(connection, state, '416 Range Not Satisfiable');
      return;
    }
    const headerText = serializeYtmLoopbackResponseHeaders(
      buildYtmServedResponseHeaders(served, entity.contentType)
    );
    if (parsed.method === 'HEAD') {
      await this.send(connection, state, this.encode(headerText));
      await this.close(connection, state);
      return;
    }
    const chunks = planYtmUpstreamChunks(served.start, served.end, YTM_UPSTREAM_CHUNK_BYTES);
    Logger.info(`YTM loopback serving bytes ${served.start}-${served.end}/${served.total} in ${chunks.length} upstream chunk(s)`);
    await this.send(connection, state, this.encode(headerText));
    for (const chunk of chunks) {
      if (state.aborted || this.stopped) {
        Logger.debug('YTM loopback stopped early: the connection is gone');
        return;
      }
      let body: ArrayBuffer;
      try {
        body = await this.fetchChunk(state, chunk);
      } catch (error) {
        const failure = error as Error;
        // The header block is already on the wire, so a short body is the only
        // signal left; AVPlayer surfaces that as a read/prepare failure.
        Logger.warn(`YTM loopback aborting mid-body: ${failure.message}`);
        await this.close(connection, state);
        return;
      }
      await this.send(connection, state, body);
    }
    await this.close(connection, state);
  }

  /**
   * Entity length and type, resolved once per source URL and shared by every
   * connection. A failure is not cached: AVPlayer retries, and a transient
   * proxy hiccup must not poison the whole playback attempt.
   */
  private describeEntity(): Promise<YtmEntityInfo> {
    const cached = this.entityInfo;
    if (cached !== null) {
      return cached;
    }
    const pending = this.probeEntity();
    this.entityInfo = pending;
    pending.catch(() => {
      if (this.entityInfo === pending) {
        this.entityInfo = null;
      }
    });
    return pending;
  }

  /**
   * Learns the entity length with a two-byte Range request. The total has to be
   * known up front because googlevideo refuses open-ended ranges, so the bridge
   * cannot simply read until EOF to discover where the track ends.
   */
  private async probeEntity(): Promise<YtmEntityInfo> {
    const request = http.createHttp();
    try {
      const response = await request.request(this.sourceUrl, {
        method: http.RequestMethod.GET,
        header: { 'User-Agent': HttpClient.DEFAULT_UA, 'Range': 'bytes=0-1' },
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: UPSTREAM_CONNECT_TIMEOUT,
        readTimeout: UPSTREAM_READ_TIMEOUT,
        usingProxy: HttpClient.usingProxyValue()
      });
      const headers = response.header as Record<string, string>;
      if (response.responseCode !== 206) {
        throw new Error(`sizing request returned HTTP ${response.responseCode} (${summarizeYtmLoopbackHeaders(headers)})`);
      }
      const total = parseYtmContentRangeTotal(readYtmHeader(headers, 'content-range'));
      if (total <= 0) {
        throw new Error(`sizing request returned no usable Content-Range (${summarizeYtmLoopbackHeaders(headers)})`);
      }
      const contentType = readYtmHeader(headers, 'content-type');
      Logger.info(`YTM loopback upstream entity: ${total} bytes type=${contentType.length > 0 ? contentType : 'unknown'}`);
      return { total, contentType };
    } finally {
      request.destroy();
    }
  }

  /**
   * Fetches one bounded chunk. Unlike requestInStream, request() reports the
   * real upstream status code, so a googlevideo rejection is an explicit error
   * instead of a header block that has to be sniffed for an entity.
   */
  private async fetchChunk(state: YtmConnectionState, range: string): Promise<ArrayBuffer> {
    const request = http.createHttp();
    state.upstream = request;
    try {
      const response = await request.request(this.sourceUrl, {
        method: http.RequestMethod.GET,
        header: { 'User-Agent': HttpClient.DEFAULT_UA, 'Range': range },
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: UPSTREAM_CONNECT_TIMEOUT,
        readTimeout: UPSTREAM_READ_TIMEOUT,
        usingProxy: HttpClient.usingProxyValue()
      });
      if (response.responseCode !== 206 && response.responseCode !== 200) {
        const headers = response.header as Record<string, string>;
        throw new Error(`chunk ${range} returned HTTP ${response.responseCode} (${summarizeYtmLoopbackHeaders(headers)})`);
      }
      if (!(response.result instanceof ArrayBuffer)) {
        throw new Error(`chunk ${range} returned a non-binary body`);
      }
      return response.result as ArrayBuffer;
    } finally {
      if (state.upstream === request) {
        state.upstream = null;
      }
      request.destroy();
    }
  }

  private async send(
    connection: socket.TCPSocketConnection,
    state: YtmConnectionState,
    data: ArrayBuffer
  ): Promise<void> {
    if (state.aborted) {
      return;
    }
    try {
      await connection.send({ data });
    } catch (error) {
      const failure = error as Error;
      Logger.debug(`YTM loopback send failed, treating the connection as gone: ${failure.message}`);
      this.abort(state);
    }
  }

  private async sendStatus(
    connection: socket.TCPSocketConnection,
    state: YtmConnectionState,
    status: string
  ): Promise<void> {
    Logger.warn(`YTM loopback replying ${status} to AVPlayer`);
    await this.send(
      connection, state,
      this.encode(`HTTP/1.1 ${status}\r\nConnection: close\r\nContent-Length: 0\r\n\r\n`)
    );
    await this.close(connection, state);
  }

  private async close(connection: socket.TCPSocketConnection, state: YtmConnectionState): Promise<void> {
    this.abort(state);
    try {
      await connection.close();
    } catch (_) {
      // Ignore peer close races.
    }
  }

  private abort(state: YtmConnectionState): void {
    state.aborted = true;
    if (state.upstream !== null) {
      state.upstream.destroy();
      state.upstream = null;
    }
  }

  private encode(text: string): ArrayBuffer {
    return new util.TextEncoder().encodeInto(text).buffer;
  }
}
