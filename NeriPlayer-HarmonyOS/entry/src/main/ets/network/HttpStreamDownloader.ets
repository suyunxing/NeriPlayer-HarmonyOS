import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '../app/Logger';
import { HttpClient } from './HttpClient';

export class StreamDownloadHeaders {
  responseCode: number = 0;
  contentLength: number = -1;
  etag: string = '';
  lastModified: string = '';
  contentRangeStart: number = -1;
  acceptRanges: boolean = false;
}

export interface StreamDownloadCallbacks {
  /** Called once with the parsed response headers. */
  onHeaders: (headers: StreamDownloadHeaders) => void;
  /**
   * Called for every body chunk in order. Return false to abort the
   * transfer (e.g. cancelled download); the promise then rejects with a
   * 'aborted' error.
   */
  onData: (chunk: ArrayBuffer, receivedBytes: number) => boolean;
  /** Optional progress hook with totals reported by the stack. */
  onProgress?: (received: number, total: number) => void;
}

/**
 * Streaming HTTP download over requestInStream, supporting Range/If-Range
 * resume requests (mirroring the Android OkHttp-based transfer core).
 */
export class HttpStreamDownloader {
  /**
   * Downloads url to the callbacks. rangeStart >= 0 sends
   * `Range: bytes=<rangeStart>-` plus `If-Range` when a validator exists.
   * Resolves with the final response code after dataEnd; rejects on
   * transport errors or when onData aborts.
   */
  static download(
    url: string,
    rangeStart: number,
    validator: string,
    callbacks: StreamDownloadCallbacks,
    timeoutMs: number = 30000
  ): Promise<number> {
    const request = http.createHttp();
    return new Promise<number>((resolve, reject) => {
      let received = 0;
      let headersSeen = false;
      let settled = false;
      const finish = (fn: () => void): void => {
        if (settled) {
          return;
        }
        settled = true;
        // destroy() unregisters the stream listeners and frees the handle.
        request.destroy();
        fn();
      };
      request.on('headersReceive', (rawHeader: Object) => {
        headersSeen = true;
        const header = rawHeader as Record<string, string>;
        const parsed = new StreamDownloadHeaders();
        parsed.etag = header['etag'] ?? '';
        parsed.lastModified = header['last-modified'] ?? '';
        parsed.acceptRanges = (header['accept-ranges'] ?? '').indexOf('bytes') >= 0;
        const lengthRaw = header['content-length'];
        if (lengthRaw !== undefined && lengthRaw.length > 0) {
          parsed.contentLength = Number(lengthRaw);
        }
        const rangeRaw = header['content-range'];
        if (rangeRaw !== undefined) {
          const start = rangeRaw.indexOf(' ');
          const dash = rangeRaw.indexOf('-');
          if (start >= 0 && dash > start) {
            const startValue = Number(rangeRaw.substring(start + 1, dash));
            parsed.contentRangeStart = Number.isNaN(startValue) ? -1 : startValue;
          }
        }
        callbacks.onHeaders(parsed);
      });
      request.on('dataReceive', (chunk: ArrayBuffer) => {
        received += chunk.byteLength;
        if (!callbacks.onData(chunk, received)) {
          finish(() => reject(new Error('aborted')));
          return;
        }
      });
      request.on('dataReceiveProgress', (info: http.DataReceiveProgressInfo) => {
        if (callbacks.onProgress !== undefined) {
          callbacks.onProgress(info.receiveSize, info.totalSize);
        }
      });
      request.on('dataEnd', () => {
        finish(() => resolve(0));
      });
      const header: Record<string, string> = {
        'User-Agent': HttpClient.DEFAULT_UA
      };
      if (rangeStart >= 0) {
        header['Range'] = `bytes=${rangeStart}-`;
        if (validator.length > 0) {
          header['If-Range'] = validator;
        }
      }
      request.requestInStream(url, {
        method: http.RequestMethod.GET,
        header: header,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs
      }).then((code: number) => {
        if (code >= 200 && code < 300) {
          // dataEnd will settle the promise; guard against a stack that
          // skips dataEnd.
          setTimeout(() => finish(() => resolve(code)), 100);
          return;
        }
        finish(() => resolve(code));
      }).catch((error: BusinessError) => {
        if (!headersSeen) {
          finish(() => reject(new Error(`HTTP stream failed: code=${error.code} message=${error.message}`)));
        } else {
          finish(() => reject(new Error(`HTTP stream failed: code=${error.code} message=${error.message}`)));
        }
      });
    });
  }

  /** Convenience probe: one-chunk ranged GET to inspect resume support. */
  static async probeRangeSupport(url: string): Promise<StreamDownloadHeaders> {
    const headers = new StreamDownloadHeaders();
    await HttpStreamDownloader.download(url, 0, '', {
      onHeaders: (parsed: StreamDownloadHeaders) => {
        headers.contentLength = parsed.contentLength;
        headers.etag = parsed.etag;
        headers.lastModified = parsed.lastModified;
        headers.acceptRanges = parsed.acceptRanges;
        headers.contentRangeStart = parsed.contentRangeStart;
      },
      onData: (chunk: ArrayBuffer) => {
        // Abort after the first chunk: only the headers matter here.
        return chunk.byteLength < 0;
      }
    }).catch((error: Error) => {
      Logger.debug(`probeRangeSupport ended: ${error.message}`);
    });
    return headers;
  }
}
