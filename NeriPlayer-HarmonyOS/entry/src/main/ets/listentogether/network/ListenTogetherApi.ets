// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Port of listentogether/network/http/ListenTogetherApi.kt.
 *
 * Deliberately does NOT reuse `HttpClient.postJson`/`getText`: those throw
 * `HTTP <code> for POST <url>` and discard the response body, whereas the room
 * protocol needs both the status code and the body inside the error message —
 * `isTerminalListenTogetherReconnectError` matches `(410)` and
 * `"error":"room not initialized"` in it to stop a hopeless reconnect loop.
 * Proxy handling and the UA are kept identical to `HttpClient` so the emulator's
 * host-proxy setup keeps working.
 *
 * One documented divergence: upstream enforces the 2 MiB response ceiling while
 * streaming, so it aborts mid-download. `http.request` buffers the whole body
 * before returning, so the ceiling here can only reject after the fact — it
 * still protects the JSON parser and the log pipeline, but not the socket read.
 * `requestInStream` was not used because M6.5 established that its response
 * codes are unreliable on this stack, and a correct status code is exactly what
 * this layer exists to provide.
 */
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '../../app/Logger';
import { HttpClient } from '../../network/HttpClient';
import {
  ListenTogetherControlResponse,
  ListenTogetherCreateRoomRequest,
  ListenTogetherInitialSnapshot,
  ListenTogetherJoinRoomRequest,
  ListenTogetherLeaveRoomResponse,
  ListenTogetherRoomResponse,
  ListenTogetherStateResponse,
  LISTEN_TOGETHER_LEAVE_ROOM_REQUEST_JSON,
  listenTogetherControlResponseFromJson,
  listenTogetherCreateRoomRequestToRecord,
  listenTogetherJoinRoomRequestToRecord,
  listenTogetherLeaveRoomResponseFromJson,
  listenTogetherRoomResponseFromJson,
  listenTogetherStateResponseFromJson
} from '../protocol/ListenTogetherHttpMessages';
import { ListenTogetherEvent, listenTogetherEventToRecord } from '../protocol/ListenTogetherEventModels';
import {
  LISTEN_TOGETHER_MAX_HTTP_RESPONSE_BYTES,
  LISTEN_TOGETHER_TEST_INVALID_BASE_URL,
  ListenTogetherServerTestResult,
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
} from './ListenTogetherApiRequests';

const LISTEN_TOGETHER_TIMEOUT_MS: number = 15000;
const LISTEN_TOGETHER_JSON_CONTENT_TYPE: string = 'application/json; charset=utf-8';

/** Status code plus body, so callers can shape upstream's error message. */
class ListenTogetherHttpResult {
  statusCode: number = 0;
  body: string = '';
}

export class ListenTogetherApi {
  async createRoom(
    baseUrl: string,
    userUuid: string,
    nickname: string,
    initialSnapshot: ListenTogetherInitialSnapshot
  ): Promise<ListenTogetherRoomResponse> {
    const request = new ListenTogetherCreateRoomRequest();
    request.userUuid = userUuid;
    request.nickname = nickname;
    request.initialSnapshot = initialSnapshot;
    const body = JSON.stringify(listenTogetherCreateRoomRequestToRecord(request));
    const text = await this.postText(listenTogetherCreateRoomUrl(baseUrl), body, null);
    return ListenTogetherApi.requireParsed(listenTogetherRoomResponseFromJson(text), 'RoomResponse');
  }

  async joinRoom(
    baseUrl: string,
    roomId: string,
    userUuid: string,
    nickname: string,
    memberSecret: string | null = null,
    joinSecret: string | null = null,
    bearerToken: string | null = null
  ): Promise<ListenTogetherRoomResponse> {
    const request = new ListenTogetherJoinRoomRequest();
    request.userUuid = userUuid;
    request.nickname = nickname;
    request.memberSecret = memberSecret;
    request.joinSecret = joinSecret;
    const body = JSON.stringify(listenTogetherJoinRoomRequestToRecord(request));
    const text = await this.postText(listenTogetherJoinRoomUrl(baseUrl, roomId), body, bearerToken);
    return ListenTogetherApi.requireParsed(listenTogetherRoomResponseFromJson(text), 'RoomResponse');
  }

  async getRoomState(
    baseUrl: string,
    roomId: string,
    bearerToken: string | null = null
  ): Promise<ListenTogetherStateResponse> {
    const text = await this.getText(listenTogetherRoomStateUrl(baseUrl, roomId), bearerToken);
    return ListenTogetherApi.requireParsed(listenTogetherStateResponseFromJson(text), 'StateResponse');
  }

  async leaveRoom(baseUrl: string, roomId: string, token: string): Promise<ListenTogetherLeaveRoomResponse> {
    const text = await this.postText(
      listenTogetherLeaveRoomUrl(baseUrl, roomId),
      LISTEN_TOGETHER_LEAVE_ROOM_REQUEST_JSON,
      token
    );
    return ListenTogetherApi.requireParsed(listenTogetherLeaveRoomResponseFromJson(text), 'LeaveRoomResponse');
  }

