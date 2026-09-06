import { describe, it, expect } from '@ohos/hypium';
import { SongItem } from '../../../main/ets/model/SongItem';
import { Playlist } from '../../../main/ets/model/Playlist';
import { MusicPlatform } from '../../../main/ets/model/MusicPlatform';
import {
  SyncRecentPlayDeletion,
  SyncPlaylistSongDeletion,
  SyncPlaybackCounterShard
} from '../../../main/ets/sync/SyncModels';
import {
  SyncSnapshotInput,
  SnapshotPlaylistInput,
  SnapshotDeletedPlaylistInput,
  SnapshotRecentPlayInput,
  SnapshotTrackStatInput,
  SnapshotBucketInput,
  buildLocalSyncData,
  syncTrackStatFromInput,
  localDayStartAt
} from '../../../main/ets/sync/SyncSnapshotBuilder';
import { token } from './SongMetadataMergePolicy.test';

function remoteSong(id: number): SongItem {
  const song = new SongItem(id, `Song ${id}`, 'Artist', 'netease', 0, 200000,
    '', 'netease://x', MusicPlatform.NETEASE);
  song.channelId = 'netease';
  song.audioId = `${id}`;
  return song;
}

function localSong(id: number): SongItem {
  return new SongItem(id, `Local ${id}`, 'Artist', 'album', 0, 0, '', '/sdcard/a.mp3',
    MusicPlatform.LOCAL);
}

export default function syncSnapshotBuilderTest(): void {
  describe('SnapshotPlaylists', () => {
    it('keepsRepositoryOrderAndAppendsMissingTombstones', 0, () => {
      const input = new SyncSnapshotInput('device-a', 'Test Device');
      const first = new Playlist('local_100', 'A', MusicPlatform.LOCAL);
      first.songs.push(remoteSong(1));
      const second = new Playlist('200', 'B', MusicPlatform.LOCAL);
      input.playlists.push(new SnapshotPlaylistInput(first, 111));
      input.playlists.push(new SnapshotPlaylistInput(second, 222));
      input.deletedPlaylists.push(new SnapshotDeletedPlaylistInput(100, 999));
      input.deletedPlaylists.push(new SnapshotDeletedPlaylistInput(300, 888));

      const data = buildLocalSyncData(input, 1000);
      // Tombstone for id 100 is NOT appended (live playlist with same id).
      expect(data.playlists.length).assertEqual(3);
      expect(data.playlists[0].id).assertEqual(100);
      expect(data.playlists[0].isDeleted).assertFalse();
      expect(data.playlists[1].id).assertEqual(200);
      expect(data.playlists[2].id).assertEqual(300);
      expect(data.playlists[2].isDeleted).assertTrue();
      expect(data.playlists[2].songs.length).assertEqual(0);
      expect(data.playlists[2].modifiedAt).assertEqual(888);
    });
  });

  describe('SnapshotRecentPlays', () => {
    it('dropsLocalSongsThenCapsAtFiveHundred', 0, () => {
      const input = new SyncSnapshotInput('device-a', 'Test Device');
      input.recentPlays.push(new SnapshotRecentPlayInput(localSong(0), 5, 0));
      for (let i = 1; i <= 502; i++) {
        input.recentPlays.push(new SnapshotRecentPlayInput(remoteSong(i), 1000 - i, 120));
      }
      const data = buildLocalSyncData(input, 2000);
      expect(data.recentPlays.length).assertEqual(500);
      // The local song never occupies a slot; first kept entry is remote id 1.
      expect(data.recentPlays[0].song.id).assertEqual(1);
      expect(data.recentPlays[0].playedAt).assertEqual(999);
      expect(data.recentPlays[0].deviceId).assertEqual('device-a');
      expect(data.recentPlays[0].resumePositionMs).assertEqual(120);
      expect(data.recentPlays[499].song.id).assertEqual(500);
    });
  });

  describe('SnapshotStats', () => {
    it('derivesCounterBasesAndNormalizesShards', 0, () => {
      const shards = [
        new SyncPlaybackCounterShard('device-a', 0, 300, 1, 250, 300),
        new SyncPlaybackCounterShard('device-a', 0, 100, 2, 260, 320),
        new SyncPlaybackCounterShard(' ', 0, 50, 1, 1, 2)
      ];
      const entry = new SnapshotTrackStatInput('123|netease|', 'song', 'artist', 'album',
        2300, 11, 300, 100, 'https://cover', 200000, 'netease://x', 123, 45, shards);
      const stat = syncTrackStatFromInput(entry);
      // Normalized shards: invalid device dropped, (device, epoch) merged
      // with max() per mergeCounterShard → listen 300 / plays 2.
      expect(stat.counterBaseListenMs).assertEqual(2000);
      expect(stat.counterBasePlayCount).assertEqual(9);
      expect(stat.counterShards.length).assertEqual(1);
      expect(stat.counterShards[0].totalListenMs).assertEqual(300);
      expect(stat.counterShards[0].playCount).assertEqual(2);
    });

    it('sanitizesLocalMediaUriInBucketsAndDeletions', 0, () => {
      const input = new SyncSnapshotInput('device-a', 'Test Device');
      const bucketStat = new SnapshotTrackStatInput('k', 'n', 'a', 'b', 100, 1, 10, 5,
        null, 0, '/local/file', 0, 0);
      input.playbackStatBuckets.push(new SnapshotBucketInput(86400000, bucketStat));
      input.recentPlayDeletions.push(new SyncRecentPlayDeletion(1, 'album', '/local/file', 9, 'd'));
      input.playlistSongDeletions.push(new SyncPlaylistSongDeletion(7, 1, 'album', null, 9, 'd',
        [token('x', 1), token('x', 0)]));

      const data = buildLocalSyncData(input, 3000);
      expect(data.playbackStatBuckets[0].mediaUri).assertNull();
      expect(data.recentPlayDeletions[0].mediaUri).assertNull();
      expect(data.playlistSongDeletions[0].removedMembershipTokens.length).assertEqual(1);
    });

    it('copiesTopLevelIdentityAndClearsSyncLog', 0, () => {
      const input = new SyncSnapshotInput('device-b', 'HarmonyOS Phone');
      input.playbackStatsClearedAt = 4321;
      const data = buildLocalSyncData(input, 7777);
      expect(data.version).assertEqual('2.0');
      expect(data.deviceId).assertEqual('device-b');
      expect(data.deviceName).assertEqual('HarmonyOS Phone');
      expect(data.lastModified).assertEqual(7777);
      expect(data.syncLog.length).assertEqual(0);
      expect(data.playbackStatsClearedAt).assertEqual(4321);
    });
  });

  describe('LocalDayStart', () => {
    it('floorsToLocalMidnightNotUtc', 0, () => {
      const anyAfternoon = new Date(2026, 7, 15, 13, 45, 30, 500).getTime();
      const start = localDayStartAt(anyAfternoon);
      expect(start <= anyAfternoon).assertTrue();
      expect(anyAfternoon - start < 86400000).assertTrue();
      expect(start + 86400000 > anyAfternoon).assertTrue();
      const midnight = new Date(2026, 7, 15).getTime();
      expect(start).assertEqual(midnight);
    });
  });
}
