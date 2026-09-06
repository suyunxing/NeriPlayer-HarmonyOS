import { describe, it, expect } from '@ohos/hypium';
import { SongItem } from '../../../main/ets/model/SongItem';
import {
  PlaybackStatsRepository,
  StatsRoot
} from '../../../main/ets/data/PlaybackStatsRepository';
import { FavoritePlaylistRepository } from '../../../main/ets/data/FavoritePlaylistRepository';
import {
  SyncCausalToken,
  SyncData,
  SyncFavoritePlaylist,
  SyncPlaybackCounterShard,
  SyncSong
} from '../../../main/ets/sync/SyncModels';
import {
  songItemFromSyncSong,
  syncSongFromSongItem
} from '../../../main/ets/sync/SyncSongConvert';
import { serializeSyncDataJson, utf8Decode } from '../../../main/ets/sync/SyncDataJsonCodec';

export default function syncLocalMetadataTest(): void {
  describe('SyncLocalMetadata', () => {
    it('preservesMembershipTokensAndExactIdThroughSongItemStorage', 0, () => {
      const syncSong = new SyncSong(9007199254740992, 'Song', 'Artist', 'Album');
      syncSong.syncIdText = '9007199254740993';
      syncSong.syncMembershipTokens = [new SyncCausalToken('device-a', 7)];
      const stored = SongItem.fromJson(songItemFromSyncSong(syncSong).toJson());
      const restored = syncSongFromSongItem(stored) as SyncSong;

      expect(restored.syncIdText).assertEqual('9007199254740993');
      expect(restored.syncMembershipTokens.length).assertEqual(1);
      expect(restored.syncMembershipTokens[0].deviceId).assertEqual('device-a');
      expect(restored.syncMembershipTokens[0].counter).assertEqual(7);
    });

    it('migratesLegacyDailyNumbersAndReadsCounterShards', 0, () => {
      const json = '{"tracks":{"id":{"playCount":3,"listenMs":30,' +
        '"counterShards":[{"deviceId":"a","epochStartedAt":1,' +
        '"totalListenMs":20,"playCount":2,"firstPlayedAt":2,"lastPlayedAt":3}]}},' +
        '"daily":{"2026-08-19":{"id":10}},"clearedAt":1}';
      const parsed = PlaybackStatsRepository.parseJson(json) as StatsRoot;
      expect(parsed.tracks['id'].counterShards.length).assertEqual(1);
      expect(parsed.daily['2026-08-19']['id'].listenMs).assertEqual(10);
      expect(parsed.daily['2026-08-19']['id'].playCount).assertEqual(0);
    });

    it('roundTripsFavoritePlaylistSyncPayload', 0, () => {
      const favorite = new SyncFavoritePlaylist(7, 'Saved', null, 1, 'netease',
        [new SyncSong(1, 'Song')], 10, 11, false, 12, null, 'playlist-id', 'subtitle');
      const data = new SyncData();
      data.favoritePlaylists = [favorite];
      const parsed = FavoritePlaylistRepository.parse(utf8Decode(serializeSyncDataJson(data)));
      expect(parsed !== null).assertTrue();
      expect((parsed as SyncFavoritePlaylist[])[0].playlistId).assertEqual('playlist-id');
      expect((parsed as SyncFavoritePlaylist[])[0].songs.length).assertEqual(1);
    });

    it('keepsCounterShardFieldsInJsonSerialization', 0, () => {
      const shard = new SyncPlaybackCounterShard('device', 1, 2, 3, 4, 5);
      expect(JSON.stringify(shard).includes('"playCount":3')).assertTrue();
    });
  });
}
