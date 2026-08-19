import { describe, it, expect } from '@ohos/hypium';
import {
  SyncData,
  SyncPlaylist,
  SyncSong,
  SyncRecentPlay,
  SyncRecentPlayDeletion,
  SyncPlaylistSongDeletion,
  SyncTrackStat,
  SyncCausalToken
} from '../../../main/ets/sync/SyncModels';
import { hasDataChanged } from '../../../main/ets/sync/DataChangeDetector';
import { token } from './SongMetadataMergePolicy.test';

function playlistSong(id: number, addedAt: number = 100): SyncSong {
  const song = new SyncSong(id, `Song ${id}`, 'Artist', 'netease', 0, 0,
    null, null, addedAt, null, null, null, null, 0, null, null, null, null, null,
    null, null, null, 'netease', `${id}`, null, null, [], 1, null);
  return song;
}

function snapshotWith(
  playlists: SyncPlaylist[] = [new SyncPlaylist(7, 'playlist', [playlistSong(1), playlistSong(2)], 0, 500)]
): SyncData {
  return new SyncData('2.0', 'device', 'name', 1000, playlists);
}

function playlistOf(data: SyncData): SyncPlaylist {
  return data.playlists[0];
}

export default function dataChangeDetectorTest(): void {
  describe('DataChangeDetectorStability', () => {
    it('identicalLargeDataIsStableNotChanged', 0, () => {
      const songs: SyncSong[] = [];
      for (let i = 1; i <= 200; i++) {
        const song = playlistSong(i, i);
        song.syncMembershipTokens = [token('device', i)];
        songs.push(song);
      }
      const remote = snapshotWith([new SyncPlaylist(7, 'playlist', songs, 0, 500)]);
      const merged = snapshotWith([new SyncPlaylist(7, 'playlist', songs, 0, 500)]);
      expect(hasDataChanged(remote, merged)).assertFalse();
    });
  });

  describe('DataChangeDetectorPlaylistChanges', () => {
    it('addedAtChangeIsDetected', 0, () => {
      const remote = snapshotWith();
      const merged = snapshotWith();
      playlistOf(merged).songs[0].addedAt = 300;
      expect(hasDataChanged(remote, merged)).assertTrue();
    });

    it('songOrderChangeIsDetected', 0, () => {
      const remote = snapshotWith();
      const merged = snapshotWith();
      const songs = playlistOf(merged).songs;
      const first = songs[0];
      songs[0] = songs[1];
      songs[1] = first;
      expect(hasDataChanged(remote, merged)).assertTrue();
    });

    it('playlistNameAndDeletionChangeIsDetected', 0, () => {
      const renamed = snapshotWith();
      playlistOf(renamed).name = 'renamed';
      expect(hasDataChanged(snapshotWith(), renamed)).assertTrue();
      const deleted = snapshotWith();
      playlistOf(deleted).isDeleted = true;
      expect(hasDataChanged(snapshotWith(), deleted)).assertTrue();
    });

    it('tokenOrderDifferenceAloneIsNotAChange', 0, () => {
      const remote = snapshotWith();
      playlistOf(remote).songs[0].syncMembershipTokens = [token('a', 1), token('b', 1)];
      const merged = snapshotWith();
      playlistOf(merged).songs[0].syncMembershipTokens = [token('b', 1), token('a', 1)];
      expect(hasDataChanged(remote, merged)).assertFalse();
    });

    it('tokenSetDifferenceAndMetadataUpgradeAreDetected', 0, () => {
      const tokenAdded = snapshotWith();
      playlistOf(tokenAdded).songs[0].syncMembershipTokens = [token('a', 1)];
      expect(hasDataChanged(snapshotWith(), tokenAdded)).assertTrue();

      const upgraded = snapshotWith();
      playlistOf(upgraded).songs[0].syncMetadataVersion = 2;
      expect(hasDataChanged(snapshotWith(), upgraded)).assertTrue();
    });
  });

  describe('DataChangeDetectorHistoryChanges', () => {
    it('recentPlayResumePositionChangeIsDetected', 0, () => {
      const remote = new SyncData('2.0', 'device', 'name', 1000, [],
        [], [new SyncRecentPlay(1, playlistSong(1), 500, 'device', 75000)]);
      const merged = new SyncData('2.0', 'device', 'name', 1000, [],
        [], [new SyncRecentPlay(1, playlistSong(1), 500, 'device', 90000)]);
      expect(hasDataChanged(remote, merged)).assertTrue();
    });

    it('recentPlayDeletionDeviceChangeIsDetected', 0, () => {
      const build = (deviceId: string): SyncData => new SyncData('2.0', 'device', 'name',
        1000, [], [], [], [], [new SyncRecentPlayDeletion(1, 'netease', null, 200, deviceId)]);
      expect(hasDataChanged(build('a'), build('b'))).assertTrue();
      expect(hasDataChanged(build('a'), build('a'))).assertFalse();
    });

    it('playlistSongDeletionRemovedTokensChangeIsDetected', 0, () => {
      const build = (tokens: SyncCausalToken[]): SyncData => new SyncData('2.0', 'device',
        'name', 1000, [], [], [], [], [], [], 0, [],
        [new SyncPlaylistSongDeletion(7, 1, 'netease', null, 200, 'device', tokens)]);
      expect(hasDataChanged(build([token('a', 1)]), build([token('a', 1)]))).assertFalse();
      expect(hasDataChanged(build([token('a', 1)]), build([token('a', 2)]))).assertTrue();
    });
  });

  describe('DataChangeDetectorStatsChanges', () => {
    it('playbackStatsCounterChangeIsDetected', 0, () => {
      const build = (listenMs: number): SyncData => new SyncData('2.0', 'device', 'name',
        1000, [], [], [], [], [], [new SyncTrackStat('k', 'name', 'artist', 'album',
        listenMs, 1, 200, 100)], 0);
      expect(hasDataChanged(build(1000), build(1000))).assertFalse();
      expect(hasDataChanged(build(1000), build(1500))).assertTrue();
    });

    it('playbackStatsClearedAtChangeIsDetected', 0, () => {
      const remote = new SyncData('2.0', 'device', 'name', 1000, [], [], [], [], [],
        [], 100);
      const merged = new SyncData('2.0', 'device', 'name', 1000, [], [], [], [], [],
        [], 200);
      expect(hasDataChanged(remote, merged)).assertTrue();
    });
  });
}
