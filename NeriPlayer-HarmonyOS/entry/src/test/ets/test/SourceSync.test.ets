import { describe, it, expect } from '@ohos/hypium';
import { Playlist } from '../../../main/ets/model/Playlist';
import { SongItem } from '../../../main/ets/model/SongItem';
import { MusicPlatform } from '../../../main/ets/model/MusicPlatform';
import { stableKeyOf } from '../../../main/ets/model/SongIdentity';
import {
  PlaylistSyncSource,
  SOURCE_SYNC_MODE_MIRROR,
  SOURCE_SYNC_MODE_APPEND,
  mirrorPlaylistId
} from '../../../main/ets/sourcesync/SourceSyncModels';
import { appendDiff, mirrorDiff } from '../../../main/ets/sourcesync/SourceSyncDiff';
import { playlistIdToSync } from '../../../main/ets/sync/SyncSongConvert';

function neteaseSong(id: number, name: string): SongItem {
  const item = new SongItem(id, name, '歌手', '专辑', id * 10, 100, `https://p/${id}.jpg`, '', MusicPlatform.NETEASE);
  item.channelId = 'netease';
  item.audioId = `${id}`;
  return item;
}

function biliSong(bvid: string, name: string): SongItem {
  const item = new SongItem(0, name, 'UP主', 'Bilibili', 0, 200, `https://p/${bvid}.jpg`, '', MusicPlatform.BILIBILI);
  item.channelId = 'bilibili';
  item.audioId = bvid;
  return item;
}

function neteaseSource(remoteId: string, mode: string = SOURCE_SYNC_MODE_MIRROR): PlaylistSyncSource {
  return new PlaylistSyncSource(MusicPlatform.NETEASE, remoteId, '云歌单', mode);
}

