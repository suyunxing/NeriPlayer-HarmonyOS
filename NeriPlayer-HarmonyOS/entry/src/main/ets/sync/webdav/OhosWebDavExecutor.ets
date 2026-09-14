// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/** API 24 @ohos.net.http adapter for WebDAV custom methods and binary bodies. */

import { http } from '@kit.NetworkKit';
import { Logger } from '../../app/Logger';
import { HttpHeaderParser } from '../../network/HttpHeaderParser';
import { utf8EncodeText } from '../SyncDataJsonCodec';
import { WebDavExecutor, WebDavRequest, WebDavResponse } from './WebDavTransport';

const TAG: string = 'OhosWebDavExecutor';
const CONNECT_TIMEOUT_MS: number = 15000;
const READ_TIMEOUT_MS: number = 60000;

export class OhosWebDavExecutor implements WebDavExecutor {
  async execute(request: WebDavRequest): Promise<WebDavResponse> {
    const client = http.createHttp();
    try {
      const isCustom = request.method === 'PROPFIND';
      const options: http.HttpRequestOptions = {
        method: request.method === 'PUT' ? http.RequestMethod.PUT :
          isCustom ? http.RequestMethod.POST : http.RequestMethod.GET,
        header: headerRecord(request.headers),
        connectTimeout: CONNECT_TIMEOUT_MS,
        readTimeout: READ_TIMEOUT_MS,
        usingCache: false,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      };
      if (isCustom) {
        // RequestMethod has no PROPFIND value; customMethod is available since API 23.
        options.customMethod = request.method;
      }
      if (request.bodyBytes.length > 0) {
        options.extraData = exactArrayBuffer(request.bodyBytes);
      }
      const response = await client.request(request.url, options);
      const out = new WebDavResponse();
      out.status = response.responseCode;
      out.headers = headerMap(response.header);
      out.bodyBytes = responseBytes(response.result);
      return out;
    } catch (error) {
      const e = error as Error;
      Logger.warn(`${TAG} ${request.method} ${request.url} failed: ${e.message}`);
      throw e;
    } finally {
      client.destroy();
    }
  }
}

function headerRecord(headers: Map<string, string>): Record<string, string> {
  const out: Record<string, string> = {};
  for (const entry of headers) {
    out[entry[0]] = entry[1];
  }
  return out;
}

function headerMap(headerValue: Object): Map<string, string> {
  const out = new Map<string, string>();
  const lines = HttpHeaderParser.toHeaderText(headerValue).split('\n');
  for (const line of lines) {
    const colon = line.indexOf(':');
    if (colon > 0) {
      out.set(line.substring(0, colon).trim().toLowerCase(), line.substring(colon + 1).trim());
    }
  }
  return out;
}

function responseBytes(result: Object): Uint8Array {
  if (typeof result === 'string') {
    return utf8EncodeText(result as string);
  }
  if (result instanceof ArrayBuffer) {
    return new Uint8Array(result);
  }
  return new Uint8Array(0);
}

function exactArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  const copy = new Uint8Array(bytes.length);
  copy.set(bytes);
  return copy.buffer;
}
