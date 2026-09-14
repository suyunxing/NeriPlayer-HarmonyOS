import { describe, it, expect } from '@ohos/hypium';
import {
  SyncData,
  SyncSong,
  SyncPlaylist,
  SyncRecentPlay,
  SyncRecentPlayDeletion,
  SyncPlaylistSongDeletion,
  SyncFavoritePlaylist,
  SyncLogEntry,
  SyncAction,
  SyncCausalToken,
  SyncTrackStat,
  SyncPlaybackStatBucket,
  SyncPlaybackCounterShard,
  syncSongEquals
} from '../../../main/ets/sync/SyncModels';
import {
  encodeSyncDataProto,
  serializeSyncDataBinary,
  decodeProtoSyncDataWithLegacyFallback
} from '../../../main/ets/sync/SyncDataProtoCodec';
import { gunzip } from '../../../main/ets/sync/GzipInflate';
import { gzipCompress } from '../../../main/ets/sync/GzipDeflate';
import { serializeSyncDataJson } from '../../../main/ets/sync/SyncDataJsonCodec';

const BIG_NEGATIVE_ID_TEXT = '-6910934312082985118';

function richSong(index: number): SyncSong {
  return new SyncSong(
    index,
    `Song ${index}`,
    '艺术家',
    'Album',
    index,
    200000 + index,
    `https://p.example/${index}.jpg`,
    null,
    1735689600000 + index,
    '[00:00.00]词',
    null,
    'netease',
    `${index}`,
    120,
    null, null, null, null, null, null, null, null,
    'netease',
    `${123456 + index}`,
    null,
    `pl-${index}`,
    [new SyncCausalToken(`dev-${index % 3}`, index + 1)],
    1,
    index % 2 === 0 ? 1735689500000 + index : null,
    ''
  );
}

function bigIdYtmSong(): SyncSong {
  const song = new SyncSong(1.234567890123e18, 'YTM', 'Artist', 'youtube_music');
  song.mediaUri = 'youtube_music|dQw4w9WgXcQ';
  song.channelId = 'youtube_music';
  song.audioId = 'dQw4w9WgXcQ';
  song.syncIdText = '6875601686285462142';
  return song;
}

function buildRichSyncData(): SyncData {
  const data = new SyncData('2.0', 'dev-1', 'HarmonyOS Device', 1735689900000);
  const playlist = new SyncPlaylist(7, '我的歌单', [richSong(1), bigIdYtmSong()],
    1735689600000, 1735689800000, false, 1);
  data.playlists.push(playlist);
  const favorite = new SyncFavoritePlaylist(9, '收藏的歌单', 'https://p.example/c.jpg',
    12, 'youtube_music', [richSong(2)], 1735689700000);
  data.favoritePlaylists.push(favorite);
  data.recentPlays.push(new SyncRecentPlay(1, richSong(3), 1735689650000, 'dev-2', 45000));
  data.syncLog.push(new SyncLogEntry(1735689660000, 'dev-1', SyncAction.ADD_SONG, 7, null, null));
  data.recentPlayDeletions.push(new SyncRecentPlayDeletion(
    0, 'netease', null, 1735689660000, 'dev-1', BIG_NEGATIVE_ID_TEXT));
  data.playlistSongDeletions.push(new SyncPlaylistSongDeletion(
    7, 0, 'netease', 'youtube_music|x', 1735689661000, 'dev-1',
    [new SyncCausalToken('dev-1', 3)], BIG_NEGATIVE_ID_TEXT));
  const shard = new SyncPlaybackCounterShard('dev-1', 1735689600000, 30000, 3, 1735689600000, 1735689900000);
  data.playbackStats.push(new SyncTrackStat('1|netease|', 'Song', '艺术家', 'netease',
    30000, 3, 1735689900000, 1735689600000, null, 200000, null, 1, 0, 0, 0, [shard]));
  data.playbackStatBuckets.push(new SyncPlaybackStatBucket(1735689600000, '1|netease|',
    'Song', '艺术家', 'netease', 30000, 3, 1735689900000, 1735689600000, null, 200000,
    null, 1, 0, 0, 0, [shard]));
  return data;
}

function expectSongsEqual(a: SyncSong, b: SyncSong): void {
  expect(syncSongEquals(a, b)).assertTrue();
}

