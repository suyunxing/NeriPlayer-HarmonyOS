/**
 * GitHub REST transport for the backup-sync pipeline (pure ArkTS: the HTTP
 * executor is injected so local hypium tests drive the full request flow).
 *
 * Mirrors Android GitHubRepositorySyncTransport / GitHubApiClient semantics:
 * - reads go through the Contents API with Accept: application/vnd.github.raw
 *   (404 -> "file absent" instead of a failure), capped at 12 MiB;
 * - uploads use the Git Data API pipeline blob -> tree -> commit -> PATCH
 *   branch ref {"sha":..., "force": false}, the optimistic-lock point exactly
 *   like Android updateBranchRef. @ohos.net.http RequestMethod has no PATCH
 *   enum value, but the official customMethod option (@since 23, present in
 *   the API 24 SDK d.ts line 576; netstack maps it to CURLOPT_CUSTOMREQUEST)
 *   sends a real PATCH request line - see OhosGhExecutor.
 * - 401 -> TOKEN_EXPIRED, 409 / 422+"reference" -> CONTENT_CONFLICT, plus the
 *   RATE_LIMITED class added by this port (see GitHubErrors).
 */

import { escapeJsonString, parseJsonText, utf8Decode, JsonValue } from '../SyncDataJsonCodec';
import { encodeBase64 } from '../../util/Base64';
import {
  GhClassifyOptions,
  GitHubApiError,
  GitHubErrorKind,
  classifyGitHubFailure
} from './GitHubErrors';

export const GITHUB_API_BASE: string = 'https://api.github.com';
export const GITHUB_API_VERSION: string = '2022-11-28';
export const GITHUB_JSON_ACCEPT: string = 'application/vnd.github+json';
export const GITHUB_RAW_ACCEPT: string = 'application/vnd.github.raw';
export const JSON_CONTENT_TYPE: string = 'application/json; charset=utf-8';
export const MAX_SYNC_FILE_BYTES: number = 12 * 1024 * 1024;
/** Android sends no User-Agent; GitHub requires one, so this port always does. */
export const GITHUB_USER_AGENT: string = 'NeriPlayer-HarmonyOS-sync';
export const DEFAULT_COMMIT_MESSAGE: string = 'Update backup data';

export class GhRequest {
  method: string = 'GET';
  url: string = '';
  headers: Map<string, string> = new Map<string, string>();
  bodyText: string | null = null;
}

export class GhResponse {
  status: number = 0;
  headers: Map<string, string> = new Map<string, string>();
  bodyBytes: Uint8Array = new Uint8Array(0);

  bodyText(): string {
    return utf8Decode(this.bodyBytes);
  }
}

export interface GhExecutor {
  execute(request: GhRequest): Promise<GhResponse>;
}

export class GitHubRepoInfo {
  name: string = '';
  fullName: string = '';
  defaultBranch: string = 'main';
  isPrivate: boolean = true;
}

export class GhRemoteFile {
  content: Uint8Array = new Uint8Array(0);
  headSha: string = '';
}

/** [A-Za-z0-9._-] whitelist for owner/repo/branch/path segments interpolated into URLs. */
export function isValidGitHubName(name: string): boolean {
  if (name.length === 0 || name.length > 100) {
    return false;
  }
  for (let i = 0; i < name.length; i++) {
    const c = name.charAt(i);
    const ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
      c === '-' || c === '_' || c === '.';
    if (!ok) {
      return false;
    }
  }
  return true;
}

export class GitHubTransport {
  private readonly executor: GhExecutor;
  private readonly token: string;
  private readonly apiBase: string;

  constructor(executor: GhExecutor, token: string, apiBase: string = GITHUB_API_BASE) {
    this.executor = executor;
    this.token = token.trim();
    this.apiBase = apiBase;
  }

  // ---- Account / repository endpoints (GitHubApiClient) -------------------

  /** GET /user -> login; 401 classifies as TOKEN_EXPIRED. */
  async validateToken(): Promise<string> {
    const parsed = await this.requestJson('validateToken', 'GET', '/user', GITHUB_JSON_ACCEPT, null,
      new GhClassifyOptions());
    return jsonFieldString(parsed, 'login');
  }