  async sendControlEvent(
    baseUrl: string,
    roomId: string,
    token: string,
    event: ListenTogetherEvent
  ): Promise<ListenTogetherControlResponse> {
    const body = JSON.stringify(listenTogetherEventToRecord(event));
    const text = await this.postText(listenTogetherControlUrl(baseUrl, roomId), body, token);
    return ListenTogetherApi.requireParsed(listenTogetherControlResponseFromJson(text), 'ControlResponse');
  }

  /**
   * Upstream `testServerAvailability`: never throws, and a non-2xx `/healthz`
   * is judged purely on the body marker, exactly as upstream does (it ignores
   * `isSuccessful` here on purpose — some deployments answer 404 with the
   * worker banner).
   */
  async testServerAvailability(baseUrl: string): Promise<ListenTogetherServerTestResult> {
    const url = listenTogetherHealthzUrlOrNull(baseUrl);
    if (url === null) {
      return listenTogetherServerTestResult(false, LISTEN_TOGETHER_TEST_INVALID_BASE_URL);
    }
    try {
      const result = await this.requestText(url, http.RequestMethod.GET, null, null);
      return listenTogetherHealthResultForBody(result.body);
    } catch (error) {
      const err = error as BusinessError;
      const message = (err.message ?? '').trim();
      return listenTogetherServerTestResult(false, message.length > 0 ? message : `errno=${err.code}`);
    }
  }

  private async getText(url: string, bearerToken: string | null): Promise<string> {
    const result = await this.requestText(url, http.RequestMethod.GET, null, bearerToken);
    return ListenTogetherApi.requireSuccessful('GET', result);
  }

  private async postText(url: string, body: string, bearerToken: string | null): Promise<string> {
    const result = await this.requestText(url, http.RequestMethod.POST, body, bearerToken);
    return ListenTogetherApi.requireSuccessful('POST', result);
  }

  private async requestText(
    url: string,
    method: http.RequestMethod,
    body: string | null,
    bearerToken: string | null
  ): Promise<ListenTogetherHttpResult> {
    const request = http.createHttp();
    try {
      const header: Record<string, string> = { 'User-Agent': HttpClient.DEFAULT_UA };
      if (body !== null) {
        header['Content-Type'] = LISTEN_TOGETHER_JSON_CONTENT_TYPE;
      }
      const authorization = listenTogetherBearerHeaderOrNull(bearerToken);
      if (authorization !== null) {
        header['Authorization'] = authorization;
      }
      const options: http.HttpRequestOptions = {
        method: method,
        header: header,
        connectTimeout: LISTEN_TOGETHER_TIMEOUT_MS,
        readTimeout: LISTEN_TOGETHER_TIMEOUT_MS,
        expectDataType: http.HttpDataType.STRING,
        usingProxy: HttpClient.usingProxyValue()
      };
      if (body !== null) {
        options.extraData = body;
      }
      const response = await request.request(url, options);
      const text = response.result as string;
      const byteCount = ListenTogetherApi.utf8ByteLengthLowerBound(text);
      if (isListenTogetherResponseTooLarge(byteCount)) {
        throw new Error(listenTogetherOversizeResponseMessage(byteCount));
      }
      const result = new ListenTogetherHttpResult();
      result.statusCode = response.responseCode;
      result.body = text;
      return result;
    } finally {
      request.destroy();
    }
  }

  /** Upstream: throw IOException("ListenTogether <M> failed (<code>): <body>"). */
  private static requireSuccessful(method: string, result: ListenTogetherHttpResult): string {
    if (result.statusCode < 200 || result.statusCode >= 300) {
      throw new Error(listenTogetherHttpErrorMessage(method, result.statusCode, result.body));
    }
    return result.body;
  }

  /**
   * A malformed body is upstream's `decodeFromString` throwing; the body itself
   * is not put in the message because it may carry the room token.
   */
  private static requireParsed<T>(parsed: T | null, kind: string): T {
    if (parsed === null) {
      Logger.warn(`ListenTogether ${kind} parse failed`);
      throw new Error(`ListenTogether response is not a valid ${kind}`);
    }
    return parsed;
  }

  /**
   * UTF-16 length is a lower bound on the UTF-8 byte count only up to a factor
   * of 3, so anything that could not possibly exceed the ceiling skips the
   * encode; oversize candidates get an exact count for the error message.
   */
  private static utf8ByteLengthLowerBound(text: string): number {
    if (text.length * 3 <= LISTEN_TOGETHER_MAX_HTTP_RESPONSE_BYTES) {
      return text.length;
    }
    return new util.TextEncoder().encodeInto(text).byteLength;
  }
}
