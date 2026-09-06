import { describe, it, expect } from '@ohos/hypium';
import {
  SyncData,
  SyncPlaylist,
  SyncPlaylistSongDeletion,
  SyncRecentPlay,
  SyncRecentPlayDeletion,
  SyncSong
} from '../../../main/ets/sync/SyncModels';
import {
  buildInitialSyncMerge,
  performThreeWayMerge
} from '../../../main/ets/sync/SyncMergeEngine';
import { SyncConflictResolution } from '../../../main/ets/sync/SyncReport';
import {
  executeUploadWithRetry,
  UploadRefetchResult,
  UploadRetryCallbacks
} from '../../../main/ets/sync/SyncUploadRetryExecutor';
import {
  CoordinatorRemoteSnapshot,
  CoordinatorRemoteVersion,
  SyncBackend,
  SyncCoordinator,
  SyncCoordinatorOptions,
  SyncLocalStore
} from '../../../main/ets/sync/SyncCoordinator';

function song(id: number, name: string, addedAt: number = 1): SyncSong {
  return new SyncSong(id, name, 'artist', 'netease', 0, 1000, null, null, addedAt,
    null, null, null, null, 0, null, null, null, null, null, null, null, null,
    'netease', `${id}`);
}

function data(playlists: SyncPlaylist[], recent: SyncRecentPlay[] = [],
  recentDeletions: SyncRecentPlayDeletion[] = [],
  songDeletions: SyncPlaylistSongDeletion[] = []): SyncData {
  return new SyncData('2.0', 'device', 'test', 1, playlists, [], recent, [],
    recentDeletions, [], 0, [], songDeletions);
}

class ConflictError extends Error {
  constructor() {
    super('conflict');
    this.name = 'ConflictError';
  }
}

class RetryCallbacks implements UploadRetryCallbacks<number, number, number> {
  uploadAttempts: number = 0;
  refetches: number = 0;
  failCount: number = 0;
  meaningful: boolean = true;

  merge(remote: number): number {
    return remote + 10;
  }

  hasMeaningfulChange(_remote: number, _merged: number): boolean {
    return this.meaningful;
  }

  async upload(_merged: number, version: number): Promise<number> {
    this.uploadAttempts++;
    if (this.uploadAttempts <= this.failCount) {
      throw new ConflictError();
    }
    return version + 1;
  }

  async refetch(version: number): Promise<UploadRefetchResult<number, number>> {
    this.refetches++;
    return new UploadRefetchResult(5 + this.refetches, version + 10);
  }

  isConflict(error: Error): boolean {
    return error instanceof ConflictError;
  }
}

class FakeLocalStore implements SyncLocalStore {
  snapshot: SyncData;
  fingerprint: string = 'local-v1';
  applied: SyncData | null = null;
  pendingConsumed: boolean = false;

  constructor(snapshot: SyncData) {
    this.snapshot = snapshot;
  }

  async loadSnapshot(): Promise<SyncData> {
    return this.snapshot;
  }

  async applySnapshot(data: SyncData): Promise<void> {
    this.applied = data;
  }

  async stateFingerprint(): Promise<string> {
    return this.fingerprint;
  }

  async consumePending(): Promise<void> {
    this.pendingConsumed = true;
  }
}

class FakeBackend implements SyncBackend {
  readonly name: string = 'fake';
  snapshots: (CoordinatorRemoteSnapshot | null)[] = [];
  fetchCalls: number = 0;
  uploadCalls: number = 0;
  conflictFailures: number = 0;
  uploadedVersions: string[] = [];
  mutateStore: FakeLocalStore | null = null;

  async fetch(): Promise<CoordinatorRemoteSnapshot | null> {
    const index = Math.min(this.fetchCalls, Math.max(this.snapshots.length - 1, 0));
    this.fetchCalls++;
    return this.snapshots.length === 0 ? null : this.snapshots[index];
  }

  async upload(_content: Uint8Array, expectedVersion: string): Promise<CoordinatorRemoteVersion> {
    this.uploadCalls++;
    this.uploadedVersions.push(expectedVersion);
    if (this.uploadCalls <= this.conflictFailures) {
      throw new ConflictError();
    }
    if (this.mutateStore !== null) {
      this.mutateStore.fingerprint = 'local-v2';
    }
    return new CoordinatorRemoteVersion(`version-${this.uploadCalls}`, `marker-${this.uploadCalls}`);
  }

