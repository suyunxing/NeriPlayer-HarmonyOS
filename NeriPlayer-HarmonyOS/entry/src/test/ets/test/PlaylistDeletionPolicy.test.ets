import { describe, it, expect } from '@ohos/hypium';
import { PlaylistDeleteSnapshot } from '../../../main/ets/data/LocalPlaylistRepository';
import {
  SyncSong,
  SyncCausalToken,
  SyncPlaylist,
  SyncFavoritePlaylist,
  SyncPlaylistSongDeletion,
  SongIdentityKey,
  syncSongEquals,
  causalTokenEquals,
  cloneSyncSong
} from '../../../main/ets/sync/SyncModels';
import {
  mergeDeletions,
  limitDeletions,
  applyDeletions,
  pruneResolvedDeletions,
  clearLegacyDeletionsForReaddedSongs,
  mergeFavoritePlaylists
} from '../../../main/ets/sync/PlaylistDeletionPolicy';
import { mergeSongs } from '../../../main/ets/sync/PlaylistSongMergePolicy';
import { song, token } from './SongMetadataMergePolicy.test';

function syncSong(
  id: number,
  addedAt: number,
  album: string = 'netease',
  mediaUri: string | null = null,
  membershipTokens: SyncCausalToken[] = []
): SyncSong {
  return song(id, `Song ${id}`, album, 'Artist', null, null, mediaUri, addedAt,
    membershipTokens);
}

function deletion(
  playlistId: number,
  songId: number,
  deletedAt: number,
  album: string = 'netease',
  mediaUri: string | null = null,
  deviceId: string = 'device',
  removedTokens: SyncCausalToken[] = []
): SyncPlaylistSongDeletion {
  return new SyncPlaylistSongDeletion(playlistId, songId, album, mediaUri,
    deletedAt, deviceId, removedTokens);
}

function expectDeletions(actual: SyncPlaylistSongDeletion[], expected: SyncPlaylistSongDeletion[]): void {
  expect(actual.length).assertEqual(expected.length);
  for (let i = 0; i < expected.length; i++) {
    expect(actual[i].stableKey()).assertEqual(expected[i].stableKey());
    expect(actual[i].deletedAt).assertEqual(expected[i].deletedAt);
    expect(actual[i].deviceId).assertEqual(expected[i].deviceId);
    expect(actual[i].removedMembershipTokens.length)
      .assertEqual(expected[i].removedMembershipTokens.length);
    for (let t = 0; t < expected[i].removedMembershipTokens.length; t++) {
      expect(causalTokenEquals(actual[i].removedMembershipTokens[t],
        expected[i].removedMembershipTokens[t])).assertTrue();
    }
  }
}

function expectSongList(actual: SyncSong[], expected: SyncSong[]): void {
  expect(actual.length).assertEqual(expected.length);
  for (let i = 0; i < expected.length; i++) {
    expect(syncSongEquals(actual[i], expected[i])).assertTrue();
  }
}

function expectNumbers(actual: number[], expected: number[]): void {
  expect(actual.length).assertEqual(expected.length);
  for (let i = 0; i < expected.length; i++) {
    expect(actual[i]).assertEqual(expected[i]);
  }
}

