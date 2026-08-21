import { http, socket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { Logger } from '../../app/Logger';
import { HttpClient } from '../HttpClient';
import {
  buildYtmLoopbackResponseHeaders,
  normalizeYtmRange,
  parseYtmLoopbackRequest,
  serializeYtmLoopbackResponseHeaders
} from './YtmLoopbackHttp';

const LOOPBACK_ADDRESS = '127.0.0.1';
const AUDIO_PATH = '/ytm-stream';

/**
 * Serves one resolved googlevideo URL through a local HTTP socket. AVPlayer's
 * media service can reach loopback, while the upstream NetworkKit request
 * explicitly uses the app proxy. Each AVPlayer Range request gets its own
 * upstream stream, so no full-track pre-download is required.
 */
export class YtmLoopbackStreamBridge {
  private server: socket.TCPSocketServer | null = null;
  private sourceUrl: string = '';
  private listenPort: number = 0;
  private connections: socket.TCPSocketConnection[] = [];

  async start(sourceUrl: string): Promise<string> {
    await this.stop();
    if (sourceUrl.length === 0) {
      throw new Error('YTM loopback source URL is empty');
    }
    const server = socket.constructTCPSocketServerInstance();
    this.sourceUrl = sourceUrl;
    this.server = server;
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
  }

  private async handleConnection(connection: socket.TCPSocketConnection): Promise<void> {
    let requestBytes = new Uint8Array(0);
    let handled = false;
    let request: http.HttpRequest | null = null;
    let sendChain: Promise<void> = Promise.resolve();
    const decoder = util.TextDecoder.create('utf-8');
    const closeConnection = async (): Promise<void> => {
      if (request !== null) {
        request.destroy();
        request = null;
      }
      try {
        await connection.close();
      } catch (_) {
        // Ignore peer close races.
      }
    };
    connection.on('close', () => {
      if (request !== null) {
        request.destroy();
        request = null;
      }
    });
    connection.on('error', () => {
      if (request !== null) {
        request.destroy();
        request = null;
      }
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
      if (end < 0 && requestBytes.length < 64 * 1024) {
        return;
      }
      handled = true;
      const parsed = parseYtmLoopbackRequest(text.substring(0, end >= 0 ? end : text.length));
      if (parsed !== null) {
        Logger.info(`YTM loopback request method=${parsed.method} path=${parsed.path} range=${parsed.range.length > 0 ? parsed.range : 'none'}`);
      }
      if (parsed === null || parsed.path !== AUDIO_PATH || (parsed.method !== 'GET' && parsed.method !== 'HEAD')) {
        sendChain = sendChain.then(async () => {
          await connection.send({ data: this.encode('HTTP/1.1 404 Not Found\r\nConnection: close\r\nContent-Length: 0\r\n\r\n') });
          await closeConnection();
        });
        return;
      }
      const range = normalizeYtmRange(parsed.range);
      if (parsed.method === 'HEAD') {
        sendChain = sendChain.then(async () => {
          await connection.send({ data: this.encode('HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n') });
          await closeConnection();
        });
        return;
      }
      request = http.createHttp();
      const upstream = request;
      let responseStarted = false;
      upstream.on('headersReceive', (rawHeaders: Object) => {
        const headers = rawHeaders as Record<string, string>;
        const response = buildYtmLoopbackResponseHeaders(headers);
        // NetworkKit reports the proxy CONNECT/intermediate header block
        // before the real googlevideo response. It has no entity length or
        // Content-Range and must not be exposed as the media response.
        if (response.contentLength < 0 && response.contentRange.length === 0) {
          Logger.debug('YTM loopback ignored intermediate proxy headers');
          return;
        }
        Logger.info(`YTM loopback upstream headers status=${response.statusCode} type=${response.contentType} length=${response.contentLength} range=${response.contentRange.length > 0 ? 'yes' : 'no'}`);
        responseStarted = true;
        sendChain = sendChain.then(() => connection.send({
          data: this.encode(serializeYtmLoopbackResponseHeaders(response))
        }));
      });
      upstream.on('dataReceive', (chunk: ArrayBuffer) => {
        sendChain = sendChain.then(() => connection.send({ data: chunk }));
      });
      upstream.on('dataEnd', () => {
        sendChain = sendChain.then(async () => {
          if (!responseStarted) {
            await connection.send({ data: this.encode('HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\nContent-Length: 0\r\n\r\n') });
          }
          await closeConnection();
        });
      });
      const headers: Record<string, string> = { 'User-Agent': HttpClient.DEFAULT_UA };
      if (range.length > 0) {
        headers['Range'] = range;
      }
      upstream.requestInStream(this.sourceUrl, {
        method: http.RequestMethod.GET,
        header: headers,
        connectTimeout: 30000,
        readTimeout: 30000,
        usingProxy: HttpClient.usingProxyValue()
      }).catch((error: Error) => {
        Logger.warn(`YTM loopback upstream failed: ${error.message}`);
        if (!responseStarted) {
          sendChain = sendChain.then(async () => {
            await connection.send({ data: this.encode('HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\nContent-Length: 0\r\n\r\n') });
            await closeConnection();
          });
        }
      });
    });
  }

  private encode(text: string): ArrayBuffer {
    return new util.TextEncoder().encodeInto(text).buffer;
  }
}