export default function syncProtoEncodeTest(): void {
  describe('SyncProtoEncode', () => {
    it('protoRoundTripPreservesAllSections', 0, () => {
      const data = buildRichSyncData();
      const decoded = decodeProtoSyncDataWithLegacyFallback(encodeSyncDataProto(data), 1735689900000);
      expect(decoded === null).assertFalse();
      const result = decoded as SyncData;
      expect(result.deviceId).assertEqual('dev-1');
      expect(result.deviceName).assertEqual('HarmonyOS Device');
      expect(result.lastModified).assertEqual(1735689900000);
      expect(result.playlists.length).assertEqual(1);
      expect(result.playlists[0].name).assertEqual('我的歌单');
      expect(result.playlists[0].songOrderVersion).assertEqual(1);
      expect(result.playlists[0].songs.length).assertEqual(2);
      expectSongsEqual(result.playlists[0].songs[0], data.playlists[0].songs[0]);
      // The 64-bit YTM id survives as wire-fidelity decimal text.
      expect(result.playlists[0].songs[1].syncIdText).assertEqual('6875601686285462142');
      expect(result.favoritePlaylists.length).assertEqual(1);
      expect(result.favoritePlaylists[0].trackCount).assertEqual(12);
      expect(result.recentPlays.length).assertEqual(1);
      expectSongsEqual(result.recentPlays[0].song, data.recentPlays[0].song);
      expect(result.recentPlays[0].resumePositionMs).assertEqual(45000);
      expect(result.syncLog.length).assertEqual(1);
      expect(result.syncLog[0].action).assertEqual(SyncAction.ADD_SONG);
      expect(result.syncLog[0].playlistId).assertEqual(7);
      expect(result.syncLog[0].songId).assertNull();
      expect(result.recentPlayDeletions.length).assertEqual(1);
      expect(result.recentPlayDeletions[0].syncSongIdText).assertEqual(BIG_NEGATIVE_ID_TEXT);
      expect(result.playlistSongDeletions.length).assertEqual(1);
      expect(result.playlistSongDeletions[0].syncSongIdText).assertEqual(BIG_NEGATIVE_ID_TEXT);
      expect(result.playlistSongDeletions[0].removedMembershipTokens.length).assertEqual(1);
      expect(result.playbackStats.length).assertEqual(1);
      expect(result.playbackStats[0].playCount).assertEqual(3);
      expect(result.playbackStats[0].counterShards.length).assertEqual(1);
      expect(result.playbackStatBuckets.length).assertEqual(1);
      expect(result.playbackStatBuckets[0].dayStartAt).assertEqual(1735689600000);
    });

    it('binaryRoundTripThroughGzip', 0, () => {
      const data = buildRichSyncData();
      const binary = serializeSyncDataBinary(data);
      const proto = gunzip(binary, 16 * 1024 * 1024);
      expect(proto === null).assertFalse();
      const decoded = decodeProtoSyncDataWithLegacyFallback(proto as Uint8Array, 1735689900000);
      expect(decoded === null).assertFalse();
      const result = decoded as SyncData;
      expect(result.playlists.length).assertEqual(1);
      expect(result.playlists[0].songs.length).assertEqual(2);
      expect(result.playlists[0].songs[1].syncIdText).assertEqual('6875601686285462142');
    });

    it('dataSaverBinaryIsSmallerThanJson', 0, () => {
      const data = new SyncData('2.0', 'dev-1', 'HarmonyOS Device', 1735689900000);
      for (let batch = 0; batch < 5; batch++) {
        const songs: SyncSong[] = [];
        for (let i = 0; i < 40; i++) {
          songs.push(richSong(batch * 40 + i));
        }
        data.playlists.push(new SyncPlaylist(batch, `歌单 ${batch}`, songs,
          1735689600000, 1735689800000, false, 1));
      }
      const json = serializeSyncDataJson(data);
      const binary = serializeSyncDataBinary(data);
      expect(binary.length < json.length).assertTrue();
    });

    it('gzipCompressRoundTripsArbitraryBytes', 0, () => {
      const text = new Uint8Array(1024);
      for (let i = 0; i < text.length; i++) {
        text[i] = 'a'.charCodeAt(0) + (i % 26);
      }
      const compressed = gzipCompress(text);
      expect(compressed.length < text.length).assertTrue();
      const restored = gunzip(compressed, 1024 * 1024);
      expect(restored === null).assertFalse();
      const bytes = restored as Uint8Array;
      expect(bytes.length).assertEqual(text.length);
      for (let i = 0; i < text.length; i++) {
        expect(bytes[i]).assertEqual(text[i]);
      }
    });

    it('emptySyncDataEncodesAndDecodesWithDefaults', 0, () => {
      const data = new SyncData('2.0', '', '', 0);
      const bytes = encodeSyncDataProto(data);
      expect(bytes.length).assertEqual(0);
      const decoded = decodeProtoSyncDataWithLegacyFallback(bytes, 1735689900000);
      expect(decoded === null).assertFalse();
      const result = decoded as SyncData;
      expect(result.version).assertEqual('2.0');
      expect(result.lastModified).assertEqual(1735689900000);
      expect(result.playlists.length).assertEqual(0);
    });

    it('nullAndEmptyStringFieldsStayDistinct', 0, () => {
      // coverUrl null vs '' must survive the round trip separately.
      const emptyCover = richSong(5);
      emptyCover.coverUrl = '';
      const data = new SyncData('2.0', 'dev-1', '', 1);
      data.playlists.push(new SyncPlaylist(1, 'L', [emptyCover], 1, 1, false, 1));
      const decoded = decodeProtoSyncDataWithLegacyFallback(encodeSyncDataProto(data), 1);
      expect(decoded === null).assertFalse();
      const song = (decoded as SyncData).playlists[0].songs[0];
      expect(song.coverUrl).assertEqual('');
      expect(song.matchedTranslatedLyric).assertNull();
    });
  });
}
