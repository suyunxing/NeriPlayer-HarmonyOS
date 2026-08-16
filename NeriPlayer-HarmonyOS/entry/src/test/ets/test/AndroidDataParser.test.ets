import { describe, it, expect } from '@ohos/hypium';
import { AndroidDataParser, SyncPendingState } from '../../../main/ets/data/AndroidDataParser';
import { SongItem } from '../../../main/ets/model/SongItem';
import { MusicPlatform } from '../../../main/ets/model/MusicPlatform';
import { stableKeyOf, songIdentity, SongIdentity } from '../../../main/ets/model/SongIdentity';

// Gson-shaped fixture taken from the Android test suite
// (PlayHistoryRepositoryPolicyTest / LocalPlaylistRepositoryTest).
const HISTORY_FIXTURE = `[
  {"id":123,"name":"Song A","artist":"Artist","album":"netease","albumId":7,
   "durationMs":200000,"resumePositionMs":45000,"coverUrl":"https://p.example/1.jpg",
   "mediaUri":null,"playedAt":1735689600000},
  {"id":456,"name":"Song B","artist":"Other","album":"Album B","albumId":8,
   "durationMs":180000,"coverUrl":null,"mediaUri":"youtube_music|v=abc","playedAt":1735689700000}
]`;

const PLAYLISTS_FIXTURE = `[
  {"id":3,"name":"My List","modifiedAt":1735689900000,"songOrderVersion":1,
   "customCoverUrl":"https://p.example/cover.jpg",
   "songs":[
     {"id":123,"name":"Song A","artist":"Artist","album":"netease","albumId":7,
      "durationMs":200000,"channelId":"netease","audioId":"123","addedAt":1735689600000}
   ]}
]`;

export default function androidDataParserTest(): void {
  describe('AndroidDataParser', () => {
    it('parsesAndroidHistoryFixture', 0, () => {
      const songs = AndroidDataParser.parseHistory(HISTORY_FIXTURE);
      expect(songs !== null).assertTrue();
      expect(songs!.length).assertEqual(2);
      expect(songs![0].id).assertEqual(123);
      expect(songs![0].name).assertEqual('Song A');
      expect(songs![0].album).assertEqual('netease');
      expect(songs![0].durationMs).assertEqual(200000);
      // playedAt maps to addedAt; null mediaUri becomes ''.
      expect(songs![0].addedAt).assertEqual(1735689600000);
      expect(songs![0].mediaUri).assertEqual('');
      expect(songs![1].mediaUri).assertEqual('youtube_music|v=abc');
    });

    it('parsesAndroidPlaylistFixture', 0, () => {
      const playlists = AndroidDataParser.parsePlaylists(PLAYLISTS_FIXTURE);
      expect(playlists !== null).assertTrue();
      expect(playlists!.length).assertEqual(1);
      const playlist = playlists![0];
      expect(playlist.id).assertEqual('3');
      expect(playlist.name).assertEqual('My List');
      expect(playlist.coverUrl).assertEqual('https://p.example/cover.jpg');
      expect(playlist.updatedAt).assertEqual(1735689900000);
      expect(playlist.songs.length).assertEqual(1);
      expect(playlist.songs[0].name).assertEqual('Song A');
      // Membership keys derived from the imported songs.
      expect(playlist.songKeys.length).assertEqual(1);
      expect(playlist.songKeys[0]).assertEqual('123|netease|');
    });

    it('rejectsCorruptedPayloads', 0, () => {
      expect(AndroidDataParser.parseHistory('not json {')).assertNull();
      expect(AndroidDataParser.parseHistory('{"songs":1}')).assertNull();
      expect(AndroidDataParser.parsePlaylists('oops')).assertNull();
      expect(AndroidDataParser.parsePlaylists('{"not":"an array"}')).assertNull();
      expect(SyncPendingState.fromJson('{bad json').length).assertEqual(0);
      expect(SyncPendingState.fromJson('{}').length).assertEqual(0);
    });
  });

  describe('SyncPendingState', () => {
    it('marksClearsAndRoundTripsIds', 0, () => {
      let ids: string[] = [];
      ids = SyncPendingState.markPending(ids, 'favorites');
      ids = SyncPendingState.markPending(ids, 'local_1');
      ids = SyncPendingState.markPending(ids, 'favorites');
      expect(ids.length).assertEqual(2);
      expect(SyncPendingState.isPending(ids, 'favorites')).assertTrue();
      expect(SyncPendingState.isPending(ids, 'local_2')).assertFalse();

      const restored = SyncPendingState.fromJson(SyncPendingState.toJson(ids));
      expect(restored.length).assertEqual(2);
      expect(restored[0]).assertEqual('favorites');

      ids = SyncPendingState.clearPending(ids, 'favorites');
      expect(ids.length).assertEqual(1);
    });
  });

  describe('SongStableKey', () => {
    it('matchesAndroidKeyFormat', 0, () => {
      // Android PlayHistoryRepositoryPolicyTest uses "123|netease|".
      const identity = new SongIdentity(123, 'netease', '');
      expect(identity.stableKey()).assertEqual('123|netease|');

      const song = new SongItem(123, 'Song A', 'Artist', 'netease', 7);
      song.audioId = '123';
      song.channelId = 'netease';
      expect(stableKeyOf(song)).assertEqual('123|netease|');
    });

    it('normalizesYouTubeMusicIdentity', 0, () => {
      const song = new SongItem(0, 'YTM Song', 'Artist', 'Album', 0);
      song.mediaUri = 'youtube_music|v=abc123';
      const identity = songIdentity(song);
      expect(identity.album).assertEqual('youtube_music');
      expect(identity.mediaUri).assertEqual('youtube_music|v=abc123');
      // Same video id maps to the same hashed id regardless of other fields.
      const other = new SongItem(999, 'Other', 'X', 'Y', 0);
      other.mediaUri = 'youtube_music|v=abc123';
      expect(songIdentity(other).id).assertEqual(identity.id);
    });

    it('fallsBackToLocalSongIdentity', 0, () => {
      const local = new SongItem(5, 'Local', 'A', 'MyAlbum', 0);
      local.platform = MusicPlatform.LOCAL;
      const identity = songIdentity(local);
      expect(identity.stableKey()).assertEqual('5|MyAlbum|');
    });
  });
}
