import { describe, it, expect } from '@ohos/hypium';
import { SongItem } from '../../../main/ets/model/SongItem';
import { MusicPlatform } from '../../../main/ets/model/MusicPlatform';
import { Playlist } from '../../../main/ets/model/Playlist';
import {
  stableKeyOf,
  songIdentity,
  parseStableSongIdentity,
  legacyFnvStableKey,
  hashStableId
} from '../../../main/ets/model/SongIdentity';
import { stableSyncId } from '../../../main/ets/sync/SyncModels';
import {
  buildLegacyKeyRemap,
  remapPlaylist,
  remapStatsRoot,
  remapCatalogEntries,
  dedupeSongsByKey
} from '../../../main/ets/data/StableKeyMigration';
import { StatsRoot, TrackStats } from '../../../main/ets/data/PlaybackStatsRepository';
import { DownloadedSongEntry } from '../../../main/ets/download/DownloadStorage';
import { matchDownloadedEntry } from '../../../main/ets/data/LocalMediaScanner';

/**
 * Cross-end fixtures (backlog §1.1). Expected values were derived with the
 * Android algorithm itself (YouTubeMusicSupport.stableYouTubeMusicId):
 * SHA-256(UTF-8(value)) first 8 bytes folded big-endian into a signed 64-bit
 * long, 0 remapped to 1; the decimal text below is that Long.toString().
 */
const YTM_VIDEO_ID: string = 'dQw4w9WgXcQ';
const YTM_VIDEO_ID_HASH: string = '6875601686285462142';
const BILI_HASH_INPUT: string = 'bilibili|170001|234567';
// Negative: exercises the two's-complement fold when digest[0] has the sign bit.
const BILI_HASH_VALUE: string = '-6910934312082985118';

function ytmSong(): SongItem {
  const song = new SongItem(0, 'YTM Song', 'Artist', 'Album', 0);
  song.platform = MusicPlatform.YOUTUBE_MUSIC;
  song.mediaUri = `youtube_music|${YTM_VIDEO_ID}`;
  return song;
}

function biliSong(): SongItem {
  const song = new SongItem(0, 'Bili Song', 'UP', 'Bilibili|234567', 0);
  song.platform = MusicPlatform.BILIBILI;
  song.channelId = 'bilibili';
  song.audioId = '170001';
  song.subAudioId = '234567';
  return song;
}

