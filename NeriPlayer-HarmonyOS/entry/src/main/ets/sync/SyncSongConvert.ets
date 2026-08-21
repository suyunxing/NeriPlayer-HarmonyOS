/**
 * Ports of the conversion layer between the app models and the sync models:
 * SyncSong.fromSongItem/toSongItem, SyncPlaylist.fromLocalPlaylist and
 * normalizedForDisplayOrder (legacy song order migration) from
 * data/sync/model/SyncDataModels.kt, plus LocalSongSupport.isLocalSong /
 * sanitizeMediaUriForSync.
 */
import { SongItem } from '../model/SongItem';
import { Playlist } from '../model/Playlist';
import { MusicPlatform } from '../model/MusicPlatform';
import { hashStableId } from '../model/SongIdentity';
import {
  SyncSong,
  SyncPlaylist,
  CURRENT_SYNC_METADATA_VERSION,
  DISPLAY_ORDER_SONG_ORDER_VERSION,
  cloneSyncSong,
  normalizedSyncCausalTokens
} from './SyncModels';

function emptyToNull(value: string): string | null {
  return value.length > 0 ? value : null;
}

/** LocalSongSupport.isLocalMediaUri subset: schemes that never leave the device. */
export function isLocalMediaUri(mediaUri: string | null): boolean {
  if (mediaUri === null || mediaUri.length === 0) {
    return false;
  }
  if (mediaUri.startsWith('/')) {
    return true;
  }
  const lowered = mediaUri.toLowerCase();
  return lowered.startsWith('file://') || lowered.startsWith('content://') ||
    lowered.startsWith('android.resource://');
}

export function isLocalSongItem(song: SongItem): boolean {
  return song.platform === MusicPlatform.LOCAL ||
    song.localFilePath.length > 0 ||
    isLocalMediaUri(song.mediaUri);
}

/** LocalSongSupport.sanitizeMediaUriForSync: local references become null. */
export function sanitizeMediaUriForSync(mediaUri: string | null): string | null {
  return isLocalMediaUri(mediaUri) ? null : mediaUri;
}

/** SyncSong.fromSongItem; returns null for local songs (never synced). */
export function syncSongFromSongItem(song: SongItem): SyncSong | null {
  if (isLocalSongItem(song)) {
    return null;
  }
  return new SyncSong(
    song.id,
    song.name,
    song.artist,
    song.album,
    song.albumId,
    song.durationMs,
    emptyToNull(song.coverUrl),
    sanitizeMediaUriForSync(song.mediaUri),
    Math.max(song.addedAt, 0),
    emptyToNull(song.matchedLyric),
    emptyToNull(song.matchedTranslatedLyric),
    null, // matchedLyricSource: the app model has no source field yet
    emptyToNull(song.matchedSongId),
    song.userLyricOffsetMs,
    emptyToNull(song.customCoverUrl),
    emptyToNull(song.customName),
    emptyToNull(song.customArtist),
    emptyToNull(song.originalName),
    emptyToNull(song.originalArtist),
    emptyToNull(song.originalCoverUrl),
    emptyToNull(song.originalLyric),
    emptyToNull(song.originalTranslatedLyric),
    emptyToNull(song.channelId),
    emptyToNull(song.audioId),
    emptyToNull(song.subAudioId),
    emptyToNull(song.playlistContextId),
    normalizedSyncCausalTokens(song.syncMembershipTokens),
    CURRENT_SYNC_METADATA_VERSION,
    null,
    song.syncIdText
  );
}

function platformOfSyncSong(song: SyncSong): MusicPlatform {
  const channel = song.channelId === null ? '' : song.channelId.trim().toLowerCase();
  if (channel === 'netease') {
    return MusicPlatform.NETEASE;
  }
  if (channel === 'bilibili') {
    return MusicPlatform.BILIBILI;
  }
  if (channel === 'youtube_music' || channel === 'youtube' || channel === 'ytmusic') {
    return MusicPlatform.YOUTUBE_MUSIC;
  }
  if (song.mediaUri !== null && song.mediaUri.startsWith('youtube_music|')) {
    return MusicPlatform.YOUTUBE_MUSIC;
  }
  if (song.album.toLowerCase().startsWith('bilibili')) {
    return MusicPlatform.BILIBILI;
  }
  return MusicPlatform.NETEASE;
}

function nullToEmpty(value: string | null): string {
  return value === null ? '' : value;
}

/**
 * SyncSong.toSongItem. Note: a 64-bit wire id (syncIdText) degrades to an
 * approximate number here — SongItem.id is a JS number domain; sync equality
 * always goes through the sync identity, never through SongItem.id.
 */
export function songItemFromSyncSong(song: SyncSong): SongItem {
  const item = new SongItem(
    song.id,
    song.name,
    song.artist,
    song.album,
    song.albumId,
    song.durationMs,
    nullToEmpty(song.coverUrl),
    nullToEmpty(song.mediaUri),
    platformOfSyncSong(song)
  );
  item.matchedLyric = nullToEmpty(song.matchedLyric);
  item.matchedTranslatedLyric = nullToEmpty(song.matchedTranslatedLyric);
  item.matchedSongId = nullToEmpty(song.matchedSongId);
  item.userLyricOffsetMs = song.userLyricOffsetMs;
  item.customCoverUrl = nullToEmpty(song.customCoverUrl);
  item.customName = nullToEmpty(song.customName);
  item.customArtist = nullToEmpty(song.customArtist);
  item.originalName = nullToEmpty(song.originalName);
  item.originalArtist = nullToEmpty(song.originalArtist);
  item.originalCoverUrl = nullToEmpty(song.originalCoverUrl);
  item.originalLyric = nullToEmpty(song.originalLyric);
  item.originalTranslatedLyric = nullToEmpty(song.originalTranslatedLyric);
  item.channelId = nullToEmpty(song.channelId);
  item.audioId = nullToEmpty(song.audioId);
  item.subAudioId = nullToEmpty(song.subAudioId);
  item.playlistContextId = nullToEmpty(song.playlistContextId);
  item.addedAt = song.addedAt;
  item.syncMembershipTokens = normalizedSyncCausalTokens(song.syncMembershipTokens);
  item.syncIdText = song.syncIdText;
  return item;
}