  isConflict(error: Error): boolean {
    return error instanceof ConflictError;
  }
}

function remoteSnapshot(value: SyncData, version: string, marker: string,
  requiresUpload: boolean = false): CoordinatorRemoteSnapshot {
  return new CoordinatorRemoteSnapshot(new Uint8Array([1]), version, value, marker, requiresUpload);
}

export default function syncCoordinatorTest(): void {
  describe('SyncMergeEngine', () => {
    it('buildsInitialReportAndFinalizesTimestamp', 0, () => {
      const local = data([new SyncPlaylist(1, 'Local', [song(1, 'A')], 1, 10)]);
      const merged = buildInitialSyncMerge(local, 99);
      expect(merged.data.lastModified).assertEqual(99);
      expect(merged.report.playlistsAdded).assertEqual(1);
      expect(merged.report.songsAdded).assertEqual(1);
    });

    it('remoteOnlyRenameWinsAndIsReported', 0, () => {
      const local = data([new SyncPlaylist(1, 'Old', [song(1, 'A')], 1, 10)]);
      const remote = data([new SyncPlaylist(1, 'Remote', [song(1, 'A')], 1, 30)]);
      const merged = performThreeWayMerge(local, remote, 20, 40, -1);
      expect(merged.data.playlists[0].name).assertEqual('Remote');
      expect(merged.report.conflicts.length).assertEqual(1);
      expect(merged.report.conflicts[0].resolution).assertEqual(SyncConflictResolution.REMOTE_WINS);
    });

    it('concurrentRenameKeepsLocalAndRequiresManualReview', 0, () => {
      const local = data([new SyncPlaylist(1, 'Local', [song(1, 'A')], 1, 31)]);
      const remote = data([new SyncPlaylist(1, 'Remote', [song(1, 'A')], 1, 30)]);
      const merged = performThreeWayMerge(local, remote, 20, 40, -1);
      expect(merged.data.playlists[0].name).assertEqual('Local');
      expect(merged.report.conflicts[0].resolution)
        .assertEqual(SyncConflictResolution.MANUAL_REQUIRED);
    });

    it('appliesPlaylistSongTombstoneAfterMembershipMerge', 0, () => {
      const local = data([new SyncPlaylist(1, 'P', [], 1, 30)], [], [],
        [new SyncPlaylistSongDeletion(1, 7, 'netease', null, 25, 'a')]);
      const remote = data([new SyncPlaylist(1, 'P', [song(7, 'Removed', 10)], 1, 10)]);
      const merged = performThreeWayMerge(local, remote, 20, 40, -1);
      expect(merged.data.playlists[0].songs.length).assertEqual(0);
    });

    it('keepsNewestRecentPlayAndHonorsDeletion', 0, () => {
      const oldPlay = new SyncRecentPlay(7, song(7, 'A'), 10, 'a', 0);
      const newPlay = new SyncRecentPlay(7, song(7, 'A'), 30, 'b', 2);
      const deletion = new SyncRecentPlayDeletion(8, 'netease', null, 40, 'b');
      const local = data([], [oldPlay, new SyncRecentPlay(8, song(8, 'B'), 20, 'a', 0)]);
      const remote = data([], [newPlay], [deletion]);
      const merged = performThreeWayMerge(local, remote, 1, 50, -1);
      expect(merged.data.recentPlays.length).assertEqual(1);
      expect(merged.data.recentPlays[0].playedAt).assertEqual(30);
    });
  });

  describe('SyncUploadRetryExecutor', () => {
    it('skipsUploadWhenMergeHasNoMeaningfulChange', 0, async () => {
      const callbacks = new RetryCallbacks();
      callbacks.meaningful = false;
      const result = await executeUploadWithRetry(1, 2, false, callbacks);
      expect(result.uploadPerformed).assertFalse();
      expect(callbacks.uploadAttempts).assertEqual(0);
    });

    it('refetchesAndReMergesAfterConflict', 0, async () => {
      const callbacks = new RetryCallbacks();
      callbacks.failCount = 1;
      const result = await executeUploadWithRetry(1, 2, false, callbacks);
      expect(result.uploadPerformed).assertTrue();
      expect(result.remoteChangedDuringSync).assertTrue();
      expect(callbacks.uploadAttempts).assertEqual(2);
      expect(callbacks.refetches).assertEqual(1);
      expect(result.merged).assertEqual(16);
    });

    it('stopsAtConflictRetryBudget', 0, async () => {
      const callbacks = new RetryCallbacks();
      callbacks.failCount = 10;
      let caught = false;
      try {
        await executeUploadWithRetry(1, 2, false, callbacks, 2);
      } catch (error) {
        caught = error instanceof ConflictError;
      }
      expect(caught).assertTrue();
      expect(callbacks.uploadAttempts).assertEqual(3);
      expect(callbacks.refetches).assertEqual(2);
    });
  });

  describe('SyncCoordinatorIntegration', () => {
    it('runsFetchConflictRefetchUploadApplyAndPendingConsumption', 0, async () => {
      const local = data([new SyncPlaylist(1, 'P', [song(1, 'Local', 30)], 1, 30)]);
      const initialRemote = data([new SyncPlaylist(1, 'P', [song(2, 'Remote', 20)], 1, 20)]);
      const freshRemote = data([new SyncPlaylist(1, 'P', [song(3, 'Fresh', 40)], 1, 40)]);
      const store = new FakeLocalStore(local);
      const backend = new FakeBackend();
      backend.snapshots = [
        remoteSnapshot(initialRemote, 'version-a', 'marker-a'),
        remoteSnapshot(freshRemote, 'version-b', 'marker-b')
      ];
      backend.conflictFailures = 1;
      const options = new SyncCoordinatorOptions();
      options.lastRemoteVersion = 'marker-old';
      const report = await new SyncCoordinator(backend, store).run(options);

      expect(report.success).assertTrue();
      expect(report.remoteChangedDuringSync).assertTrue();
      expect(report.uploadPerformed).assertTrue();
      expect(report.remoteVersion).assertEqual('marker-2');
      expect(backend.fetchCalls).assertEqual(2);
      expect(backend.uploadCalls).assertEqual(2);
      expect(backend.uploadedVersions[0]).assertEqual('version-a');
      expect(backend.uploadedVersions[1]).assertEqual('version-b');
      expect(store.applied !== null).assertTrue();
      expect(store.pendingConsumed).assertTrue();
      expect((store.applied as SyncData).playlists[0].songs.length).assertEqual(2);
    });

    it('skipsLocalApplyAndPendingConsumptionWhenLocalStateChanges', 0, async () => {
      const local = data([new SyncPlaylist(1, 'P', [song(1, 'Local', 30)], 1, 30)]);
      const store = new FakeLocalStore(local);
      const backend = new FakeBackend();
      backend.snapshots = [null];
      backend.mutateStore = store;
      const report = await new SyncCoordinator(backend, store).run();

      expect(report.success).assertTrue();
      expect(report.localChangedDuringSync).assertTrue();
      expect(report.remoteVersion).assertEqual('marker-1');
      expect(store.applied === null).assertTrue();
      expect(store.pendingConsumed).assertFalse();
    });

    it('detectsRemoteMarkerChangeEvenWhenNoUploadIsNeeded', 0, async () => {
      const shared = data([]);
      const store = new FakeLocalStore(shared);
      const backend = new FakeBackend();
      backend.snapshots = [remoteSnapshot(shared, 'condition-v2', 'marker-v2')];
      const options = new SyncCoordinatorOptions();
      options.lastRemoteVersion = 'marker-v1';
      const report = await new SyncCoordinator(backend, store).run(options);

      expect(report.remoteChangedDuringSync).assertTrue();
      expect(report.uploadPerformed).assertFalse();
      expect(report.remoteVersion).assertEqual('marker-v2');
      expect(store.pendingConsumed).assertTrue();
    });

    it('uploadsPreferredFormatWhenRemoteFallbackFileRequiresMigration', 0, async () => {
      const shared = data([new SyncPlaylist(1, 'P', [song(1, 'Same', 30)], 1, 30)]);
      const store = new FakeLocalStore(shared);
      const backend = new FakeBackend();
      backend.snapshots = [remoteSnapshot(shared, 'version-v1', 'marker-v1', true)];
      const options = new SyncCoordinatorOptions();
      options.lastRemoteVersion = 'marker-v1';
      const report = await new SyncCoordinator(backend, store).run(options);

      expect(report.uploadPerformed).assertTrue();
      expect(backend.uploadCalls).assertEqual(1);
    });
  });
}
