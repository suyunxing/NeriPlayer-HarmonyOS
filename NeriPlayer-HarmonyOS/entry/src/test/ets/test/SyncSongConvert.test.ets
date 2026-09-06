import { describe, it, expect } from '@ohos/hypium';
import { SongItem } from '../../../main/ets/model/SongItem';
import { Playlist } from '../../../main/ets/model/Playlist';
import { MusicPlatform } from '../../../main/ets/model/MusicPlatform';
import {
  SyncSong,
  SyncPlaylist,
  CURRENT_SYNC_METADATA_VERSION,
  DISPLAY_ORDER_SONG_ORDER_VERSION,
  cloneSyncSong
} from '../../../main/ets/sync/SyncModels';
import { applyDeletions } from '../../../main/ets/sync/PlaylistDeletionPolicy';
import { SyncPlaylistSongDeletion } from '../../../main/ets/sync/SyncModels';
import {
  isLocalSongItem,
  sanitizeMediaUriForSync,
  syncSongFromSongItem,
  songItemFromSyncSong,
  playlistIdToSync,
  syncPlaylistIdToLocal,
  syncPlaylistFromPlaylist,
  normalizedForDisplayOrder
} from '../../../main/ets/sync/SyncSongConvert';

function neteaseSongItem(): SongItem {
  const song = new SongItem(123, '晴天', '周杰伦', '叶惠美', 45, 269000,
    'https://cover', 'netease://123', MusicPlatform.NETEASE);
  song.channelId = 'netease';
  song.audioId = '123';
  song.addedAt = 500;
  song.matchedLyric = '[00:01.00]line';
  song.customName = 'My title';
  return song;
}

