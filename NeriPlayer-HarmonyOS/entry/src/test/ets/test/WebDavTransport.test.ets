import { describe, it, expect } from '@ohos/hypium';
import { utf8EncodeText } from '../../../main/ets/sync/SyncDataJsonCodec';
import {
  WebDavConcurrencyToken,
  WebDavExecutor,
  WebDavRemoteVersion,
  WebDavRequest,
  WebDavResponse,
  WebDavSyncClient,
  WebDavTransport,
  buildWebDavCollectionUrl,
  buildWebDavRemoteFileUrl,
  calculateWebDavFingerprint,
  shouldAllowUnconditionalWebDavWrite
} from '../../../main/ets/sync/webdav/WebDavTransport';
import {
  WebDavError,
  WebDavErrorKind,
  classifyWebDavFailure
} from '../../../main/ets/sync/webdav/WebDavErrors';

class QueuedWebDavExecutor implements WebDavExecutor {
  calls: WebDavRequest[] = [];
  responses: WebDavResponse[] = [];
  failure: Error | null = null;

  push(status: number, body: string = '', headers: Map<string, string> = new Map()): void {
    const response = new WebDavResponse();
    response.status = status;
    response.bodyBytes = utf8EncodeText(body);
    response.headers = headers;
    this.responses.push(response);
  }

  async execute(request: WebDavRequest): Promise<WebDavResponse> {
    this.calls.push(request);
    if (this.failure !== null) {
      throw this.failure;
    }
    if (this.responses.length === 0) {
      throw new Error('missing fake response');
    }
    return this.responses.shift() as WebDavResponse;
  }
}

function headers(pairs: string[][]): Map<string, string> {
  const out = new Map<string, string>();
  for (const pair of pairs) {
    out.set(pair[0], pair[1]);
  }
  return out;
}

async function rejection(promise: Promise<Object>): Promise<WebDavError> {
  try {
    await promise;
  } catch (error) {
    return error as WebDavError;
  }
  return new WebDavError(WebDavErrorKind.API, -1, 'expected rejection');
}

