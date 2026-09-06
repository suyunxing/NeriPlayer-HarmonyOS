/** Coordinates snapshot, three-way merge, optimistic upload and local apply. */

import { SyncData } from './SyncModels';
import { deserializeSyncContent, serializeSyncDataJson } from './SyncDataJsonCodec';
import { hasDataChanged } from './DataChangeDetector';
import { buildInitialSyncMerge, performThreeWayMerge, SyncMergeResult } from './SyncMergeEngine';
import { executeUploadWithRetry, UploadRefetchResult, UploadRetryCallbacks } from './SyncUploadRetryExecutor';
import { SyncReport } from './SyncReport';

export class CoordinatorRemoteSnapshot {
  content: Uint8Array;
  version: string;
  marker: string;
  requiresUpload: boolean;
  data: SyncData | null;

  constructor(content: Uint8Array = new Uint8Array(0), version: string = '',
    data: SyncData | null = null, marker: string = version, requiresUpload: boolean = false) {
    this.content = content;
    this.version = version;
    this.data = data;
    this.marker = marker;
    this.requiresUpload = requiresUpload;
  }
}

export class CoordinatorRemoteVersion {
  version: string;
  marker: string;

  constructor(version: string = '', marker: string = version) {
    this.version = version;
    this.marker = marker;
  }
}

export interface SyncBackend {
  readonly name: string;
  fetch(): Promise<CoordinatorRemoteSnapshot | null>;
  upload(content: Uint8Array, expectedVersion: string): Promise<CoordinatorRemoteVersion>;
  isConflict(error: Error): boolean;
}

export interface SyncLocalStore {
  loadSnapshot(): Promise<SyncData>;
  applySnapshot(data: SyncData): Promise<void>;
  stateFingerprint(): Promise<string>;
  consumePending(): Promise<void>;
}

export class SyncCoordinatorOptions {
  lastSyncTime: number = 0;
  lastRemoteVersion: string = '';
  maxConflictRetries: number = 3;
  favoritesPlaylistId: number = -1;
}

class CoordinatorMergeRemote {
  data: SyncData;
  exists: boolean;
  requiresUpload: boolean;

  constructor(data: SyncData, exists: boolean, requiresUpload: boolean = false) {
    this.data = data;
    this.exists = exists;
    this.requiresUpload = requiresUpload;
  }
}

class CoordinatorRetryCallbacks implements
  UploadRetryCallbacks<CoordinatorMergeRemote, SyncMergeResult, CoordinatorRemoteVersion> {
  private readonly local: SyncData;
  private readonly backend: SyncBackend;
  private readonly localStore: SyncLocalStore;
  private readonly startFingerprint: string;
  private readonly lastSyncTime: number;
  private readonly favoritesPlaylistId: number;

  constructor(local: SyncData, backend: SyncBackend, localStore: SyncLocalStore,
    startFingerprint: string, lastSyncTime: number, favoritesPlaylistId: number) {
    this.local = local;
    this.backend = backend;
    this.localStore = localStore;
    this.startFingerprint = startFingerprint;
    this.lastSyncTime = lastSyncTime;
    this.favoritesPlaylistId = favoritesPlaylistId;
  }

  merge(remote: CoordinatorMergeRemote): SyncMergeResult {
    return !remote.exists ? buildInitialSyncMerge(this.local, Date.now()) :
      performThreeWayMerge(this.local, remote.data, this.lastSyncTime, Date.now(),
        this.favoritesPlaylistId);
  }

  hasMeaningfulChange(remote: CoordinatorMergeRemote, merged: SyncMergeResult): boolean {
    return !remote.exists || remote.requiresUpload || hasDataChanged(remote.data, merged.data);
  }

  async upload(merged: SyncMergeResult,
    version: CoordinatorRemoteVersion): Promise<CoordinatorRemoteVersion> {
    const currentFingerprint = await this.localStore.stateFingerprint();
    if (currentFingerprint !== this.startFingerprint) {
      throw new Error('同步期间本地数据发生变化，已保留修改并将在下次同步上传');
    }
    return this.backend.upload(serializeSyncDataJson(merged.data), version.version);
  }

  async refetch(_version: CoordinatorRemoteVersion):
    Promise<UploadRefetchResult<CoordinatorMergeRemote, CoordinatorRemoteVersion>> {
    const fresh = await this.backend.fetch();
    if (fresh === null || fresh.data === null) {
      return new UploadRefetchResult(new CoordinatorMergeRemote(this.local, false),
        new CoordinatorRemoteVersion());
    }
    return new UploadRefetchResult(
      new CoordinatorMergeRemote(fresh.data, true, fresh.requiresUpload),
      new CoordinatorRemoteVersion(fresh.version, fresh.marker));
  }

  isConflict(error: Error): boolean {
    return this.backend.isConflict(error);
  }
}