  /** GET /repos/{owner}/{repo}; default_branch falls back to "main" like Android ifBlank. */
  async getRepoInfo(owner: string, repo: string): Promise<GitHubRepoInfo> {
    this.assertRepoArgs(owner, repo);
    const parsed = await this.requestJson('getRepoInfo', 'GET', `/repos/${owner}/${repo}`,
      GITHUB_JSON_ACCEPT, null, repoOptions());
    const info = new GitHubRepoInfo();
    info.name = jsonFieldString(parsed, 'name');
    info.fullName = jsonFieldString(parsed, 'full_name');
    const branch = jsonFieldString(parsed, 'default_branch');
    info.defaultBranch = branch.length > 0 ? branch : 'main';
    const privateValue = jsonFieldObject(parsed, 'private');
    info.isPrivate = privateValue !== false;
    return info;
  }

  /** POST /user/repos - creates a private backup repo with an initial commit (auto_init). */
  async createRepository(repoName: string): Promise<GitHubRepoInfo> {
    if (!isValidGitHubName(repoName)) {
      throw new GitHubApiError(GitHubErrorKind.API, 0, `invalid repository name: ${repoName}`);
    }
    // escapeJsonString returns the complete quoted literal ("...").
    const body = `{"name":${escapeJsonString(repoName)},` +
      `"description":"NeriPlayer backup data","private":true,"auto_init":true}`;
    const parsed = await this.requestJson('createRepository', 'POST', '/user/repos',
      GITHUB_JSON_ACCEPT, body, new GhClassifyOptions());
    const info = new GitHubRepoInfo();
    info.name = jsonFieldString(parsed, 'name');
    info.fullName = jsonFieldString(parsed, 'full_name');
    const branch = jsonFieldString(parsed, 'default_branch');
    info.defaultBranch = branch.length > 0 ? branch : 'main';
    info.isPrivate = true;
    return info;
  }

  // ---- Read pipeline -------------------------------------------------------

  async getDefaultBranch(owner: string, repo: string): Promise<string> {
    const info = await this.getRepoInfo(owner, repo);
    return info.defaultBranch;
  }

  /** GET /git/ref/heads/{branch} -> commit sha at the branch head. */
  async getBranchHead(owner: string, repo: string, branch: string): Promise<string> {
    this.assertRepoArgs(owner, repo);
    if (!isValidGitHubName(branch)) {
      throw new GitHubApiError(GitHubErrorKind.API, 0, `invalid branch name: ${branch}`);
    }
    const parsed = await this.requestJson('getBranchHead', 'GET',
      `/repos/${owner}/${repo}/git/ref/heads/${branch}`, GITHUB_JSON_ACCEPT, null, repoOptions());
    const objectValue = jsonFieldObject(parsed, 'object');
    return objectValue === null ? '' : jsonFieldString(objectValue, 'sha');
  }

  /**
   * GET /contents/{path}?ref={ref} with the raw media type. Returns null when
   * the file does not exist at the ref (Android maps this 404 the same way);
   * rejects payloads above MAX_SYNC_FILE_BYTES regardless of declared length.
   */
  async getFileContent(owner: string, repo: string, path: string, ref: string): Promise<GhRemoteFile | null> {
    this.assertRepoArgs(owner, repo);
    if (!isValidGitHubName(path)) {
      throw new GitHubApiError(GitHubErrorKind.API, 0, `invalid file name: ${path}`);
    }
    const refQuery = ref.length > 0 ? `?ref=${encodeURIComponent(ref)}` : '';
    let response: GhResponse;
    try {
      response = await this.request('getFileContent', 'GET',
        `/repos/${owner}/${repo}/contents/${path}${refQuery}`, GITHUB_RAW_ACCEPT, null,
        fileOptions());
    } catch (error) {
      const e = error as Error;
      if (e instanceof GitHubApiError && e.kind === GitHubErrorKind.FILE_NOT_FOUND) {
        return null;
      }
      throw e;
    }
    const file = new GhRemoteFile();
    file.headSha = ref;
    file.content = response.bodyBytes;
    if (file.content.length > MAX_SYNC_FILE_BYTES) {
      throw new GitHubApiError(GitHubErrorKind.API, response.status,
        `getFileContent failed: remote file exceeds ${MAX_SYNC_FILE_BYTES} bytes`);
    }
    return file;
  }

  // ---- Upload pipeline (Android commitSyncFile) ----------------------------