export default function webDavTransportTest(): void {
  describe('WebDavUrlAndFingerprint', () => {
    it('buildsEncodedCollectionAndRemoteFileUrls', 0, () => {
      expect(buildWebDavCollectionUrl(' https://dav.example/root/ ', '/Neri Player/备份/'))
        .assertEqual('https://dav.example/root/Neri%20Player/%E5%A4%87%E4%BB%BD/');
      expect(buildWebDavRemoteFileUrl('https://dav.example/root/', 'music'))
        .assertEqual('https://dav.example/root/music/neriplayer-sync.json');
    });

    it('rejectsCredentialsQueryAndInvalidSchemeInServerUrl', 0, () => {
      let failures = 0;
      for (const value of ['ftp://dav.example', 'https://u:p@dav.example',
        'https://dav.example/root?q=1']) {
        try {
          buildWebDavRemoteFileUrl(value, '');
        } catch (_error) {
          failures++;
        }
      }
      expect(failures).assertEqual(3);
    });

    it('matchesSha256FingerprintForBinaryContent', 0, () => {
      expect(calculateWebDavFingerprint(utf8EncodeText('abc')))
        .assertEqual('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      expect(calculateWebDavFingerprint(new Uint8Array([0, 255, 1])).length).assertEqual(64);
    });

    it('allowsFallbackOnlyForMatchingNonBlankFingerprint', 0, () => {
      expect(shouldAllowUnconditionalWebDavWrite('same', 'same')).assertTrue();
      expect(shouldAllowUnconditionalWebDavWrite('old', 'new')).assertFalse();
      expect(shouldAllowUnconditionalWebDavWrite('', '')).assertFalse();
      expect(shouldAllowUnconditionalWebDavWrite(null, 'old')).assertFalse();
    });
  });

  describe('WebDavTransportRequests', () => {
    it('validatesCollectionWithPropfindDepthZeroAndBasicAuth', 0, async () => {
      const executor = new QueuedWebDavExecutor();
      executor.push(207, '<multistatus/>');
      const transport = new WebDavTransport(executor, 'user', 'pass');
      await transport.validateConnection('https://dav.example/root', 'backup');
      expect(executor.calls.length).assertEqual(1);
      const call = executor.calls[0];
      expect(call.method).assertEqual('PROPFIND');
      expect(call.url).assertEqual('https://dav.example/root/backup/');
      expect(call.headers.get('Depth')).assertEqual('0');
      expect(call.headers.get('Authorization')).assertEqual('Basic dXNlcjpwYXNz');
      expect(call.bodyBytes.length > 0).assertTrue();
    });

    it('readsContentAndPrefersStrongEtag', 0, async () => {
      const executor = new QueuedWebDavExecutor();
      executor.push(200, 'abc', headers([
        ['ETag', '"strong-v1"'],
        ['Last-Modified', 'Wed, 19 Aug 2026 01:02:03 GMT']
      ]));
      const snapshot = await new WebDavTransport(executor, 'u', 'p')
        .getFileContentStrict('https://dav.example/file');
      expect(snapshot.version.etag).assertEqual('"strong-v1"');
      expect(snapshot.version.lastModified).assertEqual('Wed, 19 Aug 2026 01:02:03 GMT');
      expect(snapshot.fingerprint)
        .assertEqual('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });

    it('dropsWeakEtagButKeepsLastModified', 0, async () => {
      const executor = new QueuedWebDavExecutor();
      executor.push(200, 'x', headers([
        ['etag', 'W/"weak"'],
        ['last-modified', 'date-v1']
      ]));
      const snapshot = await new WebDavTransport(executor, 'u', 'p')
        .getFileContentStrict('https://dav.example/file');
      expect(snapshot.version.etag === null).assertTrue();
      expect(snapshot.version.lastModified).assertEqual('date-v1');
    });

    it('createOnlyPutUsesIfNoneMatchStar', 0, async () => {
      const executor = new QueuedWebDavExecutor();
      executor.push(201, '', headers([['etag', '"created"']]));
      const transport = new WebDavTransport(executor, 'u', 'p');
      await transport.updateFileContent('https://dav.example/file', utf8EncodeText('data'),
        'application/json', null, true);
      const call = executor.calls[0];
      expect(call.method).assertEqual('PUT');
      expect(call.headers.get('If-None-Match')).assertEqual('*');
      expect(call.headers.has('If-Match')).assertFalse();
    });

    it('updatePutUsesStrongEtagBeforeLastModified', 0, async () => {
      const executor = new QueuedWebDavExecutor();
      executor.push(204);
      const token = new WebDavConcurrencyToken();
      token.etag = '"v1"';
      token.lastModified = 'date-v1';
      await new WebDavTransport(executor, 'u', 'p').updateFileContent(
        'https://dav.example/file', utf8EncodeText('data'), 'application/json', token);
      const call = executor.calls[0];
      expect(call.headers.get('If-Match')).assertEqual('"v1"');
      expect(call.headers.has('If-Unmodified-Since')).assertFalse();
    });

    it('updatePutFallsBackToIfUnmodifiedSince', 0, async () => {
      const executor = new QueuedWebDavExecutor();
      executor.push(204);
      const token = new WebDavConcurrencyToken();
      token.lastModified = 'date-v1';
      await new WebDavTransport(executor, 'u', 'p').updateFileContent(
        'https://dav.example/file', utf8EncodeText('data'), 'application/json', token);
      expect(executor.calls[0].headers.get('If-Unmodified-Since')).assertEqual('date-v1');
    });

    it('missingTokenRejectsBeforeNetworkWrite', 0, async () => {
      const executor = new QueuedWebDavExecutor();
      const error = await rejection(new WebDavTransport(executor, 'u', 'p').updateFileContent(
        'https://dav.example/file', utf8EncodeText('data'), 'application/json',
        new WebDavConcurrencyToken()) as Promise<Object>);
      expect(error.kind).assertEqual(WebDavErrorKind.MISSING_CONCURRENCY_TOKEN);
      expect(executor.calls.length).assertEqual(0);
    });

    it('mapsExecutorFailureToNetworkError', 0, async () => {
      const executor = new QueuedWebDavExecutor();
      executor.failure = new Error('offline');
      const error = await rejection(new WebDavTransport(executor, 'u', 'p')
        .getFileContentStrict('https://dav.example/file') as Promise<Object>);
      expect(error.kind).assertEqual(WebDavErrorKind.NETWORK);
      expect(error.message.includes('offline')).assertTrue();
    });
  });

  describe('WebDavFailureAndFallback', () => {
    it('classifiesAuthNotFoundAndAllConflictCodes', 0, () => {
      expect(classifyWebDavFailure('read', 401, '').kind).assertEqual(WebDavErrorKind.AUTH);
      expect(classifyWebDavFailure('read', 404, '').kind).assertEqual(WebDavErrorKind.FILE_NOT_FOUND);
      for (const status of [409, 412, 423]) {
        expect(classifyWebDavFailure('write', status, 'locked').kind)
          .assertEqual(WebDavErrorKind.CONTENT_CONFLICT);
      }
    });

    it('missingRemoteFileBecomesFirstSyncNull', 0, async () => {
      const executor = new QueuedWebDavExecutor();
      executor.push(404, 'gone');
      const snapshot = await new WebDavSyncClient(new WebDavTransport(executor, 'u', 'p'))
        .fetchRemoteSnapshot('https://dav.example/file');
      expect(snapshot === null).assertTrue();
    });

    it('matchingFingerprintAllowsRevalidatedUnconditionalPut', 0, async () => {
      const executor = new QueuedWebDavExecutor();
      executor.push(200, 'old-content');
      executor.push(204, '', headers([['etag', '"v2"']]));
      const transport = new WebDavTransport(executor, 'u', 'p');
      const version = new WebDavRemoteVersion();
      version.lastKnownFingerprint = calculateWebDavFingerprint(utf8EncodeText('old-content'));
      const result = await new WebDavSyncClient(transport).uploadBackup(
        'https://dav.example/file', utf8EncodeText('new-content'), 'application/json', version);
      expect(result.version.etag).assertEqual('"v2"');
      expect(executor.calls.length).assertEqual(2);
      expect(executor.calls[0].method).assertEqual('GET');
      expect(executor.calls[1].method).assertEqual('PUT');
      expect(executor.calls[1].headers.has('If-Match')).assertFalse();
      expect(executor.calls[1].headers.has('If-Unmodified-Since')).assertFalse();
    });

    it('changedFingerprintRejectsFallbackAsConflict', 0, async () => {
      const executor = new QueuedWebDavExecutor();
      executor.push(200, 'changed-remotely');
      const version = new WebDavRemoteVersion();
      version.token = new WebDavConcurrencyToken();
      version.lastKnownFingerprint = calculateWebDavFingerprint(utf8EncodeText('old-content'));
      const error = await rejection(new WebDavSyncClient(new WebDavTransport(executor, 'u', 'p'))
        .uploadBackup('https://dav.example/file', utf8EncodeText('new-content'),
          'application/json', version) as Promise<Object>);
      expect(error.kind).assertEqual(WebDavErrorKind.CONTENT_CONFLICT);
      expect(error.statusCode).assertEqual(412);
      expect(executor.calls.length).assertEqual(1);
    });

    it('createOnlyConflictNeverFallsBack', 0, async () => {
      const executor = new QueuedWebDavExecutor();
      executor.push(412, 'exists');
      const version = new WebDavRemoteVersion();
      version.createOnly = true;
      const error = await rejection(new WebDavSyncClient(new WebDavTransport(executor, 'u', 'p'))
        .uploadBackup('https://dav.example/file', utf8EncodeText('data'),
          'application/json', version) as Promise<Object>);
      expect(error.kind).assertEqual(WebDavErrorKind.CONTENT_CONFLICT);
      expect(executor.calls.length).assertEqual(1);
      expect(executor.calls[0].headers.get('If-None-Match')).assertEqual('*');
    });
  });
}
