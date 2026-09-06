import { describe, it, expect } from '@ohos/hypium';
import {
  GhExecutor,
  GhRequest,
  GhResponse,
  GitHubTransport,
  GhRemoteFile,
  isValidGitHubName,
  MAX_SYNC_FILE_BYTES
} from '../../../main/ets/sync/github/GitHubTransport';
import {
  GitHubSyncClient,
  GitHubRemoteSnapshot,
  remoteFileCandidates
} from '../../../main/ets/sync/github/GitHubSyncClient';
import { GitHubApiError, GitHubErrorKind } from '../../../main/ets/sync/github/GitHubErrors';
import { encodeBase64 } from '../../../main/ets/util/Base64';
import { utf8EncodeText } from '../../../main/ets/sync/SyncDataJsonCodec';

const API = 'https://api.github.com';

class GhRoute {
  method: string = '';
  match: string = '';
  status: number = 200;
  body: string = '';

  constructor(method: string, match: string, status: number, body: string) {
    this.method = method;
    this.match = match;
    this.status = status;
    this.body = body;
  }
}

/**
 * Routes match by method + url substring, scanned LAST-ADDED-FIRST so tests
 * can register broad routes (e.g. GET /repos/o/r) first and specific ones
 * (e.g. /git/commits/head1) later without being shadowed.
 */
class FakeGhExecutor implements GhExecutor {
  calls: GhRequest[] = [];
  routes: GhRoute[] = [];

  addRoute(route: GhRoute): void {
    this.routes.push(route);
  }

  execute(request: GhRequest): Promise<GhResponse> {
    this.calls.push(request);
    for (let i = this.routes.length - 1; i >= 0; i--) {
      const route = this.routes[i];
      if (route.method === request.method && request.url.includes(route.match)) {
        const response = new GhResponse();
        response.status = route.status;
        response.bodyBytes = utf8EncodeText(route.body);
        return Promise.resolve(response);
      }
    }
    return Promise.reject(new Error(`no fake route for ${request.method} ${request.url}`));
  }
}

class OversizeExecutor implements GhExecutor {
  execute(request: GhRequest): Promise<GhResponse> {
    const response = new GhResponse();
    response.status = 200;
    response.bodyBytes = new Uint8Array(MAX_SYNC_FILE_BYTES + 1);
    return Promise.resolve(response);
  }
}

function pipelineExecutor(): FakeGhExecutor {
  const executor = new FakeGhExecutor();
  executor.addRoute(new GhRoute('GET', '/repos/o/r', 200,
    '{"default_branch":"main","private":true}'));
  executor.addRoute(new GhRoute('GET', '/git/ref/heads/main', 200,
    '{"object":{"sha":"head1"}}'));
  executor.addRoute(new GhRoute('GET', '/git/commits/head1', 200,
    '{"tree":{"sha":"tree0"}}'));
  executor.addRoute(new GhRoute('POST', '/git/blobs', 201, '{"sha":"blob1"}'));
  executor.addRoute(new GhRoute('POST', '/git/trees', 201, '{"sha":"tree1"}'));
  executor.addRoute(new GhRoute('POST', '/git/commits', 201, '{"sha":"commit1"}'));
  executor.addRoute(new GhRoute('PATCH', '/git/refs/heads/main', 200,
    '{"object":{"sha":"commit1"}}'));
  return executor;
}

function fetchExecutor(preferredStatus: number, preferredBody: string,
  fallbackStatus: number, fallbackBody: string): FakeGhExecutor {
  const executor = new FakeGhExecutor();
  executor.addRoute(new GhRoute('GET', '/repos/o/r', 200, '{"default_branch":"main"}'));
  executor.addRoute(new GhRoute('GET', '/git/ref/heads/main', 200, '{"object":{"sha":"head9"}}'));
  executor.addRoute(new GhRoute('GET', '/contents/backup-raw.bin', 404, 'gone'));
  executor.addRoute(new GhRoute('GET', '/contents/backup.bin', fallbackStatus, fallbackBody));
  executor.addRoute(new GhRoute('GET', '/contents/backup.json', preferredStatus, preferredBody));
  return executor;
}