export class SyncCoordinator {
  private static running: boolean = false;
  private readonly backend: SyncBackend;
  private readonly localStore: SyncLocalStore;

  constructor(backend: SyncBackend, localStore: SyncLocalStore) {
    this.backend = backend;
    this.localStore = localStore;
  }

  static isRunning(): boolean {
    return SyncCoordinator.running;
  }

  async run(options: SyncCoordinatorOptions = new SyncCoordinatorOptions()): Promise<SyncReport> {
    if (SyncCoordinator.running) {
      const busy = new SyncReport();
      busy.success = false;
      busy.message = '同步正在进行中';
      return busy;
    }
    SyncCoordinator.running = true;
    try {
      return await this.runLocked(options);
    } catch (error) {
      const report = new SyncReport();
      report.success = false;
      report.message = error instanceof Error ? error.message : '同步失败';
      return report;
    } finally {
      SyncCoordinator.running = false;
    }
  }

  private async runLocked(options: SyncCoordinatorOptions): Promise<SyncReport> {
    const local = await this.localStore.loadSnapshot();
    const startFingerprint = await this.localStore.stateFingerprint();
    const initial = await this.backend.fetch();
    const firstSync = options.lastRemoteVersion.length === 0;
    const remoteMissing = initial === null || initial.data === null;
    const initialData = new CoordinatorMergeRemote(
      remoteMissing ? local : (initial as CoordinatorRemoteSnapshot).data as SyncData,
      !remoteMissing, initial !== null && initial.requiresUpload);
    const remoteVersion = initial === null ? new CoordinatorRemoteVersion() :
      new CoordinatorRemoteVersion(initial.version, initial.marker);
    const remoteChanged = initial !== null && options.lastRemoteVersion.length > 0 &&
      options.lastRemoteVersion !== initial.marker;
    const callbacks = new CoordinatorRetryCallbacks(local, this.backend, this.localStore,
      startFingerprint, options.lastSyncTime, options.favoritesPlaylistId);
    const resolution = await executeUploadWithRetry(
      initialData, remoteVersion, remoteChanged, callbacks, options.maxConflictRetries);
    const currentFingerprint = await this.localStore.stateFingerprint();
    const localChanged = currentFingerprint !== startFingerprint;
    resolution.merged.report.uploadPerformed = resolution.uploadPerformed;
    resolution.merged.report.remoteChangedDuringSync = resolution.remoteChangedDuringSync;
    resolution.merged.report.localChangedDuringSync = localChanged;
    resolution.merged.report.remoteVersion = resolution.remoteVersion.marker;
    if (!localChanged) {
      await this.localStore.applySnapshot(resolution.merged.data);
      await this.localStore.consumePending();
    }
    if (!resolution.uploadPerformed && !resolution.remoteChangedDuringSync && !firstSync) {
      resolution.merged.report.message = '同步完成，无数据变化';
    }
    return resolution.merged.report;
  }
}

/** Parses a backend payload once, keeping decoding errors in coordinator scope. */
export function decodeCoordinatorSnapshot(content: Uint8Array, version: string,
  marker: string = version, requiresUpload: boolean = false): CoordinatorRemoteSnapshot {
  const decoded = deserializeSyncContent(content);
  if (decoded.data === null) {
    throw new Error(`远端备份解析失败：${decoded.errorMessage}`);
  }
  return new CoordinatorRemoteSnapshot(content, version, decoded.data, marker, requiresUpload);
}
