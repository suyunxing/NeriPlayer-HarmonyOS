import { describe, it, expect } from '@ohos/hypium';
import {
  SyncSong,
  SyncCausalToken,
  syncSongEquals,
  cloneSyncSong,
  CURRENT_SYNC_METADATA_VERSION
} from '../../../main/ets/sync/SyncModels';
import { mergeSongs, deduplicateSongs } from '../../../main/ets/sync/PlaylistSongMergePolicy';
import { song, token } from './SongMetadataMergePolicy.test';

function withAlbum(base: SyncSong, album: string): SyncSong {
  const copy = cloneSyncSong(base);
  copy.album = album;
  return copy;
}

function withAddedAt(base: SyncSong, addedAt: number): SyncSong {
  const copy = cloneSyncSong(base);
  copy.addedAt = addedAt;
  return copy;
}

function withTokens(base: SyncSong, tokens: SyncCausalToken[]): SyncSong {
  const copy = cloneSyncSong(base);
  copy.syncMembershipTokens = tokens;
  return copy;
}

function withName(base: SyncSong, name: string): SyncSong {
  const copy = cloneSyncSong(base);
  copy.name = name;
  return copy;
}

function expectSongs(actual: SyncSong[], expected: SyncSong[]): void {
  expect(actual.length).assertEqual(expected.length);
  for (let i = 0; i < expected.length; i++) {
    expect(syncSongEquals(actual[i], expected[i])).assertTrue();
  }
}

function songIds(songs: SyncSong[]): number[] {
  return songs.map((s: SyncSong): number => s.id);
}

function addedAts(songs: SyncSong[]): number[] {
  return songs.map((s: SyncSong): number => s.addedAt);
}

function expectNumbers(actual: number[], expected: number[]): void {
  expect(actual.length).assertEqual(expected.length);
  for (let i = 0; i < expected.length; i++) {
    expect(actual[i]).assertEqual(expected[i]);
  }
}

