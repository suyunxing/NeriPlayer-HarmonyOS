// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Pure WebDAV transport with an injected HTTP executor.
 *
 * Concurrency semantics mirror Android WebDavApiClient:
 * - strong ETag is preferred; weak ETags are ignored;
 * - Last-Modified is the fallback condition token;
 * - creation uses If-None-Match: *;
 * - servers exposing neither token require a fresh SHA-256 fingerprint check
 *   before one explicitly allowed unconditional PUT.
 */

import { encodeBase64 } from '../../util/Base64';
import { utf8Decode, utf8EncodeText } from '../SyncDataJsonCodec';
import { sha256ByteArray } from '../SyncModels';
import {
  WebDavError,
  WebDavErrorKind,
  classifyWebDavFailure,
  missingConcurrencyTokenError
} from './WebDavErrors';

export const WEBDAV_REMOTE_FILE_NAME: string = 'neriplayer-sync.json';
export const MAX_WEBDAV_FILE_BYTES: number = 12 * 1024 * 1024;
const USER_AGENT: string = 'NeriPlayer-HarmonyOS-sync';
const PROPFIND_BODY: string = '<?xml version="1.0" encoding="utf-8"?>' +
  '<d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/></d:prop></d:propfind>';

export class WebDavRequest {
  method: string = 'GET';
  url: string = '';
  headers: Map<string, string> = new Map<string, string>();
  bodyBytes: Uint8Array = new Uint8Array(0);
}

export class WebDavResponse {
  status: number = 0;
  headers: Map<string, string> = new Map<string, string>();
  bodyBytes: Uint8Array = new Uint8Array(0);

  bodyText(): string {
    return utf8Decode(this.bodyBytes);
  }
}

export interface WebDavExecutor {
  execute(request: WebDavRequest): Promise<WebDavResponse>;
}

export class WebDavConcurrencyToken {
  etag: string | null = null;
  lastModified: string | null = null;

  hasConditionToken(): boolean {
    return (this.etag !== null && this.etag.length > 0) ||
      (this.lastModified !== null && this.lastModified.length > 0);
  }
}

export class WebDavRemoteFileSnapshot {
  content: Uint8Array = new Uint8Array(0);
  fingerprint: string = '';
  version: WebDavConcurrencyToken = new WebDavConcurrencyToken();
}

export class WebDavWriteResult {
  fingerprint: string = '';
  version: WebDavConcurrencyToken = new WebDavConcurrencyToken();
}

export class WebDavRemoteVersion {
  token: WebDavConcurrencyToken | null = null;
  createOnly: boolean = false;
  lastKnownFingerprint: string | null = null;
}

export class WebDavSyncSnapshot {
  content: Uint8Array = new Uint8Array(0);
  fingerprint: string = '';
  version: WebDavRemoteVersion = new WebDavRemoteVersion();
}

export function calculateWebDavFingerprint(content: Uint8Array): string {
  const digest = sha256ByteArray(content);
  let out = '';
  for (const value of digest) {
    out += value.toString(16).padStart(2, '0');
  }
  return out;
}

export function shouldAllowUnconditionalWebDavWrite(expectedFingerprint: string | null,
  currentFingerprint: string | null): boolean {
  return expectedFingerprint !== null && expectedFingerprint.trim().length > 0 &&
    expectedFingerprint === currentFingerprint;
}

export function normalizeWebDavServerUrl(serverUrl: string): string {
  const normalized = serverUrl.trim().replace(/\/+$/, '');
  if (!(normalized.startsWith('https://') || normalized.startsWith('http://'))) {
    throw new WebDavError(WebDavErrorKind.API, 0, 'WebDAV server URL must use http:// or https://');
  }
  const authorityStart = normalized.indexOf('://') + 3;
  const firstSlash = normalized.indexOf('/', authorityStart);
  const authority = firstSlash < 0 ? normalized.substring(authorityStart) :
    normalized.substring(authorityStart, firstSlash);
  if (authority.length === 0 || authority.includes('@') || normalized.includes('?') ||
    normalized.includes('#')) {
    throw new WebDavError(WebDavErrorKind.API, 0, 'Invalid WebDAV server URL');
  }
  return normalized;
}

export function normalizeWebDavBasePath(basePath: string): string {
  return basePath.trim().replace(/^\/+|\/+$/g, '');
}

export function buildWebDavCollectionUrl(serverUrl: string, basePath: string): string {
  let url = normalizeWebDavServerUrl(serverUrl);
  const path = normalizeWebDavBasePath(basePath);
  if (path.length > 0) {
    const encoded: string[] = [];
    for (const segment of path.split('/')) {
      const trimmed = segment.trim();
      if (trimmed.length > 0) {
        encoded.push(encodeURIComponent(trimmed));
      }
    }
    if (encoded.length > 0) {
      url += `/${encoded.join('/')}`;
    }
  }
  return `${url}/`;
}