export default function playlistDeletionPolicyTest(): void {
  describe('DeletionMerge', () => {
    it('latestDeletionWinsForSamePlaylistSong', 0, () => {
      const first = deletion(7, 11, 100, 'netease', null, 'a');
      const latest = deletion(7, 11, 200, 'netease', null, 'b');
      expectDeletions(mergeDeletions([first], [latest]), [latest]);
    });

    it('mergeUnionsObservedTokensWithDeterministicLegacyMirror', 0, () => {
      const first = deletion(7, 11, 100, 'netease', null, 'a',
        [token('b', 1), token('a', 2)]);
      const latest = deletion(7, 11, 200, 'netease', null, 'b',
        [token('a', 2), token('a', 1)]);
      const localFirst = mergeDeletions([first], [latest]);
      const remoteFirst = mergeDeletions([latest], [first]);
      expectDeletions(localFirst, [new SyncPlaylistSongDeletion(7, 11, 'netease', null,
        200, 'b', [token('a', 1), token('a', 2), token('b', 1)])]);
      expectDeletions(localFirst, remoteFirst);
    });

    it('legacySnapshotDoesNotDeleteCausalReaddAndKeepsBothTombstones', 0, () => {
      const causalDeletion = deletion(7, 11, 100, 'netease', null, 'causal',
        [token('device', 1)]);
      const legacyDeletion = deletion(7, 11, 300, 'netease', null, 'legacy');
      const mergedDeletions = mergeDeletions([causalDeletion], [legacyDeletion]);
      // Sorted newest-first: legacy (300) before causal (100).
      expectDeletions(mergedDeletions, [legacyDeletion, causalDeletion]);
      const mergedSongs = applyDeletions(7, [
        syncSong(11, 200, 'netease', null, [token('device', 2)])
      ], mergedDeletions);
      expect(mergedSongs.length).assertEqual(1);
    });
  });

  describe('ApplyDeletions', () => {
    it('staleSongIsFilteredByDeletion', 0, () => {
      const merged = applyDeletions(7, [syncSong(11, 100)],
        [deletion(7, 11, 200)]);
      expect(merged.length).assertEqual(0);
    });

    it('readdedSongSurvivesNewerThanDeletion', 0, () => {
      const readded = syncSong(11, 300);
      const merged = applyDeletions(7, [readded], [deletion(7, 11, 200)]);
      expectSongList(merged, [readded]);
    });

    it('observedTokenDeletionRemovesOrdinaryMembership', 0, () => {
      const membership = token('device', 1);
      const merged = applyDeletions(7,
        [syncSong(11, 300, 'netease', null, [membership])],
        [deletion(7, 11, 100, 'netease', null, 'device', [membership])]);
      expect(merged.length).assertEqual(0);
    });

    it('restoredMembershipSurvivesDeletionOfOldTokenRegardlessOfTimestamp', 0, () => {
      const restored = syncSong(11, 100, 'netease', null, [token('device', 2)]);
      const merged = applyDeletions(7, [restored],
        [deletion(7, 11, 200, 'netease', null, 'device', [token('device', 1)])]);
      expectSongList(merged, [restored]);
    });

    it('partialObservedDeletionStripsOldTokenAndKeepsConcurrentMembership', 0, () => {
      const oldToken = token('device', 1);
      const concurrentToken = token('other', 1);
      const single = syncSong(11, 100, 'netease', null, [oldToken, concurrentToken]);
      const merged = applyDeletions(7, [single],
        [deletion(7, 11, 200, 'netease', null, 'device', [oldToken])]);
      const expected = cloneSyncSong(single);
      expected.syncMembershipTokens = [concurrentToken];
      expectSongList(merged, [expected]);
    });

    it('observedDeletionRemovesTokenAfterIdentityDrift', 0, () => {
      const membership = token('device', 1);
      const drifted = syncSong(99, 100, 'New Album', 'https://new.invalid/audio',
        [membership]);
      const merged = applyDeletions(7, [drifted],
        [deletion(7, 11, 200, 'Old Album', 'https://old.invalid/audio', 'device',
          [membership])]);
      expect(merged.length).assertEqual(0);
    });

    it('allCausalDeletionsApplyRegardlessOfIdentityAlias', 0, () => {
      const firstToken = token('device', 1);
      const secondToken = token('other', 1);
      const single = syncSong(99, 100, 'netease', null, [firstToken, secondToken]);
      const merged = applyDeletions(7, [single], [
        deletion(7, 11, 200, 'netease', null, 'device', [firstToken]),
        deletion(7, 12, 300, 'netease', null, 'device', [secondToken])
      ]);
      expect(merged.length).assertEqual(0);
    });

    it('causalDeletionApplicationIsIndependentOfDeletionOrder', 0, () => {
      const firstToken = token('device', 1);
      const secondToken = token('other', 1);
      const survivingToken = token('survivor', 1);
      const single = syncSong(99, 100, 'netease', null,
        [firstToken, secondToken, survivingToken]);
      const deletions = [
        deletion(7, 11, 200, 'netease', null, 'device', [firstToken]),
        deletion(7, 12, 300, 'netease', null, 'device', [secondToken])
      ];
      const firstOrder = applyDeletions(7, [single], deletions);
      const reverseOrder = applyDeletions(7, [single], deletions.slice().reverse());
      expectSongList(firstOrder, reverseOrder);
      expect(firstOrder.length).assertEqual(1);
      expect(firstOrder[0].syncMembershipTokens.length).assertEqual(1);
      expect(firstOrder[0].syncMembershipTokens[0].deviceId).assertEqual('survivor');
    });

    it('deletionOnlyAffectsMatchingPlaylist', 0, () => {
      const single = syncSong(11, 100);
      const merged = applyDeletions(7, [single], [deletion(8, 11, 200)]);
      expectSongList(merged, [single]);
    });

    it('legacySongWithoutAddedAtStillRespectsDeletion', 0, () => {
      const merged = applyDeletions(7, [syncSong(11, 0)], [deletion(7, 11, 200)]);
      expect(merged.length).assertEqual(0);
    });

    it('legacyRawIdentityDeletionSurvivesNeteaseIdentityNormalization', 0, () => {
      // Song normalizes to a netease channel identity, but its raw
      // id|album|mediaUri stable key still matches the tombstone.
      const single = syncSong(11, 100, 'Legacy Album');
      const merged = applyDeletions(7, [single],
        [deletion(7, 11, 200, 'Legacy Album', null, 'legacy')]);
      expect(merged.length).assertEqual(0);
    });
  });

  describe('PruneResolvedDeletions', () => {
    it('resolvedReaddWithMembershipTokenPrunesLegacyDeletion', 0, () => {
      const deletions = [deletion(7, 11, 200)];
      const playlists = [new SyncPlaylist(7, 'playlist', [
        syncSong(11, 300, 'netease', null, [token('device', 5)])
      ], 0, 300)];
      const pruned = pruneResolvedDeletions(deletions, playlists);
      expect(pruned.length).assertEqual(0);
    });

    it('legacyMigratedSongWithoutTokenDoesNotPruneDeletion', 0, () => {
      const deletions = [deletion(7, 11, 200)];
      const playlists = [new SyncPlaylist(7, 'playlist', [syncSong(11, 999)], 0, 999)];
      const pruned = pruneResolvedDeletions(deletions, playlists);
      expectDeletions(pruned, deletions);
    });

    it('observedTokenDeletionIsRetainedAfterNewMembershipAppears', 0, () => {
      const causal = deletion(7, 11, 200, 'netease', null, 'device',
        [token('device', 1)]);
      const playlists = [new SyncPlaylist(7, 'playlist', [
        syncSong(11, 300, 'netease', null, [token('device', 2)])
      ], 0, 300)];
      const pruned = pruneResolvedDeletions([causal], playlists);
      expectDeletions(pruned, [causal]);
    });
  });

  describe('ClearLegacyDeletionsForReadded', () => {
    it('readdClearsLegacyDeletionButRetainsObservedTokenDeletion', 0, () => {
      const identitySong = syncSong(11, 300);
      const legacyDeletion = deletion(7, 11, 100, 'netease', null, 'legacy');
      const causalDeletion = deletion(7, 12, 200, 'netease', null, 'device',
        [token('device', 1)]);
      const identities: SongIdentityKey[] = [
        new SongIdentityKey('11', 'netease', null),
        new SongIdentityKey('12', 'netease', null)
      ];
      const retained = clearLegacyDeletionsForReaddedSongs(
        [legacyDeletion, causalDeletion], 7, identities);
      expectDeletions(retained, [causalDeletion]);
      expect(identitySong.name).assertEqual('Song 11');
    });
  });

  describe('BoundedDeletionRetention', () => {
    it('keepsRecentLegacyAndCausalTombstones', 0, () => {
      const legacy: SyncPlaylistSongDeletion[] = [];
      for (let id = 1; id <= 6; id++) {
        legacy.push(deletion(7, id, id, 'netease', null, 'legacy'));
      }
      const causal: SyncPlaylistSongDeletion[] = [];
      for (let id = 11; id <= 16; id++) {
        causal.push(deletion(7, id, id, 'netease', null, 'causal', [token('causal', id)]));
      }
      const retained = limitDeletions(legacy.concat(causal), 6);
      expect(retained.length).assertEqual(6);
      const legacyKept = retained.filter((d: SyncPlaylistSongDeletion): boolean =>
        d.removedMembershipTokens.length === 0);
      const causalKept = retained.filter((d: SyncPlaylistSongDeletion): boolean =>
        d.removedMembershipTokens.length > 0);
      expect(legacyKept.length).assertEqual(3);
      expect(causalKept.length).assertEqual(3);
      expectNumbers(legacyKept.map((d: SyncPlaylistSongDeletion): number => d.songId)
        .sort((a: number, b: number): number => a - b), [4, 5, 6]);
      expectNumbers(causalKept.map((d: SyncPlaylistSongDeletion): number => d.songId)
        .sort((a: number, b: number): number => a - b), [14, 15, 16]);
    });

    it('fillsUnusedClassCapacity', 0, () => {
      const legacy: SyncPlaylistSongDeletion[] = [];
      for (let id = 1; id <= 2; id++) {
        legacy.push(deletion(7, id, id, 'netease', null, 'legacy'));
      }
      const causal: SyncPlaylistSongDeletion[] = [];
      for (let id = 11; id <= 16; id++) {
        causal.push(deletion(7, id, id, 'netease', null, 'causal', [token('causal', id)]));
      }
      const retained = limitDeletions(legacy.concat(causal), 6);
      expect(retained.length).assertEqual(6);
      expect(retained.filter((d: SyncPlaylistSongDeletion): boolean =>
        d.removedMembershipTokens.length === 0).length).assertEqual(2);
      expect(retained.filter((d: SyncPlaylistSongDeletion): boolean =>
        d.removedMembershipTokens.length > 0).length).assertEqual(4);
    });
  });

  describe('MergeFavoritePlaylists', () => {
    it('deletionWinsEqualTimestampTies', 0, () => {
      const active = new SyncFavoritePlaylist(1, 'name', null, 1, 'netease',
        [syncSong(11, 100)], 0, 100, false, 100);
      const deleted = new SyncFavoritePlaylist(1, 'name', null, 0, 'netease',
        [], 0, 100, true, 100);
      const merged = mergeFavoritePlaylists(active, deleted);
      expect(merged.isDeleted).assertTrue();
      expect(merged.songs.length).assertEqual(0);
      expect(merged.trackCount).assertEqual(0);
    });

    it('newerActiveFavoritesUnionSongsAndSortOrder', 0, () => {
      const older = new SyncFavoritePlaylist(1, 'name', 'https://old', 1, 'netease',
        [syncSong(11, 100)], 0, 100, false, 100);
      const newer = new SyncFavoritePlaylist(1, 'name', null, 1, 'netease',
        [syncSong(12, 150)], 0, 200, false, 200);
      const merged = mergeFavoritePlaylists(older, newer);
      expect(merged.isDeleted).assertFalse();
      expect(merged.songs.length).assertEqual(2);
      expect(merged.modifiedAt).assertEqual(200);
      expect(merged.sortOrder).assertEqual(200);
      expect(merged.coverUrl).assertEqual('https://old');
      expect(merged.trackCount).assertEqual(2);
    });
  });

  describe('ObservedRemoveIntegration', () => {
    it('restoredMembershipSurvivesOldClearAndRemainsDeletable', 0, () => {
      const oldMembership = token('device', 1);
      const restoredMembership = token('device', 2);
      const restoredSong = syncSong(11, 100, 'netease', null, [restoredMembership]);

      const mergedSongs = mergeSongs([restoredSong], [], 100, 10000, true, true, 50, false).songs;
      const oldDeletion = deletion(7, 11, 200, 'netease', null, 'device', [oldMembership]);
      const restoredResult = applyDeletions(7, mergedSongs, [oldDeletion]);
      expectSongList(restoredResult, [restoredSong]);

      const laterDeletion = deletion(7, 11, 20000, 'netease', null, 'device',
        [restoredMembership]);
      const deletedResult = applyDeletions(7, restoredResult, [oldDeletion, laterDeletion]);
      expect(deletedResult.length).assertEqual(0);
    });
  });

  describe('PlaylistDeleteSnapshotJson', () => {
    it('roundTripsSnapshotPayload', 0, () => {
      const snapshot = new PlaylistDeleteSnapshot();
      snapshot.playlistJson = '{\"id\":\"local_1\"}';
      snapshot.index = 3;
      snapshot.deletedAt = 123456;
      const revived = PlaylistDeleteSnapshot.fromJson(snapshot.toJson());
      expect(revived !== null).assertTrue();
      expect(revived!.playlistJson).assertEqual('{\"id\":\"local_1\"}');
      expect(revived!.index).assertEqual(3);
      expect(revived!.deletedAt).assertEqual(123456);
    });

    it('rejectsEmptyAndGarbageJson', 0, () => {
      expect(PlaylistDeleteSnapshot.fromJson('not json')).assertNull();
      const empty = PlaylistDeleteSnapshot.fromJson('{"playlistJson":"","index":1,"deletedAt":2}');
      expect(empty).assertNull();
    });
  });
}