export default function songIdentitySha256Test(): void {
  describe('SongIdentitySha256', () => {
    it('stableSyncIdMatchesAndroidFixtures', 0, () => {
      expect(stableSyncId(YTM_VIDEO_ID)).assertEqual(YTM_VIDEO_ID_HASH);
      expect(stableSyncId(BILI_HASH_INPUT)).assertEqual(BILI_HASH_VALUE);
      // Deterministic and idempotent for the same input.
      expect(stableSyncId(YTM_VIDEO_ID)).assertEqual(stableSyncId(YTM_VIDEO_ID));
    });

    it('ytmSongIdentityUsesSha256Long', 0, () => {
      const identity = songIdentity(ytmSong());
      expect(identity.id).assertEqual(YTM_VIDEO_ID_HASH);
      expect(identity.album).assertEqual('youtube_music');
      expect(stableKeyOf(ytmSong()))
        .assertEqual(`${YTM_VIDEO_ID_HASH}|youtube_music|youtube_music|${YTM_VIDEO_ID}`);
    });

    it('bilibiliSongIdentityUsesChannelSeed', 0, () => {
      const identity = songIdentity(biliSong());
      expect(identity.id).assertEqual(BILI_HASH_VALUE);
      expect(stableKeyOf(biliSong())).assertEqual(`${BILI_HASH_VALUE}|bilibili|`);
    });

    it('neteaseNumericIdKeptVerbatim', 0, () => {
      const song = new SongItem(123, 'Song', 'Artist', 'Album', 0);
      song.channelId = 'netease';
      song.audioId = '123';
      expect(stableKeyOf(song)).assertEqual('123|netease|');
    });

    it('legacyFnvStableKeyDiffersAndRemapsToNewKey', 0, () => {
      const song = ytmSong();
      const legacy = legacyFnvStableKey(song);
      expect(legacy).assertEqual(
        `${hashStableId(YTM_VIDEO_ID)}|youtube_music|youtube_music|${YTM_VIDEO_ID}`);
      expect(legacy !== stableKeyOf(song)).assertTrue();
      const remap = buildLegacyKeyRemap([song]);
      expect(remap.get(legacy)).assertEqual(stableKeyOf(song));
    });

    it('buildLegacyKeyRemapDropsAmbiguousKeys', 0, () => {
      // Two locals sharing one legacy key but restoring different wire ids
      // must not silently pick one winner.
      const a = new SongItem(5, 'A', 'X', 'Al', 0);
      a.platform = MusicPlatform.LOCAL;
      a.syncIdText = '777';
      const b = new SongItem(5, 'A', 'X', 'Al', 0);
      b.platform = MusicPlatform.LOCAL;
      b.syncIdText = '888';
      expect(legacyFnvStableKey(a)).assertEqual(legacyFnvStableKey(b));
      const remap = buildLegacyKeyRemap([a, b]);
      expect(remap.has(legacyFnvStableKey(a))).assertFalse();
    });

    it('remapPlaylistRewritesKeysAndKeepsAlignment', 0, () => {
      const song = ytmSong();
      const playlist = new Playlist('local_1', 'List', MusicPlatform.LOCAL);
      playlist.songKeys = [legacyFnvStableKey(song)];
      playlist.songs = [song];
      const changed = remapPlaylist(playlist, buildLegacyKeyRemap([song]));
      expect(changed).assertTrue();
      expect(playlist.songKeys.length).assertEqual(1);
      expect(playlist.songKeys[0]).assertEqual(stableKeyOf(song));
    });

    it('remapPlaylistDedupesCollidingEntries', 0, () => {
      const song = ytmSong();
      const twin = SongItem.fromJson(song.toJson());
      const playlist = new Playlist('local_1', 'List', MusicPlatform.LOCAL);
      // Same video under two legacy shapes that now collide on one new key.
      playlist.songKeys = [legacyFnvStableKey(song), stableKeyOf(song)];
      playlist.songs = [song, twin];
      const changed = remapPlaylist(playlist, buildLegacyKeyRemap([song]));
      expect(changed).assertTrue();
      expect(playlist.songKeys.length).assertEqual(1);
      expect(playlist.songs.length).assertEqual(1);
    });

    it('remapStatsRootMergesCollisionsAndKeepsUnmatched', 0, () => {
      const root = new StatsRoot();
      const first = new TrackStats();
      first.playCount = 3;
      first.listenMs = 30000;
      first.firstPlayedAt = 1000;
      first.lastPlayedAt = 5000;
      const second = new TrackStats();
      second.playCount = 2;
      second.listenMs = 20000;
      second.firstPlayedAt = 1500;
      second.lastPlayedAt = 9000;
      const untouched = new TrackStats();
      untouched.playCount = 7;
      root.tracks['legacyA|bilibili|'] = first;
      root.tracks['legacyB|bilibili|'] = second;
      root.tracks['900000|netease|'] = untouched;
      const remap = new Map<string, string>([
        ['legacyA|bilibili|', `${BILI_HASH_VALUE}|bilibili|`],
        ['legacyB|bilibili|', `${BILI_HASH_VALUE}|bilibili|`]
      ]);
      const next = remapStatsRoot(root, remap);
      const merged = next.tracks[`${BILI_HASH_VALUE}|bilibili|`];
      expect(merged === undefined).assertFalse();
      expect(merged!.playCount).assertEqual(5);
      expect(merged!.listenMs).assertEqual(50000);
      expect(merged!.firstPlayedAt).assertEqual(1000);
      expect(merged!.lastPlayedAt).assertEqual(9000);
      // Keys without a remap entry survive verbatim.
      expect(next.tracks['900000|netease|'] === undefined).assertFalse();
      expect(next.tracks['900000|netease|'].playCount).assertEqual(7);
    });

    it('remapCatalogEntriesRecomputesFromStoredSong', 0, () => {
      const song = biliSong();
      const legacyKey = legacyFnvStableKey(song);
      const entries: DownloadedSongEntry[] = [
        new DownloadedSongEntry(legacyKey, '/data/download/a.m4a', song.toJson(), 100),
        new DownloadedSongEntry('900000|netease|', '/data/download/b.mp3', '', 200)
      ];
      const next = remapCatalogEntries(entries, new Map<string, string>());
      expect(next.length).assertEqual(2);
      expect(next[0].stableKey).assertEqual(stableKeyOf(song));
      // Entries without a snapshot keep their key.
      expect(next[1].stableKey).assertEqual('900000|netease|');
    });

    it('sourceStableKeyRestoresRemoteIdentity', 0, () => {
      const remote = new SongItem(123, 'Song', 'Artist', 'Album', 0);
      remote.channelId = 'netease';
      remote.audioId = '123';
      const local = new SongItem(0, 'Local copy', 'Artist', 'MyAlbum', 0);
      local.platform = MusicPlatform.LOCAL;
      local.localFilePath = '/data/download/song.mp3';
      local.sourceStableKey = stableKeyOf(remote);
      // The downloaded local copy counts as the same song as the remote one.
      expect(stableKeyOf(local)).assertEqual(stableKeyOf(remote));
      expect(songIdentity(local).id).assertEqual('123');
      // A source key that just mirrors the plain local identity is a
      // self-reference and is ignored.
      const selfRef = new SongItem(0, 'Local copy', 'Artist', 'MyAlbum', 0);
      selfRef.platform = MusicPlatform.LOCAL;
      selfRef.sourceStableKey = '0|MyAlbum|';
      expect(songIdentity(selfRef).stableKey()).assertEqual('0|MyAlbum|');
    });

    it('downloadToSyncToOtherEndRecognizesSameSong', 0, () => {
      // download: catalog row keyed by the remote identity + stored snapshot
      const remote = biliSong();
      const entry = new DownloadedSongEntry(stableKeyOf(remote), '/files/Download/NeriPlayer/a.m4a',
        remote.toJson(), 1);
      // other end: the file is imported back through the local media picker
      const imported = new SongItem(0, 'Local copy', 'UP', 'MyAlbum', 0);
      imported.platform = MusicPlatform.LOCAL;
      imported.localFilePath = 'file:///files/Download/NeriPlayer/a.m4a';
      imported.localFileName = 'a.m4a';
      const matched = matchDownloadedEntry(imported, [entry]);
      expect(matched === null).assertFalse();
      imported.sourceStableKey = matched!.stableKey;
      expect(stableKeyOf(imported)).assertEqual(stableKeyOf(remote));
    });

    it('matchDownloadedEntryFallsBackToFileName', 0, () => {
      const entry = new DownloadedSongEntry('1|netease|', '/storage/emulated/10/Music/x.mp3', '', 1);
      const song = new SongItem(0, 'X', '', '', 0);
      song.localFilePath = 'file://media/picked/other-form/x.mp3';
      song.localFileName = 'x.mp3';
      expect(matchDownloadedEntry(song, [entry]) === null).assertFalse();
      expect(matchDownloadedEntry(song, [])).assertNull();
    });

    it('parseStableSongIdentityRejectsMalformedKeys', 0, () => {
      expect(parseStableSongIdentity('nodashes')).assertNull();
      expect(parseStableSongIdentity('|album|uri')).assertNull();
      expect(parseStableSongIdentity('abc|album|uri')).assertNull();
      expect(parseStableSongIdentity('123||uri')).assertNull();
      const parsed = parseStableSongIdentity('-42|netease|');
      expect(parsed === null).assertFalse();
      expect(parsed!.id).assertEqual('-42');
      expect(parsed!.album).assertEqual('netease');
    });

    it('dedupeSongsByKeyKeepsFirstOccurrence', 0, () => {
      const a = new SongItem(5, 'A', '', 'Album', 0);
      a.platform = MusicPlatform.LOCAL;
      const b = SongItem.fromJson(a.toJson());
      const c = new SongItem(9, 'C', '', 'Album', 0);
      c.platform = MusicPlatform.LOCAL;
      const result = dedupeSongsByKey([a, b, c]);
      expect(result.length).assertEqual(2);
      expect(result[0].name).assertEqual('A');
      expect(result[1].name).assertEqual('C');
    });
  });
}