export function buildWebDavRemoteFileUrl(serverUrl: string, basePath: string): string {
  return `${buildWebDavCollectionUrl(serverUrl, basePath)}${WEBDAV_REMOTE_FILE_NAME}`;
}

export class WebDavTransport {
  private readonly executor: WebDavExecutor;
  private readonly authorization: string;

  constructor(executor: WebDavExecutor, username: string, password: string) {
    this.executor = executor;
    this.authorization = `Basic ${encodeBase64(utf8EncodeText(`${username}:${password}`))}`;
  }

  /** PROPFIND Depth:0 verifies the configured collection and credentials. */
  async validateConnection(serverUrl: string, basePath: string): Promise<void> {
    const request = this.newRequest('PROPFIND', buildWebDavCollectionUrl(serverUrl, basePath));
    request.headers.set('Depth', '0');
    request.headers.set('Content-Type', 'application/xml; charset=utf-8');
    request.bodyBytes = utf8EncodeText(PROPFIND_BODY);
    await this.executeSuccess('validateConnection', request, true);
  }

  /** RFC 4918 MOVE with an absolute Destination URI; servers may reject with 405/501. */
  async moveFile(sourceUrl: string, destinationUrl: string, overwrite: boolean): Promise<WebDavResponse> {
    const request = this.newRequest('MOVE', sourceUrl);
    request.headers.set('Destination', destinationUrl);
    request.headers.set('Overwrite', overwrite ? 'T' : 'F');
    return this.executeSuccess('moveFile', request);
  }

  /** Best-effort cleanup of leftover upload workspace files; never throws. */
  async tryDeleteFile(remoteUrl: string): Promise<void> {
    try {
      await this.executeSuccess('deleteFile', this.newRequest('DELETE', remoteUrl));
    } catch (_error) {
      // Leftover temp files are cosmetic garbage; cleanup failures must not mask the real error.
    }
  }

  async getFileContentStrict(remoteUrl: string): Promise<WebDavRemoteFileSnapshot> {
    const response = await this.executeSuccess('getFileContent', this.newRequest('GET', remoteUrl));
    if (response.bodyBytes.length > MAX_WEBDAV_FILE_BYTES) {
      throw new WebDavError(WebDavErrorKind.API, response.status,
        `WebDAV remote file exceeds ${MAX_WEBDAV_FILE_BYTES} bytes`);
    }
    const snapshot = new WebDavRemoteFileSnapshot();
    snapshot.content = response.bodyBytes;
    snapshot.fingerprint = calculateWebDavFingerprint(response.bodyBytes);
    snapshot.version = extractConcurrencyToken(response.headers);
    return snapshot;
  }

  async updateFileContent(remoteUrl: string, content: Uint8Array,
    mediaType: string = 'application/octet-stream', expectedVersion: WebDavConcurrencyToken | null = null,
    createOnly: boolean = false, allowUnconditionalWrite: boolean = false): Promise<WebDavWriteResult> {
    if (content.length === 0) {
      throw new WebDavError(WebDavErrorKind.API, 0, 'WebDAV upload payload is empty');
    }
    if (content.length > MAX_WEBDAV_FILE_BYTES) {
      throw new WebDavError(WebDavErrorKind.API, 0,
        `WebDAV upload payload exceeds ${MAX_WEBDAV_FILE_BYTES} bytes`);
    }
    if (!createOnly && (expectedVersion === null || !expectedVersion.hasConditionToken()) &&
      !allowUnconditionalWrite) {
      throw missingConcurrencyTokenError();
    }
    const request = this.newRequest('PUT', remoteUrl);
    request.headers.set('Content-Type', mediaType);
    if (createOnly) {
      request.headers.set('If-None-Match', '*');
    } else if (expectedVersion !== null) {
      if (expectedVersion.etag !== null && expectedVersion.etag.length > 0) {
        request.headers.set('If-Match', expectedVersion.etag);
      } else if (expectedVersion.lastModified !== null && expectedVersion.lastModified.length > 0) {
        request.headers.set('If-Unmodified-Since', expectedVersion.lastModified);
      }
    }
    request.bodyBytes = content;
    const response = await this.executeSuccess('updateFileContent', request);
    const result = new WebDavWriteResult();
    result.fingerprint = calculateWebDavFingerprint(content);
    result.version = extractConcurrencyToken(response.headers);
    return result;
  }

  private newRequest(method: string, url: string): WebDavRequest {
    const request = new WebDavRequest();
    request.method = method;
    request.url = url;
    request.headers.set('Authorization', this.authorization);
    request.headers.set('User-Agent', USER_AGENT);
    request.headers.set('Accept', '*/*');
    return request;
  }

