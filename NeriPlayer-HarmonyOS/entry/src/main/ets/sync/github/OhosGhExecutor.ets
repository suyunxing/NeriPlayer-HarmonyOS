/**
 * @ohos.net.http adapter for the GitHub transport. This is the only file in
 * sync/github with platform imports - everything else stays pure for local
 * hypium tests.
 *
 * RequestMethod has no PATCH enum value on this SDK, but the official
 * customMethod option (@since 23; verified in the API 24 SDK d.ts line 576,
 * netstack maps it to CURLOPT_CUSTOMREQUEST so a real PATCH request line is
 * sent and the body still uploads). The GitHub branch-ref update relies on it.
 */

import { http } from '@kit.NetworkKit';
import { HttpHeaderParser } from '../../network/HttpHeaderParser';
import { GhExecutor, GhRequest, GhResponse } from './GitHubTransport';
import { utf8EncodeText } from '../SyncDataJsonCodec';
import { Logger } from '../../app/Logger';

const TAG: string = 'OhosGhExecutor';
const CONNECT_TIMEOUT_MS: number = 15000;
const READ_TIMEOUT_MS: number = 60000;

export class OhosGhExecutor implements GhExecutor {
  async execute(request: GhRequest): Promise<GhResponse> {
    const client = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: request.method === 'POST' || request.method === 'PATCH' ?
          http.RequestMethod.POST : request.method === 'PUT' ? http.RequestMethod.PUT :
            request.method === 'DELETE' ? http.RequestMethod.DELETE : http.RequestMethod.GET,
        header: headerRecord(request.headers),
        connectTimeout: CONNECT_TIMEOUT_MS,
        readTimeout: READ_TIMEOUT_MS,
        usingCache: false,
        // Force binary so JSON responses are never auto-parsed into Objects.
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      };
      if (request.method === 'PATCH') {
        options.customMethod = 'PATCH';
      }
      if (request.bodyText !== null) {
        options.extraData = request.bodyText;
      }
      const response = await client.request(request.url, options);
      const out = new GhResponse();
      out.status = response.responseCode;
      out.headers = headerMap(response.header);
      out.bodyBytes = bodyBytes(response.result);
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
  const record: Record<string, string> = {};
  for (const entry of headers) {
    record[entry[0]] = entry[1];
  }
  return record;
}

function headerMap(headerValue: Object): Map<string, string> {
  const map = new Map<string, string>();
  const text = HttpHeaderParser.toHeaderText(headerValue);
  const lines = text.split('\n');
  for (const line of lines) {
    const colon = line.indexOf(':');
    if (colon <= 0) {
      continue;
    }
    map.set(line.substring(0, colon).trim().toLowerCase(), line.substring(colon + 1).trim());
  }
  return map;
}

function bodyBytes(result: Object): Uint8Array {
  if (typeof result === 'string') {
    return utf8EncodeText(result as string);
  }
  if (result instanceof ArrayBuffer) {
    return new Uint8Array(result);
  }
  return new Uint8Array(0);
}
