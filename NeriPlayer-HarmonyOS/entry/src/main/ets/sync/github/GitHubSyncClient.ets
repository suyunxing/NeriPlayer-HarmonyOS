/**
 * Sync-semantics layer over GitHubTransport: the remote-snapshot fetch with
 * cross-format fallback file names (Android GitHubSyncManager
 * fetchRemoteSnapshot) and the backup upload entry (message/branch defaults
 * of GitHubApiClient.updateFileContent).
 */

import {
  getReadFallbackFileNames
} from '../SyncDataJsonCodec';
import { DEFAULT_COMMIT_MESSAGE, GitHubTransport } from './GitHubTransport';
import { GitHubApiError, GitHubErrorKind } from './GitHubErrors';

export class GitHubRemoteSnapshot {
  content: Uint8Array = new Uint8Array(0);
  /** Head sha of the default branch at fetch time (upload optimistic-lock baseline). */
  headSha: string = '';
  /** File the content actually came from; differs from the preferred name
   * when only a legacy-format backup exists (drives migration upload in M5.5). */
  sourceFileName: string = '';
}

/** Ordered unique file-name candidates for the preferred format first. */
export function remoteFileCandidates(preferredFileName: string, useDataSaver: boolean): string[] {
  const names: string[] = [preferredFileName];
  for (const fallback of getReadFallbackFileNames(useDataSaver)) {
    if (names.indexOf(fallback) < 0) {
      names.push(fallback);
    }
  }
  return names;
}

export class GitHubSyncClient {
  private readonly transport: GitHubTransport;

  constructor(transport: GitHubTransport) {
    this.transport = transport;
  }

  /**
   * Reads the remote backup from the default branch.
   * - File absent everywhere (pure 404s) -> null (first-sync marker).
   * - File exists but empty -> API failure: an empty payload must never act
   *   as the merge base (Android github_backup_file_invalid).
   * - Any non-404 failure aborts immediately - never fall back to a stale
   *   snapshot from another file name after a real error (Android P1-4).
   */
  async fetchRemoteSnapshot(owner: string, repo: string, preferredFileName: string,
    useDataSaver: boolean): Promise<GitHubRemoteSnapshot | null> {
    const branch = await this.transport.getDefaultBranch(owner, repo);
    const head = await this.transport.getBranchHead(owner, repo, branch);
    for (const fileName of remoteFileCandidates(preferredFileName, useDataSaver)) {
      const file = await this.transport.getFileContent(owner, repo, fileName, head);
      if (file === null) {
        continue;
      }
      if (file.content.length === 0) {
        throw new GitHubApiError(GitHubErrorKind.API, 0,
          `远端备份文件 ${fileName} 为空（github_backup_file_invalid）`);
      }
      const snapshot = new GitHubRemoteSnapshot();
      snapshot.content = file.content;
      snapshot.headSha = head;
      snapshot.sourceFileName = fileName;
      return snapshot;
    }
    return null;
  }

  /**
   * Uploads serialized backup bytes at fileName. expectedSha is the remote
   * head sha the upload is based on (null = fetch it server-side first).
   * Returns the new commit sha.
   */
  async uploadBackup(owner: string, repo: string, content: Uint8Array, expectedSha: string | null,
    fileName: string): Promise<string> {
    return this.transport.updateFileContent(owner, repo, content, expectedSha, fileName,
      DEFAULT_COMMIT_MESSAGE, null);
  }
}