  private async executeSuccess(operation: string, request: WebDavRequest,
    dirProbe: boolean = false): Promise<WebDavResponse> {
    let response: WebDavResponse;
    try {
      response = await this.executor.execute(request);
    } catch (error) {
      const e = error as Error;
      throw new WebDavError(WebDavErrorKind.NETWORK, 0, `${operation} network error: ${e.message}`);
    }
    if (response.status < 200 || response.status >= 300) {
      throw classifyWebDavFailure(operation, response.status, response.bodyText(), dirProbe);
    }
    return response;
  }
}

export class WebDavSyncClient {
  private readonly transport: WebDavTransport;

  constructor(transport: WebDavTransport) {
    this.transport = transport;
  }

  async fetchRemoteSnapshot(remoteUrl: string): Promise<WebDavSyncSnapshot | null> {
    let remote: WebDavRemoteFileSnapshot;
    try {
      remote = await this.transport.getFileContentStrict(remoteUrl);
    } catch (error) {
      const e = error as WebDavError;
      if (e instanceof WebDavError && e.kind === WebDavErrorKind.FILE_NOT_FOUND) {
        return null;
      }
      if (e instanceof Error) {
        throw e;
      }
      throw new WebDavError(WebDavErrorKind.API, 0, 'Unknown WebDAV read failure');
    }
    if (remote.content.length === 0) {
      throw new WebDavError(WebDavErrorKind.API, 0, 'WebDAV remote backup file is empty');
    }
    const snapshot = new WebDavSyncSnapshot();
    snapshot.content = remote.content;
    snapshot.fingerprint = remote.fingerprint;
    snapshot.version.token = remote.version;
    snapshot.version.createOnly = false;
    snapshot.version.lastKnownFingerprint = remote.fingerprint;
    return snapshot;
  }

  /**
   * Atomic publish (Android upstream #495 semantics): upload to a per-call temp
   * name inside the target collection, verify the remote still matches the
   * version we merged from, then MOVE over the final name so an interrupted
   * transfer can never leave a truncated backup. Servers without MOVE support
   * (403/405/501) fall back to the legacy direct conditional PUT.
   */
  async uploadBackup(remoteUrl: string, content: Uint8Array, mediaType: string,
    version: WebDavRemoteVersion): Promise<WebDavWriteResult> {
    await this.verifyRemoteStateForUpload(remoteUrl, version);
    const tempUrl = await this.uploadToTempFile(remoteUrl, content, mediaType);
    let moveResponse: WebDavResponse;
    try {
      moveResponse = await this.transport.moveFile(tempUrl, remoteUrl, !version.createOnly);
    } catch (error) {
      await this.transport.tryDeleteFile(tempUrl);
      const e = error as WebDavError;
      if (e instanceof WebDavError && !version.createOnly &&
        (e.statusCode === 403 || e.statusCode === 405 || e.statusCode === 501)) {
        return this.directConditionalUpload(remoteUrl, content, mediaType, version);
      }
      if (e instanceof Error) {
        throw e;
      }
      throw new WebDavError(WebDavErrorKind.API, 0, 'Unknown WebDAV publish failure');
    }
    const result = new WebDavWriteResult();
    result.fingerprint = calculateWebDavFingerprint(content);
    result.version = extractConcurrencyToken(moveResponse.headers);
    return result;
  }

  /**
   * Pre-publish guard replacing the old If-Match/If-None-Match headers: the
   * final resource must still be exactly the state we merged from. Unlike a
   * conditional PUT, this check runs before the payload transfer, so the
   * residual race window spans verify→MOVE instead of blocking the upload.
   */
  private async verifyRemoteStateForUpload(remoteUrl: string,
    version: WebDavRemoteVersion): Promise<void> {
    const hasToken = version.token !== null && version.token.hasConditionToken();
    const hasFingerprint = version.lastKnownFingerprint !== null &&
      version.lastKnownFingerprint.trim().length > 0;
    if (!version.createOnly && !hasToken && !hasFingerprint) {
      throw new WebDavError(WebDavErrorKind.CONTENT_CONFLICT, 412,
        'WebDAV upload rejected: no fingerprint or concurrency token to verify against');
    }
    let remote: WebDavRemoteFileSnapshot;
    try {
      remote = await this.transport.getFileContentStrict(remoteUrl);
    } catch (error) {
      const e = error as WebDavError;
      if (e instanceof WebDavError && e.kind === WebDavErrorKind.FILE_NOT_FOUND) {
        if (version.createOnly) {
          return;
        }
        // A vanished backup cannot be condition-overwritten either; the
        // coordinator refetches, sees null and retries as create-only.
        throw new WebDavError(WebDavErrorKind.CONTENT_CONFLICT, 412,
          'WebDAV remote backup vanished while syncing');
      }
      if (e instanceof Error) {
        throw e;
      }
      throw new WebDavError(WebDavErrorKind.API, 0, 'Unknown WebDAV read failure');
    }
    if (version.createOnly) {
      throw new WebDavError(WebDavErrorKind.CONTENT_CONFLICT, 412,
        'WebDAV remote backup already exists (create-only upload)');
    }
    if (hasFingerprint && remote.fingerprint !== version.lastKnownFingerprint) {
      throw new WebDavError(WebDavErrorKind.CONTENT_CONFLICT, 412,
        'WebDAV remote content changed while syncing');
    }
    if (hasToken && !sameConcurrencyToken(remote.version, version.token as WebDavConcurrencyToken)) {
      throw new WebDavError(WebDavErrorKind.CONTENT_CONFLICT, 412,
        'WebDAV remote version token changed while syncing');
    }
  }