  /**
   * Commits `content` at `path` and advances the branch head. `remoteHead` is
   * the last known head sha (optimistic-lock baseline); when blank the current
   * head is fetched first, exactly like Android updateFileContent.
   * Returns the new commit sha.
   */
  async updateFileContent(owner: string, repo: string, content: Uint8Array, remoteHead: string | null,
    path: string, message: string, branch: string | null): Promise<string> {
    this.assertRepoArgs(owner, repo);
    if (!isValidGitHubName(path)) {
      throw new GitHubApiError(GitHubErrorKind.API, 0, `invalid file name: ${path}`);
    }
    if (content.length === 0) {
      throw new GitHubApiError(GitHubErrorKind.API, 0, 'updateFileContent failed: empty payload');
    }
    if (content.length > MAX_SYNC_FILE_BYTES) {
      throw new GitHubApiError(GitHubErrorKind.API, 0,
        `updateFileContent failed: payload exceeds ${MAX_SYNC_FILE_BYTES} bytes`);
    }
    const targetBranch = branch !== null && branch.trim().length > 0 ?
      branch.trim() : await this.getDefaultBranch(owner, repo);
    const baseline = remoteHead !== null && remoteHead.trim().length > 0 ?
      remoteHead.trim() : await this.getBranchHead(owner, repo, targetBranch);
    const baseTreeSha = baseline.length > 0 ? await this.getCommitTreeSha(owner, repo, baseline) : '';
    const blobSha = await this.createBinaryBlob(owner, repo, content);
    const treeSha = await this.createSyncFileTree(owner, repo, baseTreeSha, path, blobSha);
    const parents: string[] = baseline.length > 0 ? [baseline] : [];
    const commitSha = await this.createSyncFileCommit(owner, repo, message, treeSha, parents);
    await this.updateBranchRef(owner, repo, targetBranch, commitSha);
    return commitSha;
  }

  /** GET /git/commits/{sha} -> its tree sha. */
  async getCommitTreeSha(owner: string, repo: string, commitSha: string): Promise<string> {
    this.assertRepoArgs(owner, repo);
    const parsed = await this.requestJson('getCommitTreeSha', 'GET',
      `/repos/${owner}/${repo}/git/commits/${commitSha}`, GITHUB_JSON_ACCEPT, null,
      new GhClassifyOptions());
    const tree = jsonFieldObject(parsed, 'tree');
    return tree === null ? '' : jsonFieldString(tree, 'sha');
  }

  /** POST /git/blobs - raw bytes stored server-side via the base64 envelope. */
  async createBinaryBlob(owner: string, repo: string, content: Uint8Array): Promise<string> {
    this.assertRepoArgs(owner, repo);
    const body = `{"content":"${encodeBase64(content)}","encoding":"base64"}`;
    const parsed = await this.requestJson('createBinaryBlob', 'POST',
      `/repos/${owner}/${repo}/git/blobs`, GITHUB_JSON_ACCEPT, body, new GhClassifyOptions());
    return jsonFieldString(parsed, 'sha');
  }

  /** POST /git/trees - single-file tree on top of baseTreeSha (mode always 100644). */
  async createSyncFileTree(owner: string, repo: string, baseTreeSha: string, path: string,
    blobSha: string): Promise<string> {
    this.assertRepoArgs(owner, repo);
    const baseEntry = baseTreeSha.length > 0 ? `"base_tree":"${baseTreeSha}",` : '';
    const body = `{${baseEntry}"tree":[{"path":${escapeJsonString(path)},` +
      `"mode":"100644","type":"blob","sha":"${blobSha}"}]}`;
    const parsed = await this.requestJson('createSyncFileTree', 'POST',
      `/repos/${owner}/${repo}/git/trees`, GITHUB_JSON_ACCEPT, body, new GhClassifyOptions());
    return jsonFieldString(parsed, 'sha');
  }

  /** POST /git/commits - parents empty for the very first upload. */
  async createSyncFileCommit(owner: string, repo: string, message: string, treeSha: string,
    parents: string[]): Promise<string> {
    this.assertRepoArgs(owner, repo);
    const quoted = parents.map((parent: string): string => `"${parent}"`);
    const body = `{"message":${escapeJsonString(message)},"tree":"${treeSha}",` +
      `"parents":[${quoted.join(',')}]}`;
    const parsed = await this.requestJson('createSyncFileCommit', 'POST',
      `/repos/${owner}/${repo}/git/commits`, GITHUB_JSON_ACCEPT, body, new GhClassifyOptions());
    return jsonFieldString(parsed, 'sha');
  }

