// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Port of data/sync/github/SyncDataChangeDetector.kt.
 * Decides whether the merged snapshot differs from the remote one (i.e.
 * whether an upload is needed). All comparisons are position-sensitive except
 * token/shard collections, which compare as sets.
 */
import {
  SyncData,
  SyncSong,
  SyncCausalToken,
  SyncPlaylist,
  SyncFavoritePlaylist,
  SyncTrackStat,
  SyncPlaybackStatBucket,
  SyncPlaylistSongDeletion,
  SyncRecentPlay,
  SyncRecentPlayDeletion,
  syncSongIdentity,
  causalTokenKey,
  trackStatMetadataEquals,
  bucketMetadataEquals
} from './SyncModels';

function tokenSetEquals(a: SyncCausalToken[], b: SyncCausalToken[]): boolean {
  if (a.length !== b.length) {
    return false;
  }
  const keys = new Set<string>();
  for (const token of a) {
    keys.add(causalTokenKey(token));
  }
  for (const token of b) {
    if (!keys.has(causalTokenKey(token))) {
      return false;
    }
  }
  return true;
}

function sameSongMetadata(a: SyncSong, b: SyncSong): boolean {
  return a.name === b.name &&
    a.artist === b.artist &&
    a.album === b.album &&
    a.albumId === b.albumId &&
    a.durationMs === b.durationMs &&
    a.coverUrl === b.coverUrl &&
    a.mediaUri === b.mediaUri &&
    a.addedAt === b.addedAt &&
    a.matchedLyric === b.matchedLyric &&
    a.matchedTranslatedLyric === b.matchedTranslatedLyric &&
    a.matchedLyricSource === b.matchedLyricSource &&
    a.matchedSongId === b.matchedSongId &&
    a.userLyricOffsetMs === b.userLyricOffsetMs &&
    a.customCoverUrl === b.customCoverUrl &&
    a.customName === b.customName &&
    a.customArtist === b.customArtist &&
    a.originalName === b.originalName &&
    a.originalArtist === b.originalArtist &&
    a.originalCoverUrl === b.originalCoverUrl &&
    a.originalLyric === b.originalLyric &&
    a.originalTranslatedLyric === b.originalTranslatedLyric &&
    a.channelId === b.channelId &&
    a.audioId === b.audioId &&
    a.subAudioId === b.subAudioId &&
    a.playlistContextId === b.playlistContextId &&
    a.syncMetadataVersion === b.syncMetadataVersion &&
    tokenSetEquals(a.syncMembershipTokens, b.syncMembershipTokens);
}

function identitySequencesEqual(left: SyncSong[], right: SyncSong[]): boolean {
  if (left.length !== right.length) {
    return false;
  }
  for (let i = 0; i < left.length; i++) {
    if (!syncSongIdentity(left[i]).equals(syncSongIdentity(right[i]))) {
      return false;
    }
  }
  return true;
}

function sameSongListsMetadata(left: SyncSong[], right: SyncSong[]): boolean {
  if (left.length !== right.length) {
    return false;
  }
  for (let i = 0; i < left.length; i++) {
    if (!sameSongMetadata(left[i], right[i])) {
      return false;
    }
  }
  return true;
}

function recentPlaysChanged(remoteRecent: SyncRecentPlay[], mergedRecent: SyncRecentPlay[]): boolean {
  if (remoteRecent.length !== mergedRecent.length) {
    return true;
  }
  for (let i = 0; i < remoteRecent.length; i++) {
    if (!syncSongIdentity(remoteRecent[i].song).equals(syncSongIdentity(mergedRecent[i].song))) {
      return true;
    }
    if (!sameSongMetadata(remoteRecent[i].song, mergedRecent[i].song)) {
      return true;
    }
    if (remoteRecent[i].playedAt !== mergedRecent[i].playedAt) {
      return true;
    }
    if (remoteRecent[i].resumePositionMs !== mergedRecent[i].resumePositionMs) {
      return true;
    }
  }
  return false;
}

function recentPlayDeletionsChanged(
  remoteDeletions: SyncRecentPlayDeletion[],
  mergedDeletions: SyncRecentPlayDeletion[]
): boolean {
  if (remoteDeletions.length !== mergedDeletions.length) {
    return true;
  }
  for (let i = 0; i < remoteDeletions.length; i++) {
    if (!remoteDeletions[i].identity().equals(mergedDeletions[i].identity())) {
      return true;
    }
    if (remoteDeletions[i].deletedAt !== mergedDeletions[i].deletedAt) {
      return true;
    }
    if (remoteDeletions[i].deviceId !== mergedDeletions[i].deviceId) {
      return true;
    }
  }
  return false;
}

function playlistSongDeletionsChanged(
  remoteDeletions: SyncPlaylistSongDeletion[],
  mergedDeletions: SyncPlaylistSongDeletion[]
): boolean {
  if (remoteDeletions.length !== mergedDeletions.length) {
    return true;
  }
  for (let i = 0; i < remoteDeletions.length; i++) {
    if (remoteDeletions[i].playlistId !== mergedDeletions[i].playlistId) {
      return true;
    }
    if (!remoteDeletions[i].identity().equals(mergedDeletions[i].identity())) {
      return true;
    }
    if (remoteDeletions[i].deletedAt !== mergedDeletions[i].deletedAt) {
      return true;
    }
    if (remoteDeletions[i].deviceId !== mergedDeletions[i].deviceId) {
      return true;
    }
    if (!tokenSetEquals(remoteDeletions[i].removedMembershipTokens,
      mergedDeletions[i].removedMembershipTokens)) {
      return true;
    }
  }
  return false;
}

