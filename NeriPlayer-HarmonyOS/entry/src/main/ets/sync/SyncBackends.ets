// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/** Concrete coordinator adapters for the two supported backup transports. */

import {
  SyncBackend,
  CoordinatorRemoteSnapshot,
  CoordinatorRemoteVersion,
  decodeCoordinatorSnapshot
} from './SyncCoordinator';
import { GitHubSyncClient } from './github/GitHubSyncClient';
import { GitHubTransport } from './github/GitHubTransport';
import { GitHubApiError, GitHubErrorKind } from './github/GitHubErrors';
import {
  WebDavConcurrencyToken,
  WebDavSyncClient,
  WebDavRemoteVersion
} from './webdav/WebDavTransport';
import { WebDavError, WebDavErrorKind } from './webdav/WebDavErrors';

export class GitHubSyncBackend implements SyncBackend {
  readonly name: string = 'github';
  private readonly client: GitHubSyncClient;
  private readonly owner: string;
  private readonly repo: string;
  private readonly fileName: string;
  private readonly dataSaver: boolean;

  constructor(transport: GitHubTransport, owner: string, repo: string, fileName: string,
    dataSaver: boolean) {
    this.client = new GitHubSyncClient(transport);
    this.owner = owner;
    this.repo = repo;
    this.fileName = fileName;
    this.dataSaver = dataSaver;
  }

  async fetch(): Promise<CoordinatorRemoteSnapshot | null> {
    const remote = await this.client.fetchRemoteSnapshot(this.owner, this.repo,
      this.fileName, this.dataSaver);
    if (remote === null) {
      return null;
    }
    return decodeCoordinatorSnapshot(remote.content, remote.headSha, remote.headSha,
      remote.sourceFileName !== this.fileName);
  }

  async upload(content: Uint8Array, expectedVersion: string): Promise<CoordinatorRemoteVersion> {
    const sha = await this.client.uploadBackup(this.owner, this.repo, content,
      expectedVersion.length > 0 ? expectedVersion : null, this.fileName);
    return new CoordinatorRemoteVersion(sha, sha);
  }

  isConflict(error: Error): boolean {
    return error instanceof GitHubApiError && error.kind === GitHubErrorKind.CONTENT_CONFLICT;
  }
}

export class WebDavSyncBackend implements SyncBackend {
  readonly name: string = 'webdav';
  private readonly client: WebDavSyncClient;
  private readonly remoteUrl: string;

  constructor(client: WebDavSyncClient, remoteUrl: string) {
    this.client = client;
    this.remoteUrl = remoteUrl;
  }

  async fetch(): Promise<CoordinatorRemoteSnapshot | null> {
    const remote = await this.client.fetchRemoteSnapshot(this.remoteUrl);
    if (remote === null) {
      return null;
    }
    const version = encodeWebDavVersion(remote.fingerprint, remote.version.token);
    return decodeCoordinatorSnapshot(remote.content, version, remote.fingerprint);
  }

  async upload(content: Uint8Array, expectedVersion: string): Promise<CoordinatorRemoteVersion> {
    const version = new WebDavRemoteVersion();
    const parts = expectedVersion.split(';');
    const fingerprint = valueOfPart(parts, 'fingerprint:');
    const etag = valueOfPart(parts, 'etag:');
    const modified = valueOfPart(parts, 'modified:');
    if (etag.length > 0) {
      version.token = new WebDavConcurrencyToken();
      version.token.etag = decodeURIComponent(etag);
    } else if (modified.length > 0) {
      version.token = new WebDavConcurrencyToken();
      version.token.lastModified = decodeURIComponent(modified);
    }
    if (fingerprint.length > 0) {
      version.lastKnownFingerprint = fingerprint;
    } else {
      version.createOnly = true;
    }
    // Binary (data-saver) payloads upload as octet-stream, JSON stays textual
    // — matches Android WebDavSyncManager's media type selection.
    const isGzip = content.length >= 2 && content[0] === 0x1F && content[1] === 0x8B;
    const mediaType = isGzip ? 'application/octet-stream' : 'application/json; charset=utf-8';
    const result = await this.client.uploadBackup(this.remoteUrl, content, mediaType, version);
    return new CoordinatorRemoteVersion(
      encodeWebDavVersion(result.fingerprint, result.version), result.fingerprint);
  }

  isConflict(error: Error): boolean {
    return error instanceof WebDavError && error.kind === WebDavErrorKind.CONTENT_CONFLICT;
  }
}

function encodeWebDavVersion(fingerprint: string, token: WebDavConcurrencyToken | null): string {
  let version = `fingerprint:${fingerprint}`;
  if (token !== null && token.etag !== null && token.etag.length > 0) {
    version += `;etag:${encodeURIComponent(token.etag)}`;
  } else if (token !== null && token.lastModified !== null && token.lastModified.length > 0) {
    version += `;modified:${encodeURIComponent(token.lastModified)}`;
  }
  return version;
}

function valueOfPart(parts: string[], prefix: string): string {
  for (const part of parts) {
    if (part.startsWith(prefix)) {
      return part.substring(prefix.length);
    }
  }
  return '';
}