function methodUrls(calls: GhRequest[]): string[] {
  return calls.map((call: GhRequest): string => `${call.method} ${call.url}`);
}

async function expectRejection(promise: Promise<Object | null>): Promise<GitHubApiError> {
  try {
    await promise;
  } catch (error) {
    return error as GitHubApiError;
  }
  return new GitHubApiError(GitHubErrorKind.API, -1, 'expected failure but call resolved');
}

export default function githubTransportTest(): void {
  describe('GitHubTransportBase', () => {
    it('encodesBase64Vectors', 0, () => {
      expect(encodeBase64(new Uint8Array(0))).assertEqual('');
      expect(encodeBase64(utf8EncodeText('a'))).assertEqual('YQ==');
      expect(encodeBase64(utf8EncodeText('ab'))).assertEqual('YWI=');
      expect(encodeBase64(utf8EncodeText('abc'))).assertEqual('YWJj');
      expect(encodeBase64(utf8EncodeText('abcdefghijklmnopqrstuvwxyz'))).assertEqual(
        'YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXo=');
    });

    it('validatesOwnerRepoNameWhitelist', 0, () => {
      expect(isValidGitHubName('user-01.name')).assertTrue();
      expect(isValidGitHubName('a.b_c-d')).assertTrue();
      expect(isValidGitHubName('backup.json')).assertTrue();
      expect(isValidGitHubName('')).assertFalse();
      expect(isValidGitHubName('../etc')).assertFalse();
      expect(isValidGitHubName('owner repo')).assertFalse();
      expect(isValidGitHubName('owner/repo')).assertFalse();
      expect(isValidGitHubName('x'.repeat(101))).assertFalse();
    });
  });

  describe('GitHubTransportEndpoints', () => {
    it('validateTokenReturnsLoginWithAuthHeaders', 0, async () => {
      const executor = new FakeGhExecutor();
      executor.addRoute(new GhRoute('GET', '/user', 200, '{"login":"octocat"}'));
      const transport = new GitHubTransport(executor, 'tok');
      const login = await transport.validateToken();
      expect(login).assertEqual('octocat');
      expect(executor.calls[0].headers.get('Authorization')).assertEqual('Bearer tok');
      expect(executor.calls[0].headers.get('X-GitHub-Api-Version')).assertEqual('2022-11-28');
      expect(executor.calls[0].headers.get('Accept')).assertEqual('application/vnd.github+json');
    });

    it('anonymousTransportOmitsAuthorizationAnd401Classifies', 0, async () => {
      const executor = new FakeGhExecutor();
      executor.addRoute(new GhRoute('GET', '/user', 401,
        '{"message":"Requires authentication"}'));
      const transport = new GitHubTransport(executor, '  ');
      const error = await expectRejection(transport.validateToken());
      expect(error.kind).assertEqual(GitHubErrorKind.TOKEN_EXPIRED);
      expect(executor.calls[0].headers.has('Authorization')).assertFalse();
    });

    it('getRepoInfoParsesDefaultBranchAndPrivacy', 0, async () => {
      const executor = new FakeGhExecutor();
      executor.addRoute(new GhRoute('GET', '/repos/o/r', 200,
        '{"name":"r","full_name":"o/r","default_branch":"master","private":false}'));
      const transport = new GitHubTransport(executor, 'tok');
      const info = await transport.getRepoInfo('o', 'r');
      expect(info.defaultBranch).assertEqual('master');
      expect(info.isPrivate).assertFalse();
      expect(info.fullName).assertEqual('o/r');
    });

    it('getRepoInfoDefaultsBlankBranchToMainAndPrivateWhenMissing', 0, async () => {
      const executor = new FakeGhExecutor();
      executor.addRoute(new GhRoute('GET', '/repos/o/r2', 200, '{"default_branch":""}'));
      const transport = new GitHubTransport(executor, 'tok');
      const info = await transport.getRepoInfo('o', 'r2');
      expect(info.defaultBranch).assertEqual('main');
      expect(info.isPrivate).assertTrue();
    });

    it('getBranchHeadReadsObjectSha', 0, async () => {
      const executor = new FakeGhExecutor();
      executor.addRoute(new GhRoute('GET', '/git/ref/heads/main', 200,
        '{"ref":"refs/heads/main","object":{"sha":"head1","type":"commit"}}'));
      const transport = new GitHubTransport(executor, 'tok');
      expect(await transport.getBranchHead('o', 'r', 'main')).assertEqual('head1');
    });

    it('getFileContentReturnsNullOn404', 0, async () => {
      const executor = new FakeGhExecutor();
      executor.addRoute(new GhRoute('GET', '/contents/backup.json', 404, 'not found'));
      const transport = new GitHubTransport(executor, 'tok');
      const file = await transport.getFileContent('o', 'r', 'backup.json', 'head1');
      expect(file === null).assertTrue();
      expect(executor.calls[0].headers.get('Accept')).assertEqual('application/vnd.github.raw');
      expect(executor.calls[0].url.includes('?ref=head1')).assertTrue();
    });

    it('getFileContentRejectsOversizePayload', 0, async () => {
      const transport = new GitHubTransport(new OversizeExecutor(), 'tok');
      const error = await expectRejection(
        transport.getFileContent('o', 'r', 'backup.json', 'head1'));
      expect(error.kind).assertEqual(GitHubErrorKind.API);
      expect(error.message.includes('exceeds')).assertTrue();
    });

    it('rejectsInvalidOwnerNames', 0, async () => {
      const transport = new GitHubTransport(new FakeGhExecutor(), 'tok');
      const error = await expectRejection(transport.getRepoInfo('bad/name', 'r'));
      expect(error.kind).assertEqual(GitHubErrorKind.API);
    });
  });

  describe('GitHubTransportUploadPipeline', () => {
    it('runsRepoRefTreeBlobTreeCommitPatchRefSequence', 0, async () => {
      const executor = pipelineExecutor();
      const transport = new GitHubTransport(executor, 'tok');
      const commitSha = await transport.updateFileContent('o', 'r',
        utf8EncodeText('{"version":"2.0"}'), null, 'backup.json', 'Update backup data', null);
      expect(commitSha).assertEqual('commit1');
      const sequence = methodUrls(executor.calls);
      expect(sequence.length).assertEqual(7);
      expect(sequence[0]).assertEqual(`GET ${API}/repos/o/r`);
      expect(sequence[1]).assertEqual(`GET ${API}/repos/o/r/git/ref/heads/main`);
      expect(sequence[2]).assertEqual(`GET ${API}/repos/o/r/git/commits/head1`);
      expect(sequence[3]).assertEqual(`POST ${API}/repos/o/r/git/blobs`);
      expect(sequence[4]).assertEqual(`POST ${API}/repos/o/r/git/trees`);
      expect(sequence[5]).assertEqual(`POST ${API}/repos/o/r/git/commits`);
      expect(sequence[6]).assertEqual(`PATCH ${API}/repos/o/r/git/refs/heads/main`);
    });

    it('wrapsPayloadInBase64BlobEnvelope', 0, async () => {
      const executor = pipelineExecutor();
      const transport = new GitHubTransport(executor, 'tok');
      const payload = utf8EncodeText('{"deviceId":"dev"}');
      await transport.updateFileContent('o', 'r', payload, null, 'backup.json',
        'Update backup data', null);
      const blobBody = executor.calls[3].bodyText ?? '';
      expect(blobBody).assertEqual(`{"content":"${encodeBase64(payload)}","encoding":"base64"}`);
      const treeBody = executor.calls[4].bodyText ?? '';
      expect(treeBody.includes('"base_tree":"tree0"')).assertTrue();
      expect(treeBody.includes('"path":"backup.json"')).assertTrue();
      expect(treeBody.includes('"mode":"100644"')).assertTrue();
      expect(treeBody.includes('"type":"blob"')).assertTrue();
      expect(treeBody.includes('"sha":"blob1"')).assertTrue();
      const commitBody = executor.calls[5].bodyText ?? '';
      expect(commitBody.includes('"message":"Update backup data"')).assertTrue();
      expect(commitBody.includes('"tree":"tree1"')).assertTrue();
      expect(commitBody.includes('"parents":["head1"]')).assertTrue();
      const refBody = executor.calls[6].bodyText ?? '';
      expect(refBody).assertEqual('{"sha":"commit1","force":false}');
    });

    it('skipsBranchAndHeadLookupsWhenBaselinesProvided', 0, async () => {
      const executor = new FakeGhExecutor();
      executor.addRoute(new GhRoute('POST', '/git/blobs', 201, '{"sha":"blobX"}'));
      executor.addRoute(new GhRoute('POST', '/git/trees', 201, '{"sha":"treeX2"}'));
      executor.addRoute(new GhRoute('POST', '/git/commits', 201, '{"sha":"commitX"}'));
      executor.addRoute(new GhRoute('PATCH', '/git/refs/heads/dev', 200, '{"object":{"sha":"commitX"}}'));
      executor.addRoute(new GhRoute('GET', '/git/commits/headX', 200, '{"tree":{"sha":"treeX"}}'));
      const transport = new GitHubTransport(executor, 'tok');
      const commitSha = await transport.updateFileContent('o', 'r', utf8EncodeText('x'),
        'headX', 'backup.json', 'msg', 'dev');
      expect(commitSha).assertEqual('commitX');
      const sequence = methodUrls(executor.calls);
      expect(sequence.length).assertEqual(5);
      expect(sequence[0]).assertEqual(`GET ${API}/repos/o/r/git/commits/headX`);
      expect(sequence[1]).assertEqual(`POST ${API}/repos/o/r/git/blobs`);
      const hasRepoInfo = sequence.some((entry: string): boolean =>
        entry === `GET ${API}/repos/o/r`);
      const hasRefHeads = sequence.some((entry: string): boolean =>
        entry.includes('/git/ref/heads/'));
      expect(hasRepoInfo).assertFalse();
      expect(hasRefHeads).assertFalse();
      const commitBody = executor.calls[3].bodyText ?? '';
      expect(commitBody.includes('"parents":["headX"]')).assertTrue();
      const refBody = executor.calls[4].bodyText ?? '';
      expect(refBody.includes('"force":false')).assertTrue();
    });

    it('rejectsEmptyPayload', 0, async () => {
      const transport = new GitHubTransport(new FakeGhExecutor(), 'tok');
      const error = await expectRejection(
        transport.updateFileContent('o', 'r', new Uint8Array(0), null, 'backup.json', 'msg', null));
      expect(error.message.includes('empty payload')).assertTrue();
    });

    it('patch409SurfacesAsContentConflict', 0, async () => {
      const executor = pipelineExecutor();
      executor.addRoute(new GhRoute('PATCH', '/git/refs/heads/main', 409,
        '{"message":"Update is not a fast forward"}'));
      const transport = new GitHubTransport(executor, 'tok');
      const error = await expectRejection(
        transport.updateFileContent('o', 'r', utf8EncodeText('x'), null, 'backup.json', 'msg', null));
      expect(error.kind).assertEqual(GitHubErrorKind.CONTENT_CONFLICT);
      expect(error.statusCode).assertEqual(409);
    });

    it('patch422WithReferenceBodySurfacesAsContentConflict', 0, async () => {
      const executor = pipelineExecutor();
      executor.addRoute(new GhRoute('PATCH', '/git/refs/heads/main', 422,
        '{"message":" Reference does not exist"}'));
      const transport = new GitHubTransport(executor, 'tok');
      const error = await expectRejection(
        transport.updateFileContent('o', 'r', utf8EncodeText('x'), null, 'backup.json', 'msg', null));
      expect(error.kind).assertEqual(GitHubErrorKind.CONTENT_CONFLICT);
      expect(error.statusCode).assertEqual(422);
    });
  });

  describe('GitHubRemoteSnapshotFetch', () => {
    it('ordersFileCandidatesWithoutDuplicates', 0, () => {
      const jsonFirst = remoteFileCandidates('backup.json', false);
      expect(jsonFirst.length).assertEqual(3);
      expect(jsonFirst[0]).assertEqual('backup.json');
      expect(jsonFirst[1]).assertEqual('backup-raw.bin');
      expect(jsonFirst[2]).assertEqual('backup.bin');
      const rawFirst = remoteFileCandidates('backup-raw.bin', true);
      expect(rawFirst.length).assertEqual(3);
      expect(rawFirst[0]).assertEqual('backup-raw.bin');
      expect(rawFirst[1]).assertEqual('backup.bin');
      expect(rawFirst[2]).assertEqual('backup.json');
    });

    it('fallsBackToLegacyFileWhenPreferredMissing', 0, async () => {
      const executor = fetchExecutor(404, 'gone', 200, 'legacy-bytes');
      const client = new GitHubSyncClient(new GitHubTransport(executor, 'tok'));
      const snapshot = await client.fetchRemoteSnapshot('o', 'r', 'backup.json', false);
      expect(snapshot === null).assertFalse();
      if (snapshot !== null) {
        expect(snapshot.sourceFileName).assertEqual('backup.bin');
        expect(snapshot.headSha).assertEqual('head9');
        expect(snapshot.content.length > 0).assertTrue();
      }
    });

    it('returnsNullWhenAllCandidatesMissing', 0, async () => {
      const executor = fetchExecutor(404, 'gone', 404, 'gone');
      const client = new GitHubSyncClient(new GitHubTransport(executor, 'tok'));
      const snapshot = await client.fetchRemoteSnapshot('o', 'r', 'backup.json', false);
      expect(snapshot === null).assertTrue();
    });

    it('rejectsEmptyRemoteFile', 0, async () => {
      const executor = fetchExecutor(200, '', 200, 'unused');
      const client = new GitHubSyncClient(new GitHubTransport(executor, 'tok'));
      const error = await expectRejection(
        client.fetchRemoteSnapshot('o', 'r', 'backup.json', false) as Promise<Object>);
      expect(error.kind === GitHubErrorKind.API || error.message.includes('为空')).assertTrue();
    });

    it('abortsOnNon404FailureWithoutFallback', 0, async () => {
      const executor = new FakeGhExecutor();
      executor.addRoute(new GhRoute('GET', '/repos/o/r', 200, '{"default_branch":"main"}'));
      executor.addRoute(new GhRoute('GET', '/contents/backup.json', 500, 'server error'));
      executor.addRoute(new GhRoute('GET', '/contents/backup.bin', 200, 'should-not-be-read'));
      executor.addRoute(new GhRoute('GET', '/git/ref/heads/main', 200, '{"object":{"sha":"head9"}}'));
      const client = new GitHubSyncClient(new GitHubTransport(executor, 'tok'));
      const error = await expectRejection(
        client.fetchRemoteSnapshot('o', 'r', 'backup.json', false) as Promise<Object>);
      expect(error.statusCode).assertEqual(500);
      const readFiles = executor.calls.filter((call: GhRequest): boolean =>
        call.url.includes('/contents/'));
      expect(readFiles.length).assertEqual(1);
    });

    it('uploadBackupUsesDefaultMessageAndFileName', 0, async () => {
      const executor = new FakeGhExecutor();
      executor.addRoute(new GhRoute('GET', '/repos/o/r', 200, '{"default_branch":"main"}'));
      executor.addRoute(new GhRoute('GET', '/git/commits/head1', 200, '{"tree":{"sha":"tree0"}}'));
      executor.addRoute(new GhRoute('POST', '/git/blobs', 201, '{"sha":"blob1"}'));
      executor.addRoute(new GhRoute('POST', '/git/trees', 201, '{"sha":"tree1"}'));
      executor.addRoute(new GhRoute('POST', '/git/commits', 201, '{"sha":"commit1"}'));
      executor.addRoute(new GhRoute('PATCH', '/git/refs/heads/main', 200, '{"object":{"sha":"commit1"}}'));
      const client = new GitHubSyncClient(new GitHubTransport(executor, 'tok'));
      const sha = await client.uploadBackup('o', 'r', utf8EncodeText('data'), 'head1', 'backup.json');
      expect(sha).assertEqual('commit1');
      const commitBody = executor.calls[4].bodyText ?? '';
      expect(commitBody.includes('"message":"Update backup data"')).assertTrue();
      const treeBody = executor.calls[3].bodyText ?? '';
      expect(treeBody.includes('"path":"backup.json"')).assertTrue();
      const refBody = executor.calls[5].bodyText ?? '';
      expect(refBody.includes('"force":false')).assertTrue();
    });
  });
}