  /** Uploads the payload to a unique temp sibling of the final URL. */
  private async uploadToTempFile(remoteUrl: string, content: Uint8Array,
    mediaType: string): Promise<string> {
    const prefix = calculateWebDavFingerprint(content).substring(0, 12);
    let attempt = 0;
    while (true) {
      const tempUrl = `${remoteUrl}.tmp-${prefix}-${nextTempCounter()}`;
      try {
        await this.transport.updateFileContent(tempUrl, content, mediaType, null, true);
        return tempUrl;
      } catch (error) {
        const e = error as WebDavError;
        if (!(e instanceof WebDavError) || e.kind !== WebDavErrorKind.CONTENT_CONFLICT) {
          if (e instanceof Error) {
            throw e;
          }
          throw new WebDavError(WebDavErrorKind.API, 0, 'Unknown WebDAV temp upload failure');
        }
        attempt += 1;
        if (attempt >= 2) {
          // Temp-name collision with an in-flight upload that persisted across
          // one regenerated name; bail out as a plain API failure.
          throw new WebDavError(WebDavErrorKind.API, 412,
            'WebDAV temp upload name collision');
        }
      }
    }
  }

  /** Legacy single-request path for servers that reject MOVE. */
  private async directConditionalUpload(remoteUrl: string, content: Uint8Array, mediaType: string,
    version: WebDavRemoteVersion): Promise<WebDavWriteResult> {
    try {
      return await this.transport.updateFileContent(remoteUrl, content, mediaType,
        version.token, version.createOnly, false);
    } catch (error) {
      const e = error as WebDavError;
      if (version.createOnly || !(e instanceof WebDavError) ||
        e.kind !== WebDavErrorKind.MISSING_CONCURRENCY_TOKEN) {
        if (e instanceof Error) {
          throw e;
        }
        throw new WebDavError(WebDavErrorKind.API, 0, 'Unknown WebDAV upload failure');
      }
    }
    const current = await this.transport.getFileContentStrict(remoteUrl);
    if (!shouldAllowUnconditionalWebDavWrite(version.lastKnownFingerprint, current.fingerprint)) {
      throw new WebDavError(WebDavErrorKind.CONTENT_CONFLICT, 412,
        'WebDAV remote content changed while conditional tokens were unavailable');
    }
    return this.transport.updateFileContent(remoteUrl, content, mediaType, null, false, true);
  }
}

let webDavTempCounter: number = 0;

function nextTempCounter(): number {
  webDavTempCounter += 1;
  return webDavTempCounter;
}

function sameConcurrencyToken(actual: WebDavConcurrencyToken,
  expected: WebDavConcurrencyToken): boolean {
  if (expected.etag !== null && expected.etag.length > 0) {
    return actual.etag === expected.etag;
  }
  if (expected.lastModified !== null && expected.lastModified.length > 0) {
    return actual.lastModified === expected.lastModified;
  }
  return true;
}

function extractConcurrencyToken(headers: Map<string, string>): WebDavConcurrencyToken {
  const token = new WebDavConcurrencyToken();
  const etag = headerValue(headers, 'etag').trim();
  if (etag.length > 0 && !etag.toUpperCase().startsWith('W/')) {
    token.etag = etag;
  }
  const lastModified = headerValue(headers, 'last-modified').trim();
  if (lastModified.length > 0) {
    token.lastModified = lastModified;
  }
  return token;
}

function headerValue(headers: Map<string, string>, lowerName: string): string {
  const direct = headers.get(lowerName);
  if (direct !== undefined) {
    return direct;
  }
  for (const entry of headers) {
    if (entry[0].toLowerCase() === lowerName) {
      return entry[1];
    }
  }
  return '';
}