const LOCAL_PLAYLIST_ID_PREFIX: string = 'local_';

/**
 * Local playlist ids are strings on this side ("local_<ts>" for created
 * playlists, plain numeric text for ids imported from Android). SyncPlaylist
 * ids are numbers: numeric text maps directly, everything else falls back to
 * a stable FNV hash of the full id string (collision-free for our domains).
 */
export function playlistIdToSync(id: string): number {
  const text = id.startsWith(LOCAL_PLAYLIST_ID_PREFIX)
    ? id.substring(LOCAL_PLAYLIST_ID_PREFIX.length)
    : id;
  const numeric = Number(text);
  if (text.length > 0 && Number.isFinite(numeric)) {
    return numeric;
  }
  return hashStableId(id);
}

export function syncPlaylistIdToLocal(id: number): string {
  return `${id}`;
}

/** SyncPlaylist.fromLocalPlaylist: createdAt uses the playlist id, per Android. */
export function syncPlaylistFromPlaylist(playlist: Playlist, modifiedAt: number): SyncPlaylist {
  const songs: SyncSong[] = [];
  for (const song of playlist.songs) {
    const syncSong = syncSongFromSongItem(song);
    if (syncSong !== null) {
      songs.push(syncSong);
    }
  }
  const numericId = playlistIdToSync(playlist.id);
  return new SyncPlaylist(
    numericId,
    playlist.name,
    songs,
    numericId,
    modifiedAt,
    false,
    DISPLAY_ORDER_SONG_ORDER_VERSION
  );
}

function songListEquals(a: SyncSong[], b: SyncSong[]): boolean {
  if (a.length !== b.length) {
    return false;
  }
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) {
      return false;
    }
  }
  return true;
}

function sortedByAddedAtForDisplay(songs: SyncSong[]): SyncSong[] {
  if (songs.length < 2) {
    return songs;
  }
  const indexed = songs.map((song: SyncSong, index: number): [SyncSong, number] => [song, index]);
  indexed.sort((x: [SyncSong, number], y: [SyncSong, number]): number => {
    if (x[0].addedAt !== y[0].addedAt) {
      return x[0].addedAt > y[0].addedAt ? -1 : 1;
    }
    return x[1] < y[1] ? -1 : (x[1] > y[1] ? 1 : 0);
  });
  return indexed.map((pair: [SyncSong, number]): SyncSong => pair[0]);
}

function migrateLegacySongsToDisplayOrder(
  songs: SyncSong[],
  playlistModifiedAt: number
): SyncSong[] {
  if (songs.length === 0) {
    return [];
  }
  // The anchor must be independent of the wall clock: use the playlist's own
  // modifiedAt (snapshot creation time), otherwise the synthesized addedAt
  // would always exceed every historical deletedAt and resurrect deleted
  // songs (Android P1-1).
  let newestAddedAt = playlistModifiedAt;
  for (const song of songs) {
    if (song.addedAt > newestAddedAt) {
      newestAddedAt = song.addedAt;
    }
  }
  if (newestAddedAt < 1) {
    newestAddedAt = 1;
  }
  const migrated: SyncSong[] = [];
  for (let i = songs.length - 1; i >= 0; i--) {
    const index = songs.length - 1 - i;
    const song = songs[i];
    const copy = cloneSyncSong(song);
    copy.addedAt = Math.max(newestAddedAt - index, 1);
    copy.legacyAddedAt = song.legacyAddedAt !== null ? song.legacyAddedAt : song.addedAt;
    migrated.push(copy);
  }
  return migrated;
}

/** SyncPlaylist.normalizedForDisplayOrder. */
export function normalizedForDisplayOrder(playlist: SyncPlaylist): SyncPlaylist {
  if (playlist.isDeleted) {
    const copy = new SyncPlaylist(
      playlist.id, playlist.name, [], playlist.createdAt, playlist.modifiedAt,
      playlist.isDeleted, DISPLAY_ORDER_SONG_ORDER_VERSION
    );
    return copy;
  }
  const alreadyDisplay = playlist.songOrderVersion >= DISPLAY_ORDER_SONG_ORDER_VERSION;
  const displaySongs = alreadyDisplay
    ? sortedByAddedAtForDisplay(playlist.songs)
    : migrateLegacySongsToDisplayOrder(playlist.songs, playlist.modifiedAt);
  if (alreadyDisplay && songListEquals(displaySongs, playlist.songs)) {
    return playlist;
  }
  return new SyncPlaylist(
    playlist.id,
    playlist.name,
    displaySongs,
    playlist.createdAt,
    playlist.modifiedAt,
    playlist.isDeleted,
    DISPLAY_ORDER_SONG_ORDER_VERSION
  );
}