export function hasDataChanged(remote: SyncData, merged: SyncData): boolean {
  if (remote.playlists.length !== merged.playlists.length) {
    return true;
  }
  for (let i = 0; i < remote.playlists.length; i++) {
    if (remote.playlists[i].id !== merged.playlists[i].id) {
      return true;
    }
  }

  const remotePlaylistMap = new Map<number, SyncPlaylist>();
  for (const playlist of remote.playlists) {
    remotePlaylistMap.set(playlist.id, playlist);
  }
  for (const mergedPlaylist of merged.playlists) {
    const remotePlaylist = remotePlaylistMap.get(mergedPlaylist.id);
    if (remotePlaylist === undefined) {
      return true;
    }
    if (remotePlaylist.isDeleted !== mergedPlaylist.isDeleted ||
      remotePlaylist.name !== mergedPlaylist.name ||
      remotePlaylist.songOrderVersion !== mergedPlaylist.songOrderVersion ||
      remotePlaylist.songs.length !== mergedPlaylist.songs.length) {
      return true;
    }
    if (!identitySequencesEqual(remotePlaylist.songs, mergedPlaylist.songs)) {
      return true;
    }
    if (!sameSongListsMetadata(remotePlaylist.songs, mergedPlaylist.songs)) {
      return true;
    }
  }

  if (remote.favoritePlaylists.length !== merged.favoritePlaylists.length) {
    return true;
  }
  const remoteFavoriteMap = new Map<string, SyncFavoritePlaylist>();
  const mergedFavoriteMap = new Map<string, SyncFavoritePlaylist>();
  for (const favorite of remote.favoritePlaylists) {
    remoteFavoriteMap.set(`${favorite.id}_${favorite.source}`, favorite);
  }
  for (const favorite of merged.favoritePlaylists) {
    mergedFavoriteMap.set(`${favorite.id}_${favorite.source}`, favorite);
  }
  if (remoteFavoriteMap.size !== mergedFavoriteMap.size) {
    return true;
  }
  let favoritesChanged = false;
  mergedFavoriteMap.forEach((mergedFavorite: SyncFavoritePlaylist, key: string) => {
    if (favoritesChanged) {
      return;
    }
    const remoteFavorite = remoteFavoriteMap.get(key);
    if (remoteFavorite === undefined) {
      favoritesChanged = true;
      return;
    }
    if (remoteFavorite.isDeleted !== mergedFavorite.isDeleted ||
      remoteFavorite.modifiedAt !== mergedFavorite.modifiedAt ||
      remoteFavorite.sortOrder !== mergedFavorite.sortOrder ||
      remoteFavorite.trackCount !== mergedFavorite.trackCount) {
      favoritesChanged = true;
      return;
    }
    if (!identitySequencesEqual(remoteFavorite.songs, mergedFavorite.songs) ||
      !sameSongListsMetadata(remoteFavorite.songs, mergedFavorite.songs)) {
      favoritesChanged = true;
    }
  });
  if (favoritesChanged) {
    return true;
  }

  if (recentPlaysChanged(remote.recentPlays, merged.recentPlays)) {
    return true;
  }
  if (recentPlayDeletionsChanged(remote.recentPlayDeletions, merged.recentPlayDeletions)) {
    return true;
  }
  if (playlistSongDeletionsChanged(remote.playlistSongDeletions, merged.playlistSongDeletions)) {
    return true;
  }

  if (remote.playbackStatsClearedAt !== merged.playbackStatsClearedAt) {
    return true;
  }
  const remoteStats = new Map<string, SyncTrackStat>();
  const mergedStats = new Map<string, SyncTrackStat>();
  for (const stat of remote.playbackStats) {
    remoteStats.set(stat.identityKey, stat);
  }
  for (const stat of merged.playbackStats) {
    mergedStats.set(stat.identityKey, stat);
  }
  if (remoteStats.size !== mergedStats.size) {
    return true;
  }
  let statsChanged = false;
  mergedStats.forEach((mergedStat: SyncTrackStat, key: string) => {
    if (statsChanged) {
      return;
    }
    const remoteStat = remoteStats.get(key);
    if (remoteStat === undefined || !trackStatMetadataEquals(remoteStat, mergedStat)) {
      statsChanged = true;
    }
  });
  if (statsChanged) {
    return true;
  }

  const remoteBuckets = new Map<string, SyncPlaybackStatBucket>();
  const mergedBuckets = new Map<string, SyncPlaybackStatBucket>();
  for (const bucket of remote.playbackStatBuckets) {
    remoteBuckets.set(`${bucket.dayStartAt}\u0000${bucket.identityKey}`, bucket);
  }
  for (const bucket of merged.playbackStatBuckets) {
    mergedBuckets.set(`${bucket.dayStartAt}\u0000${bucket.identityKey}`, bucket);
  }
  if (remoteBuckets.size !== mergedBuckets.size) {
    return true;
  }
  let bucketsChanged = false;
  mergedBuckets.forEach((mergedBucket: SyncPlaybackStatBucket, key: string) => {
    if (bucketsChanged) {
      return;
    }
    const remoteBucket = remoteBuckets.get(key);
    if (remoteBucket === undefined || !bucketMetadataEquals(remoteBucket, mergedBucket)) {
      bucketsChanged = true;
    }
  });
  return bucketsChanged;
}