export default function syncSongConvertTest(): void {
  describe('LocalSongDetection', () => {
    it('detectsLocalPlatformPathAndUri', 0, () => {
      const byPlatform = new SongItem(1, 'a', 'b', 'c', 0, 0, '', '', MusicPlatform.LOCAL);
      expect(isLocalSongItem(byPlatform)).assertTrue();
      const byPath = new SongItem(1, 'a', 'b', 'c', 0, 0, '', 'http://x', MusicPlatform.NETEASE);
      byPath.localFilePath = '/data/a.mp3';
      expect(isLocalSongItem(byPath)).assertTrue();
      const byUri = new SongItem(1, 'a', 'b', 'c', 0, 0, '', 'file://local', MusicPlatform.NETEASE);
      expect(isLocalSongItem(byUri)).assertTrue();
      expect(isLocalSongItem(neteaseSongItem())).assertFalse();
    });

    it('sanitizesLocalMediaUrisToNull', 0, () => {
      expect(sanitizeMediaUriForSync('/data/song.mp3')).assertNull();
      expect(sanitizeMediaUriForSync('content://media/1')).assertNull();
      expect(sanitizeMediaUriForSync('https://cdn/audio.m4a')).assertEqual('https://cdn/audio.m4a');
      expect(sanitizeMediaUriForSync(null)).assertNull();
    });
  });

  describe('SongItemConversion', () => {
    it('fromSongItemMapsFieldsAndSkipsLocalSongs', 0, () => {
      const sync = syncSongFromSongItem(neteaseSongItem());
      expect(sync !== null).assertTrue();
      const song = sync as SyncSong;
      expect(song.id).assertEqual(123);
      expect(song.name).assertEqual('晴天');
      expect(song.coverUrl).assertEqual('https://cover');
      expect(song.mediaUri).assertEqual('netease://123');
      expect(song.addedAt).assertEqual(500);
      expect(song.matchedLyric).assertEqual('[00:01.00]line');
      expect(song.customName).assertEqual('My title');
      expect(song.channelId).assertEqual('netease');
      expect(song.audioId).assertEqual('123');
      expect(song.syncMetadataVersion).assertEqual(CURRENT_SYNC_METADATA_VERSION);
      expect(syncSongFromSongItem(new SongItem(1, 'a', 'b', 'c', 0, 0, '', '', MusicPlatform.LOCAL))).assertNull();
    });

    it('emptyStringsBecomeNullsOnExport', 0, () => {
      const song = syncSongFromSongItem(new SongItem(1, 'a', 'b', 'c', 0, 0, '', '', MusicPlatform.NETEASE)) as SyncSong;
      expect(song.coverUrl).assertNull();
      expect(song.matchedLyric).assertNull();
      expect(song.channelId).assertNull();
    });

    it('toSongItemInfersPlatformAndRestoresStrings', 0, () => {
      const netease = songItemFromSyncSong(new SyncSong(1, 'a', 'b', 'album', 0, 0,
        null, null, 0, null, null, null, null, 0, null, null, null, null, null,
        null, null, null, 'netease', '1', null, null, [], 1, null));
      expect(netease.platform).assertEqual(MusicPlatform.NETEASE);
      const bili = songItemFromSyncSong(new SyncSong(1, 'a', 'b', 'album', 0, 0,
        null, null, 0, null, null, null, null, 0, null, null, null, null, null,
        null, null, null, 'bilibili', 'BV1', null, null, [], 1, null));
      expect(bili.platform).assertEqual(MusicPlatform.BILIBILI);
      const ytm = songItemFromSyncSong(new SyncSong(1, 'a', 'b', 'album', 0, 0,
        null, 'youtube_music|vid', 0, null, null, null, null, 0, null, null, null,
        null, null, null, null, null, null, null, null, null, [], 1, null));
      expect(ytm.platform).assertEqual(MusicPlatform.YOUTUBE_MUSIC);
      expect(netease.coverUrl).assertEqual('');
      expect(netease.matchedLyric).assertEqual('');
    });
  });

  describe('PlaylistIdConversion', () => {
    it('mapsLocalAndNumericAndForeignIds', 0, () => {
      expect(playlistIdToSync('local_1710000000000')).assertEqual(1710000000000);
      expect(playlistIdToSync('42')).assertEqual(42);
      const hashed = playlistIdToSync('custom-name');
      expect(hashed > 0).assertTrue();
      // M5.7: the reverse mapping restores the "local_" shape so an apply
      // round-trip cannot rewrite a created playlist's id string.
      expect(syncPlaylistIdToLocal(42)).assertEqual('local_42');
      expect(playlistIdToSync(syncPlaylistIdToLocal(42))).assertEqual(42);
    });
  });

  describe('PlaylistConversion', () => {
    it('fromLocalPlaylistKeepsOrderAndFiltersLocalSongs', 0, () => {
      const playlist = new Playlist('local_100', 'My List', MusicPlatform.LOCAL);
      playlist.songs.push(neteaseSongItem());
      const localSong = new SongItem(9, 'local', 'a', 'b', 0, 0, '', '/x.mp3', MusicPlatform.LOCAL);
      playlist.songs.push(localSong);
      const sync = syncPlaylistFromPlaylist(playlist, 777);
      expect(sync.id).assertEqual(100);
      expect(sync.createdAt).assertEqual(100);
      expect(sync.modifiedAt).assertEqual(777);
      expect(sync.songOrderVersion).assertEqual(DISPLAY_ORDER_SONG_ORDER_VERSION);
      expect(sync.songs.length).assertEqual(1);
      expect(sync.songs[0].id).assertEqual(123);
    });
  });

  describe('NormalizedForDisplayOrder', () => {
    it('deletedPlaylistDropsSongs', 0, () => {
      const deleted = new SyncPlaylist(7, 'x', [new SyncSong(1, 'a')], 0, 0, true, 0);
      const normalized = normalizedForDisplayOrder(deleted);
      expect(normalized.songs.length).assertEqual(0);
      expect(normalized.songOrderVersion).assertEqual(DISPLAY_ORDER_SONG_ORDER_VERSION);
    });

    it('alreadySortedDisplayPlaylistReturnsSameReference', 0, () => {
      const songs = [
        new SyncSong(1, 'a', '', '', 0, 0, null, null, 300),
        new SyncSong(2, 'b', '', '', 0, 0, null, null, 200)
      ];
      const playlist = new SyncPlaylist(7, 'x', songs, 0, 0, false, DISPLAY_ORDER_SONG_ORDER_VERSION);
      expect(normalizedForDisplayOrder(playlist) === playlist).assertTrue();
    });

    it('sortsDisplayPlaylistByAddedAtDescendingStable', 0, () => {
      const songs = [
        new SyncSong(1, 'a', '', '', 0, 0, null, null, 100),
        new SyncSong(2, 'b', '', '', 0, 0, null, null, 300),
        new SyncSong(3, 'c', '', '', 0, 0, null, null, 300)
      ];
      const playlist = new SyncPlaylist(7, 'x', songs, 0, 0, false, DISPLAY_ORDER_SONG_ORDER_VERSION);
      const normalized = normalizedForDisplayOrder(playlist);
      expect(normalized.songs[0].id).assertEqual(2);
      expect(normalized.songs[1].id).assertEqual(3);
      expect(normalized.songs[2].id).assertEqual(1);
    });

    it('legacyMigrationKeepsDeletedSongDeleted', 0, () => {
      // Android P1-1 regression: the anchor is the playlist's modifiedAt (not
      // wall clock) so identity tombstones stay effective after migration.
      const legacyPlaylist = new SyncPlaylist(7, 'legacy',
        [new SyncSong(11, 'Song', 'Artist', 'netease', 0, 0, null, null, 0)],
        0, 100, false, 0);
      const migrated = normalizedForDisplayOrder(legacyPlaylist);
      expect(migrated.songs[0].addedAt <= 100).assertTrue();
      expect(migrated.songOrderVersion).assertEqual(DISPLAY_ORDER_SONG_ORDER_VERSION);
      const survivors = applyDeletions(7, migrated.songs, [
        new SyncPlaylistSongDeletion(7, 11, 'netease', null, 200)
      ]);
      expect(survivors.length).assertEqual(0);
    });

    it('legacyMigrationPreservesOriginalAddedAtForComparisons', 0, () => {
      const legacyPlaylist = new SyncPlaylist(7, 'legacy',
        [new SyncSong(11, 'Song', 'Artist', 'netease', 0, 0, null, null, 0)],
        0, 500, false, 0);
      const migrated = normalizedForDisplayOrder(legacyPlaylist).songs[0];
      expect(migrated.legacyAddedAt).assertEqual(0);
      expect(migrated.addedAt > 0).assertTrue();
      // Removal still wins because effectiveAddedAt falls back to legacyAddedAt=0.
      const survivors = applyDeletions(7, [migrated], [
        new SyncPlaylistSongDeletion(7, 11, 'netease', null, 200)
      ]);
      expect(survivors.length).assertEqual(0);
    });

    it('legacyMigrationAnchorsAtMaxSongAddedAtWhenNewer', 0, () => {
      const songs = [
        new SyncSong(1, 'a', '', '', 0, 0, null, null, 900),
        new SyncSong(2, 'b', '', '', 0, 0, null, null, 0)
      ];
      const legacyPlaylist = new SyncPlaylist(7, 'x', songs, 0, 100, false, 0);
      const migrated = normalizedForDisplayOrder(legacyPlaylist);
      // Reverse index order: last list item gets the newest synthesized addedAt.
      expect(migrated.songs[0].id).assertEqual(2);
      expect(migrated.songs[0].addedAt).assertEqual(900);
      expect(migrated.songs[1].addedAt).assertEqual(899);
      expect(cloneSyncSong(migrated.songs[0]).addedAt).assertEqual(900);
    });
  });
}
