import { describe, it, expect } from '@ohos/hypium';
import {
  SyncData,
  SyncPlaylist,
  SyncRecentPlay,
  SyncPlaylistSongDeletion,
  SyncRecentPlayDeletion,
  SyncSong
} from '../../../main/ets/sync/SyncModels';
import { performThreeWayMerge } from '../../../main/ets/sync/SyncMergeEngine';
import {
  playlistIdToSync,
  syncPlaylistIdToLocal
} from '../../../main/ets/sync/SyncSongConvert';
import {
  SnapshotDeletedPlaylistInput,
  SnapshotPlaylistInput,
  SyncSnapshotInput,
  buildLocalSyncData
} from '../../../main/ets/sync/SyncSnapshotBuilder';
import { Playlist } from '../../../main/ets/model/Playlist';
import { MusicPlatform } from '../../../main/ets/model/MusicPlatform';

/**
 * M5.7 regression nail: a playlist deleted on device A must stay deleted
 * through the whole multi-device relay (A uploads tombstone -> B relays it
 * -> A re-syncs against B's copy). Each step asserts the merged row keeps
 * isDeleted=true. If any step resurrects the playlist as a live row, the
 * tombstone propagation is broken.
 */

function song(id: number, name: string): SyncSong {
  return new SyncSong(id, name, 'artist', 'netease', 0, 1000, null, null, 1,
    null, null, null, null, 0, null, null, null, null, null, null, null, null,
    'netease', `${id}`);
}

function data(playlists: SyncPlaylist[]): SyncData {
  const recent: SyncRecentPlay[] = [];
  const recentDeletions: SyncRecentPlayDeletion[] = [];
  const songDeletions: SyncPlaylistSongDeletion[] = [];
  return new SyncData('2.0', 'device', 'test', 1, playlists, [], recent, [],
    recentDeletions, [], 0, [], songDeletions);
}

function deletedRowOf(result: SyncData, playlistId: number): boolean {
  const row = result.playlists.find(item => item.id === playlistId);
  if (row === undefined) {
    return false;
  }
  return row.isDeleted;
}

export default function syncTombstonePropagationTest(): void {
  describe('SyncTombstonePropagationTest', () => {
    it('tombstoneSurvivesMultiDeviceRelay', 0, () => {
      const playlistId = 424242;
      // Step 1: A creates and uploads a live playlist (first-sync backup U1).
      const aUpload1 = data([new SyncPlaylist(playlistId, 'P', [song(1, 's')],
        100, 200)]);

      // Step 2: A deletes the playlist locally. Snapshot shape mirrors
      // SyncSnapshotBuilder: no live row + tombstone row (createdAt=0,
      // modifiedAt=deletedAt, isDeleted=true).
      const aAfterDelete = data([new SyncPlaylist(playlistId, '', [], 0, 300,
        true)]);

      // A syncs against the stale remote copy that still has the live row.
      const aMerged = performThreeWayMerge(aAfterDelete, aUpload1, 0, 400, -1);
      expect(deletedRowOf(aMerged.data, playlistId)).assertTrue();

      // Step 3: B has never seen the playlist (empty local store) and
      // relays A's merged backup.
      const bLocal = data([]);
      const bMerged = performThreeWayMerge(bLocal, aMerged.data, 0, 500, -1);
      expect(deletedRowOf(bMerged.data, playlistId)).assertTrue();

      // Step 4: A re-syncs against B's relayed copy while A still carries
      // the tombstone locally.
      const aMerged2 = performThreeWayMerge(aAfterDelete, bMerged.data, 0, 600, -1);
      expect(deletedRowOf(aMerged2.data, playlistId)).assertTrue();

      // Step 5: even if A lost its local tombstone (e.g. store reset), the
      // relayed remote tombstone alone must still win over nothing.
      const aWithoutTombstone = data([]);
      const aMerged3 = performThreeWayMerge(aWithoutTombstone, bMerged.data, 0, 700, -1);
      expect(deletedRowOf(aMerged3.data, playlistId)).assertTrue();
    });
    it('builderEmitsTombstoneRowWhenPlaylistDeleted', 0, () => {
      // No live playlists, one tombstone: the snapshot must carry the
      // playlist as an isDeleted row (not drop it, not resurrect it).
      const input = new SyncSnapshotInput('device', 'test');
      input.deletedPlaylists.push(new SnapshotDeletedPlaylistInput(424242, 999));
      const snapshot = buildLocalSyncData(input, 1000);
      const row = snapshot.playlists.find(item => item.id === 424242);
      expect(row !== undefined).assertTrue();
      if (row !== undefined) {
        expect(row.isDeleted).assertTrue();
        expect(row.modifiedAt).assertEqual(999);
        expect(row.songs.length).assertEqual(0);
      }
    });

    it('builderDropsTombstoneWhenPlaylistIsLiveAgain', 0, () => {
      // The live-again guard: a tombstone whose id matches a live playlist
      // must NOT emit a second (deleted) row.
      const input = new SyncSnapshotInput('device', 'test');
      input.deletedPlaylists.push(new SnapshotDeletedPlaylistInput(424242, 999));
      const playlist = new Playlist('local_424242', 'Live', MusicPlatform.LOCAL);
      input.playlists.push(new SnapshotPlaylistInput(playlist, 200));
      const snapshot = buildLocalSyncData(input, 1000);
      const rows = snapshot.playlists.filter(item => item.id === 424242);
      expect(rows.length).assertEqual(1);
      expect(rows[0].isDeleted).assertFalse();
    });
    it('playlistIdRoundTripKeepsLocalShapeUsable', 0, () => {
      // M5.7 regression: syncPlaylistIdToLocal used to return the bare
      // numeric text, so a playlist created as "local_<ts>" came back from a
      // sync apply with a different id string. Any later by-id removal (exact
      // string match) silently missed it and the playlist resurrected.
      expect(syncPlaylistIdToLocal(424242)).assertEqual('local_424242');
      expect(playlistIdToSync(syncPlaylistIdToLocal(424242))).assertEqual(424242);
      // Both historical local shapes must still map to the same sync id.
      expect(playlistIdToSync('local_424242')).assertEqual(playlistIdToSync('424242'));
      // Non-numeric ids hash, and the hash survives the reverse mapping.
      const favoritesKey = playlistIdToSync('favorites');
      expect(playlistIdToSync(syncPlaylistIdToLocal(favoritesKey))).assertEqual(favoritesKey);
    });
  });
}