export default function playlistSongMergePolicyTest(): void {
  describe('PlaylistSongMergeOneSided', () => {
    it('remotePhoneReorderKeepsRemoteAddedAtValuesAndOrder', 0, () => {
      const local = [
        song(1, 'A', '', '', null, null, null, 300),
        song(2, 'B', '', '', null, null, null, 200),
        song(3, 'C', '', '', null, null, null, 100)
      ];
      const remote = [
        withAddedAt(local[2], 900),
        withAddedAt(local[0], 899),
        withAddedAt(local[1], 898)
      ];
      const result = mergeSongs(local, remote, 100, 300, false, true, 200, false);
      expectNumbers(songIds(result.songs), [3, 1, 2]);
      expectNumbers(addedAts(result.songs), [900, 899, 898]);
      expect(result.isUpdated).assertTrue();
    });

    it('localDesktopReorderKeepsLocalAddedAtValuesAndOrder', 0, () => {
      const remote = [
        song(1, 'A', '', '', null, null, null, 300),
        song(2, 'B', '', '', null, null, null, 200),
        song(3, 'C', '', '', null, null, null, 100)
      ];
      const local = [
        withAddedAt(remote[1], 900),
        withAddedAt(remote[2], 899),
        withAddedAt(remote[0], 898)
      ];
      const result = mergeSongs(local, remote, 300, 100, true, false, 200, false);
      expectNumbers(songIds(result.songs), [2, 3, 1]);
      expectNumbers(addedAts(result.songs), [900, 899, 898]);
      expect(result.isUpdated).assertFalse();
    });
  });

  describe('PlaylistSongClearSemantics', () => {
    it('localClearWinsWhenLocalPlaylistChangedAfterSync', 0, () => {
      const result = mergeSongs([], [song(1, 'Song')], 200, 100, true, false, 150, false);
      expect(result.songs.length).assertEqual(0);
      expect(result.isUpdated).assertFalse();
    });

    it('remoteClearWinsWhenRemotePlaylistChangedAfterSync', 0, () => {
      const result = mergeSongs([song(1, 'Song')], [], 100, 200, false, true, 150, false);
      expect(result.songs.length).assertEqual(0);
      expect(result.isUpdated).assertTrue();
    });

    it('localClearDefersTokenizedRemoteMembershipToDeletionPolicy', 0, () => {
      const remoteSong = song(1, 'Restored', '', '', null, null, null, 0, [token('remote', 2)]);
      const result = mergeSongs([], [remoteSong], 300, 100, true, false, 200, false);
      expectSongs(result.songs, [remoteSong]);
    });

    it('remoteClearDefersTokenizedLocalMembershipToDeletionPolicy', 0, () => {
      const localSong = song(1, 'Restored', '', '', null, null, null, 0, [token('local', 2)]);
      const result = mergeSongs([localSong], [], 100, 300, false, true, 200, false);
      expectSongs(result.songs, [localSong]);
    });

    it('largeLocalClearSkipsRemoteRefill', 0, () => {
      const remoteSongs: SyncSong[] = [];
      for (let index = 1; index <= 2000; index++) {
        remoteSongs.push(song(index, `Song ${index}`));
      }
      const result = mergeSongs([], remoteSongs, 300, 200, true, false, 250, false);
      expect(result.songs.length).assertEqual(0);
      expect(result.isUpdated).assertFalse();
    });

    it('emptySnapshotsAreNotMarkedUpdated', 0, () => {
      const result = mergeSongs([], [], 200, 100, true, false, 150, false);
      expect(result.songs.length).assertEqual(0);
      expect(result.isUpdated).assertFalse();
    });
  });

  describe('PlaylistSongPayloadResolution', () => {
    it('legacyPrimaryOrderKeepsCurrentRichMetadata', 0, () => {
      const current = song(1, 'Original', '', '', null, null, null, 100);
      current.matchedLyric = '[00:01.00]lyric';
      current.customName = 'Custom title';
      current.originalName = 'Original';
      const legacyPrimary = cloneSyncSong(current);
      legacyPrimary.name = 'Custom title';
      legacyPrimary.addedAt = 900;
      legacyPrimary.matchedLyric = null;
      legacyPrimary.customName = null;
      legacyPrimary.originalName = null;
      legacyPrimary.syncMetadataVersion = 0;

      const result = mergeSongs([current], [legacyPrimary], 100, 300, false, true, 200, false);
      const merged = result.songs[0];
      expect(merged.addedAt).assertEqual(900);
      expect(merged.name).assertEqual('Original');
      expect(merged.matchedLyric).assertEqual('[00:01.00]lyric');
      expect(merged.customName).assertEqual('Custom title');
      expect(merged.syncMetadataVersion).assertEqual(CURRENT_SYNC_METADATA_VERSION);
    });

    it('currentPrimaryCanIntentionallyClearMetadata', 0, () => {
      const local = song(1, 'Song', '', '', null, null, null, 100);
      local.matchedLyric = '[00:01.00]old lyric';
      local.customName = 'Old custom title';
      const remote = cloneSyncSong(local);
      remote.addedAt = 200;
      remote.matchedLyric = null;
      remote.customName = null;

      const result = mergeSongs([local], [remote], 100, 300, false, true, 200, false);
      expect(result.songs[0].matchedLyric).assertNull();
      expect(result.songs[0].customName).assertNull();
    });

    it('primaryMissingAddedAtInheritsKnownValueInsteadOfMovingToTop', 0, () => {
      const current = song(1, 'Song', '', '', null, null, null, 500);
      const legacyPrimary = song(1, 'Song', '', '', null, null, null, 0, [], 0);
      const result = mergeSongs([current], [legacyPrimary], 100, 300, false, true, 200, false);
      expect(result.songs[0].addedAt).assertEqual(500);
    });

    it('unmarkedLegacyLocalMetadataIsNotForciblyOverwrittenByRemote', 0, () => {
      const local = song(1, 'Z Legacy user title', '', '', 'netease', '1', null, 0,
        [token('local', 1)], 0);
      local.customName = 'Z Legacy custom title';
      const remote = song(1, 'A Synced title', '', '', 'netease', '1', null, 0,
        [token('remote', 1)], 0);
      const result = mergeSongs([local], [remote], 100, 100, false, false, 200, false);
      expect(result.songs.length).assertEqual(1);
      expect(result.songs[0].name).assertEqual('Z Legacy user title');
      expect(result.songs[0].customName).assertEqual('Z Legacy custom title');
      expect(result.songs[0].syncMembershipTokens.length).assertEqual(2);
      expect(result.songs[0].syncMembershipTokens[0].deviceId).assertEqual('local');
      expect(result.songs[0].syncMembershipTokens[1].deviceId).assertEqual('remote');
      expect(result.isUpdated).assertTrue();
    });
  });

  describe('PlaylistSongMatchingKeys', () => {
    it('sameChannelAudioSongIsNotDuplicatedWhenAlbumChanges', 0, () => {
      const localSong = song(1, 'Song', 'Old Album', 'Artist', 'netease', '1');
      const remoteSong = song(1, 'Song', 'New Album', 'Artist', 'netease', '1');
      // Both changed with equal timestamps → deterministic payload branch;
      // length prefix makes "9:Old Album" the larger canonical key.
      const result = mergeSongs([localSong], [remoteSong], 200, 200, true, true, 100, false);
      expectSongs(result.songs, [localSong]);
    });

    it('channelAudioDuplicateUnionsMembershipTokens', 0, () => {
      const localToken = token('local', 1);
      const remoteToken = token('remote', 1);
      const localSong = song(1, 'Song', 'Old Album', 'Artist', 'netease', '1', null, 0,
        [localToken]);
      const remoteSong = withTokens(withAlbum(localSong, 'New Album'), [remoteToken]);

      const result = deduplicateSongs([localSong, remoteSong]);
      expectSongs(result, [withTokens(localSong, [localToken, remoteToken])]);
    });

    it('nonExactMembershipMergeResolvesPayloadDeterministically', 0, () => {
      const localSong = song(1, 'Song', 'Old Album', 'Artist', 'netease', '1', null, 0,
        [token('local', 1)]);
      const remoteSong = withTokens(withAlbum(localSong, 'New Album'), [token('remote', 1)]);

      const localFirst = mergeSongs([localSong], [remoteSong], 200, 200, true, true, 100, false);
      const remoteFirst = mergeSongs([remoteSong], [localSong], 200, 200, true, true, 100, false);
      expectSongs(localFirst.songs, remoteFirst.songs);
    });

    it('remotePrimaryUnionsTokenFromNonExactLocalDuplicate', 0, () => {
      const localToken = token('local', 1);
      const remoteToken = token('remote', 1);
      const localSong = song(1, 'Local', 'Old Album', 'Artist', 'netease', '1', null, 0,
        [localToken]);
      const remoteSong = withTokens(withAlbum(withName(localSong, 'Remote'), 'New Album'),
        [remoteToken]);

      const result = mergeSongs([localSong], [remoteSong], 100, 200, false, true, 150, false);
      expectSongs(result.songs, [withTokens(remoteSong, [localToken, remoteToken])]);
    });

    it('fallbackDuplicateUnionsMembershipTokens', 0, () => {
      const first = song(1, 'Song', 'Legacy A', 'Artist', null, null,
        'https://legacy-a.invalid/audio', 0, [token('a', 1)]);
      const duplicate = withTokens(
        withAlbum(withMedia(first, 'https://legacy-b.invalid/audio'), 'Legacy B'),
        [token('b', 1)]);
      const result = deduplicateSongs([first, duplicate]);
      expectSongs(result, [withTokens(first, [token('a', 1), token('b', 1)])]);
    });

    it('fallbackMergeKeepsDifferentSourceHints', 0, () => {
      const neteaseSong = song(1, 'Song', 'netease album');
      const biliSong = song(1, 'Song', 'bilibili album');
      const result = deduplicateSongs([neteaseSong, biliSong]);
      expectSongs(result, [neteaseSong, biliSong]);
    });

    it('sharedMembershipTokenCollapsesIdentityDrift', 0, () => {
      const membership = token('device', 1);
      const legacy = song(1, 'Legacy', 'Legacy Album', 'Artist', null, null, null, 0,
        [membership]);
      const hydrated = song(9, 'Hydrated', 'New Album', 'Artist', 'netease', '9', null, 0,
        [membership]);
      const result = deduplicateSongs([legacy, hydrated]);
      expectSongs(result, [legacy]);
    });

    it('bridgeAliasesMergeTheCompleteMembershipComponent', 0, () => {
      const tokenA = token('a', 1);
      const tokenB = token('b', 1);
      const first = song(1, 'First', 'First Album', 'Artist', null, null,
        'https://first.invalid/audio', 0, [tokenA]);
      const second = song(2, 'Second', 'Second Album', 'Artist', null, null,
        'https://second.invalid/audio', 0, [tokenB]);
      const bridge = withTokens(first, [tokenB]);
      const permutations = [
        [first, second, bridge],
        [second, bridge, first],
        [bridge, first, second]
      ];
      for (const songs of permutations) {
        const result = deduplicateSongs(songs);
        expect(result.length).assertEqual(1);
        expect(result[0].syncMembershipTokens.length).assertEqual(2);
        expect(result[0].syncMembershipTokens[0].deviceId).assertEqual('a');
        expect(result[0].syncMembershipTokens[1].deviceId).assertEqual('b');
      }
    });

    it('unknownFallbackBridgeMergesEveryMatchingSourceComponent', 0, () => {
      const netease = song(1, 'Song', 'netease album', 'Artist', null, null,
        'https://netease.invalid/audio', 0, [token('netease', 1)]);
      const bilibili = song(1, 'Song', 'bilibili album', 'Artist', null, null,
        'https://bilibili.invalid/audio', 0, [token('bilibili', 1)]);
      const unknown = song(1, 'Song', 'legacy album', 'Artist', null, null,
        'https://legacy.invalid/audio', 0, [token('legacy', 1)]);
      const lists = [
        [netease, bilibili, unknown],
        [bilibili, netease, unknown]
      ];
      for (const songs of lists) {
        const result = deduplicateSongs(songs);
        expect(result.length).assertEqual(1);
        expect(result[0].syncMembershipTokens.length).assertEqual(3);
        expect(result[0].syncMembershipTokens[0].deviceId).assertEqual('bilibili');
        expect(result[0].syncMembershipTokens[1].deviceId).assertEqual('legacy');
        expect(result[0].syncMembershipTokens[2].deviceId).assertEqual('netease');
      }
    });
  });

  describe('PlaylistSongDeduplication', () => {
    it('duplicateSongsInSameSnapshotAreCollapsed', 0, () => {
      const first = song(1, 'Song');
      const duplicate = song(1, 'Song');
      const result = deduplicateSongs([first, duplicate]);
      expectSongs(result, [first]);
    });

    it('singleSongMembershipTokensAreNormalizedDeterministically', 0, () => {
      const single = song(1, 'Song', '', '', null, null, null, 0, [
        token('b', 1), token('a', 2), token('a', 1), token('a', 2)
      ]);
      const result = deduplicateSongs([single]);
      expectSongs(result, [withTokens(single, [token('a', 1), token('a', 2), token('b', 1)])]);
    });

    it('exactDuplicateSongsUnionMembershipTokensAndKeepFirstMetadata', 0, () => {
      const first = song(1, 'Local metadata', '', '', null, null, null, 0,
        [token('b', 1), token('a', 100)]);
      const duplicate = song(1, 'Remote metadata', '', '', null, null, null, 0,
        [token('b', 1), token('c', 1)]);
      const result = deduplicateSongs([first, duplicate]);
      expect(result.length).assertEqual(1);
      expect(result[0].name).assertEqual('Local metadata');
      expect(result[0].syncMembershipTokens.length).assertEqual(3);
      expect(result[0].syncMembershipTokens[0].deviceId).assertEqual('a');
      expect(result[0].syncMembershipTokens[0].counter).assertEqual(100);
      expect(result[0].syncMembershipTokens[1].deviceId).assertEqual('b');
      expect(result[0].syncMembershipTokens[2].deviceId).assertEqual('c');
    });
  });

  describe('PlaylistSongConcurrentMerge', () => {
    it('concurrentDisjointListsMergeWithoutDroppingSongsWhenLocalIsNewer', 0, () => {
      const localSongs: SyncSong[] = [];
      const remoteSongs: SyncSong[] = [];
      for (let index = 1; index <= 2000; index++) {
        localSongs.push(song(index, `Local ${index}`));
      }
      for (let index = 2001; index <= 4000; index++) {
        remoteSongs.push(song(index, `Remote ${index}`));
      }
      const result = mergeSongs(localSongs, remoteSongs, 300, 200, true, true, 100, false);
      expect(result.songs.length).assertEqual(4000);
      expect(result.songs[0].id).assertEqual(1);
      expect(result.songs[0].name).assertEqual('Local 1');
      expect(result.songs[3999].id).assertEqual(4000);
      expect(result.songs[3999].name).assertEqual('Remote 4000');
    });

    it('concurrentRemotePrimaryKeepsLocalOnlySongsAndRemoteMatchingPayload', 0, () => {
      const localCommon = song(1, 'Old title', '', '', null, null, null, 0, [token('local', 1)]);
      const localOnly = song(2, 'Local only', '', '', null, null, null, 0, [token('local', 2)]);
      const remoteCommon = song(1, 'New title', '', '', null, null, null, 0, [token('remote', 1)]);
      const remoteOnly = song(3, 'Remote only', '', '', null, null, null, 0, [token('remote', 3)]);

      const result = mergeSongs([localCommon, localOnly], [remoteCommon, remoteOnly],
        200, 300, true, true, 100, false);
      expectNumbers(songIds(result.songs), [1, 3, 2]);
      expect(result.songs[0].name).assertEqual('New title');
      expect(result.songs[0].syncMembershipTokens.length).assertEqual(2);
      expect(result.songs[0].syncMembershipTokens[0].deviceId).assertEqual('local');
      expect(result.songs[0].syncMembershipTokens[1].deviceId).assertEqual('remote');
    });

    it('twoChangedEndpointsResolveExactDuplicatePayloadDeterministically', 0, () => {
      const local = song(1, 'Local metadata', '', '', null, null, null, 0, [token('local', 1)]);
      local.customName = 'Stale local title';
      const remote = song(1, 'Remote metadata', '', '', null, null, null, 0, [token('remote', 1)]);
      const result = mergeSongs([local], [remote], 200, 200, true, true, 100, false);
      expect(result.songs.length).assertEqual(1);
      // Deterministic canonical key picks the lexicographically larger payload
      // on both endpoints regardless of which side supplied it.
      expect(result.songs[0].name).assertEqual('Remote metadata');
      expect(result.songs[0].customName).assertNull();
      expect(result.songs[0].syncMembershipTokens.length).assertEqual(2);
    });
  });
}

function withMedia(base: SyncSong, mediaUri: string): SyncSong {
  const copy = cloneSyncSong(base);
  copy.mediaUri = mediaUri;
  return copy;
}