export default function sourceSyncTest(): void {
  describe('SourceSync', () => {
    // ---------- SourceSyncModels ----------

    it('syncSourceRoundtripKeepsAllFields', 0, () => {
      const source = neteaseSource('12345');
      source.lastSyncAt = 111;
      source.lastCheckedAt = 222;
      source.lastFingerprint = 'fp-1';
      source.skipKeys = ['k1', 'k2'];
      const parsed = PlaylistSyncSource.fromJson(JSON.parse(source.toJson()) as Object);
      expect(parsed === null).assertFalse();
      if (parsed === null) {
        return;
      }
      expect(parsed.platform).assertEqual(MusicPlatform.NETEASE);
      expect(parsed.remoteId).assertEqual('12345');
      expect(parsed.remoteName).assertEqual('云歌单');
      expect(parsed.mode).assertEqual(SOURCE_SYNC_MODE_MIRROR);
      expect(parsed.enabled).assertTrue();
      expect(parsed.lastSyncAt).assertEqual(111);
      expect(parsed.lastCheckedAt).assertEqual(222);
      expect(parsed.lastFingerprint).assertEqual('fp-1');
      expect(parsed.skipKeys.length).assertEqual(2);
      expect(parsed.skipKeys[1]).assertEqual('k2');
    });

    it('syncSourceRejectsMissingAndNormalizesMode', 0, () => {
      expect(PlaylistSyncSource.fromJson(null) === null).assertTrue();
      const broken = new PlaylistSyncSource(MusicPlatform.NETEASE, '', '无id');
      expect(PlaylistSyncSource.fromJson(JSON.parse(broken.toJson()) as Object) === null).assertTrue();
      const weird = new PlaylistSyncSource(MusicPlatform.BILIBILI, '42', '夹', 'bogus-mode');
      const parsed = PlaylistSyncSource.fromJson(JSON.parse(weird.toJson()) as Object);
      expect(parsed === null).assertFalse();
      if (parsed !== null) {
        expect(parsed.mode).assertEqual(SOURCE_SYNC_MODE_MIRROR);
      }
    });

    it('mirrorPlaylistIdIsDeterministicAndPlatformScoped', 0, () => {
      const netease = mirrorPlaylistId(MusicPlatform.NETEASE, '123');
      expect(netease).assertEqual(mirrorPlaylistId(MusicPlatform.NETEASE, '123'));
      expect(netease === mirrorPlaylistId(MusicPlatform.BILIBILI, '123')).assertFalse();
      expect(netease === mirrorPlaylistId(MusicPlatform.NETEASE, '124')).assertFalse();
      // Cross-device convergence: the deterministic id maps to one sync id.
      expect(playlistIdToSync(netease)).assertEqual(playlistIdToSync(mirrorPlaylistId(MusicPlatform.NETEASE, '123')));
    });

    it('playlistParsesLegacySnapshotWithoutSyncSource', 0, () => {
      const playlist = new Playlist('local_1', '旧歌单');
      playlist.songKeys = [stableKeyOf(neteaseSong(1, 'A'))];
      playlist.songs = [neteaseSong(1, 'A')];
      const withoutField = playlist.toJson().replace('"syncSource":null', '');
      const parsed = Playlist.fromJson(withoutField);
      expect(parsed.syncSource === null).assertTrue();
      expect(parsed.songKeys.length).assertEqual(1);
      expect(parsed.songs.length).assertEqual(1);
    });

    it('playlistRoundtripsWithSyncSource', 0, () => {
      const playlist = new Playlist(mirrorPlaylistId(MusicPlatform.BILIBILI, '77'), 'B站夹');
      playlist.syncSource = new PlaylistSyncSource(MusicPlatform.BILIBILI, '77', 'B站夹', SOURCE_SYNC_MODE_APPEND);
      playlist.syncSource.skipKeys = ['sk'];
      const parsed = Playlist.fromJson(playlist.toJson());
      expect(parsed.syncSource === null).assertFalse();
      if (parsed.syncSource !== null) {
        expect(parsed.syncSource.remoteId).assertEqual('77');
        expect(parsed.syncSource.mode).assertEqual(SOURCE_SYNC_MODE_APPEND);
        expect(parsed.syncSource.skipKeys.length).assertEqual(1);
      }
      expect(parsed.id).assertEqual(mirrorPlaylistId(MusicPlatform.BILIBILI, '77'));
    });

    // ---------- mirrorDiff ----------

    it('mirrorDiffAddsNewAndRemovesGone', 0, () => {
      const a = neteaseSong(1, 'A');
      const b = neteaseSong(2, 'B');
      const c = neteaseSong(3, 'C');
      const localKeys = [stableKeyOf(a), stableKeyOf(b)];
      const diff = mirrorDiff(localKeys, [b, c], []);
      expect(diff.toAdd.length).assertEqual(1);
      expect(diff.toAdd[0].name).assertEqual('C');
      expect(diff.toRemoveKeys.length).assertEqual(1);
      expect(diff.toRemoveKeys[0]).assertEqual(stableKeyOf(a));
      expect(diff.changed).assertTrue();
      expect(diff.finalOrder.length).assertEqual(2);
      expect(diff.finalOrder[0]).assertEqual(stableKeyOf(b));
    });

    it('mirrorDiffNeverReAddsSkippedSongs', 0, () => {
      const a = neteaseSong(1, 'A');
      const b = neteaseSong(2, 'B');
      const skipped = neteaseSong(3, 'S');
      const localKeys = [stableKeyOf(a), stableKeyOf(b)];
      const diff = mirrorDiff(localKeys, [a, b, skipped], [stableKeyOf(skipped)]);
      expect(diff.toAdd.length).assertEqual(0);
      expect(diff.toRemoveKeys.length).assertEqual(0);
      expect(diff.changed).assertFalse();
      expect(diff.finalOrder.length).assertEqual(2);
    });

    it('mirrorDiffRemovesSongsGoneFromRemote', 0, () => {
      const a = neteaseSong(1, 'A');
      const b = neteaseSong(2, 'B');
      const localKeys = [stableKeyOf(a), stableKeyOf(b)];
      const diff = mirrorDiff(localKeys, [b], []);
      expect(diff.toAdd.length).assertEqual(0);
      expect(diff.toRemoveKeys.length).assertEqual(1);
      expect(diff.changed).assertTrue();
      expect(diff.finalOrder.length).assertEqual(1);
    });

    it('mirrorDiffDetectsPureReorder', 0, () => {
      const a = neteaseSong(1, 'A');
      const b = neteaseSong(2, 'B');
      const localKeys = [stableKeyOf(a), stableKeyOf(b)];
      const diff = mirrorDiff(localKeys, [b, a], []);
      expect(diff.toAdd.length).assertEqual(0);
      expect(diff.toRemoveKeys.length).assertEqual(0);
      expect(diff.changed).assertTrue();
      expect(diff.finalOrder[0]).assertEqual(stableKeyOf(b));
    });

    it('mirrorDiffUnchangedWhenRemoteMatchesLocal', 0, () => {
      const a = neteaseSong(1, 'A');
      const b = neteaseSong(2, 'B');
      const localKeys = [stableKeyOf(a), stableKeyOf(b)];
      const diff = mirrorDiff(localKeys, [a, b], []);
      expect(diff.changed).assertFalse();
      expect(diff.toAdd.length).assertEqual(0);
    });

    it('mirrorDiffDedupesRemoteBatch', 0, () => {
      const a = neteaseSong(1, 'A');
      const diff = mirrorDiff([], [a, neteaseSong(1, 'A-again')], []);
      expect(diff.toAdd.length).assertEqual(1);
      expect(diff.toAdd[0].name).assertEqual('A');
      expect(diff.finalOrder.length).assertEqual(1);
    });

    it('mirrorDiffHandlesBiliSource', 0, () => {
      const video = biliSong('BV1x', '视频');
      const diff = mirrorDiff([], [video], []);
      expect(diff.toAdd.length).assertEqual(1);
      expect(diff.finalOrder.length).assertEqual(1);
      expect(diff.finalOrder[0]).assertEqual(stableKeyOf(video));
    });

    // ---------- appendDiff ----------

    it('appendDiffOnlyAddsMissingAndRespectsSkips', 0, () => {
      const a = neteaseSong(1, 'A');
      const b = neteaseSong(2, 'B');
      const c = neteaseSong(3, 'C');
      const localKeys = [stableKeyOf(a)];
      const diff = appendDiff(localKeys, [a, b, c], [stableKeyOf(c)]);
      expect(diff.toAdd.length).assertEqual(1);
      expect(diff.toAdd[0].name).assertEqual('B');
      expect(diff.changed).assertTrue();
      expect(diff.toRemoveKeys.length).assertEqual(0);
      expect(diff.finalOrder.length).assertEqual(0);
    });

    it('appendDiffUnchangedWhenNothingNew', 0, () => {
      const a = neteaseSong(1, 'A');
      const diff = appendDiff([stableKeyOf(a)], [a, a], []);
      expect(diff.changed).assertFalse();
      expect(diff.toAdd.length).assertEqual(0);
    });
  });
}