  /**
   * PATCH /git/refs/heads/{branch} {"sha":..., "force": false} - the Android
   * updateBranchRef optimistic-lock step. The branch update fails with
   * 409 / 422+"Reference ..." when the head moved since our baseline commit,
   * classifying as CONTENT_CONFLICT. The PATCH request line itself is sent
   * through the official customMethod option (see file header).
   */
  async updateBranchRef(owner: string, repo: string, branch: string, commitSha: string): Promise<void> {
    this.assertRepoArgs(owner, repo);
    if (!isValidGitHubName(branch)) {
      throw new GitHubApiError(GitHubErrorKind.API, 0, `invalid branch name: ${branch}`);
    }
    const body = `{"sha":"${commitSha}","force":false}`;
    await this.request('updateBranchRef', 'PATCH',
      `/repos/${owner}/${repo}/git/refs/heads/${branch}`, GITHUB_JSON_ACCEPT, body,
      conflictOptions());
  }

  // ---- Internals ------------------------------------------------------------

  private async request(operation: string, method: string, path: string, accept: string,
    bodyText: string | null, classify: GhClassifyOptions): Promise<GhResponse> {
    const request = new GhRequest();
    request.method = method;
    request.url = `${this.apiBase}${path}`;
    request.headers = this.buildHeaders(accept, bodyText !== null);
    request.bodyText = bodyText;
    let response: GhResponse;
    try {
      response = await this.executor.execute(request);
    } catch (error) {
      const e = error as Error;
      throw new GitHubApiError(GitHubErrorKind.NETWORK, 0, `${operation} network error: ${e.message}`);
    }
    if (response.status < 200 || response.status >= 300) {
      throw classifyGitHubFailure(operation, response.status, response.bodyText(), response.headers, classify);
    }
    return response;
  }

  private async requestJson(operation: string, method: string, path: string, accept: string,
    bodyText: string | null, classify: GhClassifyOptions): Promise<JsonValue> {
    const response = await this.request(operation, method, path, accept, bodyText, classify);
    const parsed = parseJsonText(response.bodyText());
    if (parsed === null || !(parsed instanceof Map)) {
      throw new GitHubApiError(GitHubErrorKind.API, response.status,
        `${operation} failed: response is not a JSON object`);
    }
    return parsed;
  }

  private buildHeaders(accept: string, hasBody: boolean): Map<string, string> {
    const headers = new Map<string, string>();
    if (this.token.length > 0) {
      headers.set('Authorization', `Bearer ${this.token}`);
    }
    headers.set('Accept', accept);
    headers.set('X-GitHub-Api-Version', GITHUB_API_VERSION);
    headers.set('User-Agent', GITHUB_USER_AGENT);
    if (hasBody) {
      headers.set('Content-Type', JSON_CONTENT_TYPE);
    }
    return headers;
  }

  private assertRepoArgs(owner: string, repo: string): void {
    if (!isValidGitHubName(owner) || !isValidGitHubName(repo)) {
      throw new GitHubApiError(GitHubErrorKind.API, 0, `invalid owner/repo: ${owner}/${repo}`);
    }
  }
}

function repoOptions(): GhClassifyOptions {
  const options = new GhClassifyOptions();
  options.notFoundKind = GitHubErrorKind.REPO_NOT_FOUND;
  return options;
}

function fileOptions(): GhClassifyOptions {
  const options = new GhClassifyOptions();
  options.notFoundKind = GitHubErrorKind.FILE_NOT_FOUND;
  return options;
}

function conflictOptions(): GhClassifyOptions {
  const options = new GhClassifyOptions();
  options.detectConflict = true;
  return options;
}

function jsonFieldString(root: JsonValue, key: string): string {
  if (!(root instanceof Map)) {
    return '';
  }
  const value = root.get(key);
  return typeof value === 'string' ? value : '';
}

function jsonFieldObject(root: JsonValue, key: string): JsonValue | null {
  if (!(root instanceof Map)) {
    return null;
  }
  const value = root.get(key);
  return value === undefined ? null : value;
}
