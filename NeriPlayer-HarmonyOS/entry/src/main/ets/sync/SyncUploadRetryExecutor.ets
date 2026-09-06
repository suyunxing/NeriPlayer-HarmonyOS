/** Optimistic-lock upload retry loop shared by GitHub and WebDAV. */

export class UploadRefetchResult<TRemote, TVersion> {
  remote: TRemote;
  version: TVersion;

  constructor(remote: TRemote, version: TVersion) {
    this.remote = remote;
    this.version = version;
  }
}

export class UploadResolution<TMerged, TVersion> {
  merged: TMerged;
  remoteVersion: TVersion;
  uploadPerformed: boolean;
  remoteChangedDuringSync: boolean;

  constructor(merged: TMerged, remoteVersion: TVersion, uploadPerformed: boolean,
    remoteChangedDuringSync: boolean) {
    this.merged = merged;
    this.remoteVersion = remoteVersion;
    this.uploadPerformed = uploadPerformed;
    this.remoteChangedDuringSync = remoteChangedDuringSync;
  }
}

export interface UploadRetryCallbacks<TRemote, TMerged, TVersion> {
  merge(remote: TRemote): TMerged;
  hasMeaningfulChange(remote: TRemote, merged: TMerged): boolean;
  upload(merged: TMerged, version: TVersion): Promise<TVersion>;
  refetch(version: TVersion): Promise<UploadRefetchResult<TRemote, TVersion>>;
  isConflict(error: Error): boolean;
}

export async function executeUploadWithRetry<TRemote, TMerged, TVersion>(
  initialRemote: TRemote,
  initialVersion: TVersion,
  initialRemoteChangedDuringSync: boolean,
  callbacks: UploadRetryCallbacks<TRemote, TMerged, TVersion>,
  maxConflictRetries: number = 3
): Promise<UploadResolution<TMerged, TVersion>> {
  let remote = initialRemote;
  let version = initialVersion;
  let remoteChangedDuringSync = initialRemoteChangedDuringSync;

  for (let attempt = 0; attempt <= maxConflictRetries; attempt++) {
    const merged = callbacks.merge(remote);
    if (!callbacks.hasMeaningfulChange(remote, merged)) {
      return new UploadResolution(merged, version, false, remoteChangedDuringSync);
    }
    try {
      const nextVersion = await callbacks.upload(merged, version);
      return new UploadResolution(merged, nextVersion, true, remoteChangedDuringSync);
    } catch (error) {
      const e = error instanceof Error ? error : new Error('Sync upload failed');
      if (!callbacks.isConflict(e) || attempt >= maxConflictRetries) {
        throw e;
      }
      const fresh = await callbacks.refetch(version);
      remote = fresh.remote;
      version = fresh.version;
      remoteChangedDuringSync = true;
    }
  }
  throw new Error('Sync upload retry budget exhausted');
}
