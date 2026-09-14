// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Port of data/sync/github/SyncPlaylistDeletionPolicy.kt.
 *
 * Tombstones come in two flavours: legacy (identity + deletedAt timestamp)
 * and causal (the set of membership tokens observed at removal time — only
 * token equality matters, timestamps are ignored).
 */
import {
  SyncSong,
  SyncCausalToken,
  SyncPlaylist,
  SyncFavoritePlaylist,
  SyncPlaylistSongDeletion,
  SongIdentityKey,
  syncSongIdentity,
  causalTokenEquals,
  causalTokenKey,
  normalizedSyncCausalTokens,
  effectiveAddedAt,
  syncSongIdentityStableKeys
} from './SyncModels';

export const MAX_PLAYLIST_SONG_DELETIONS: number = 5000;

function hasRemovedTokens(deletion: SyncPlaylistSongDeletion): boolean {
  return deletion.removedMembershipTokens.length > 0;
}

/** compareBy(deletedAt).thenBy(deviceId). */
function deletionMirrorComparator(a: SyncPlaylistSongDeletion, b: SyncPlaylistSongDeletion): number {
  if (a.deletedAt !== b.deletedAt) {
    return a.deletedAt < b.deletedAt ? -1 : 1;
  }
  if (a.deviceId !== b.deviceId) {
    return a.deviceId < b.deviceId ? -1 : 1;
  }
  return 0;
}

/** deletedAt desc, deviceId desc, stableKey asc, tokenless first. */
function deletionOrderComparator(a: SyncPlaylistSongDeletion, b: SyncPlaylistSongDeletion): number {
  if (a.deletedAt !== b.deletedAt) {
    return a.deletedAt > b.deletedAt ? -1 : 1;
  }
  if (a.deviceId !== b.deviceId) {
    return a.deviceId > b.deviceId ? -1 : 1;
  }
  const keyA = a.stableKey();
  const keyB = b.stableKey();
  if (keyA !== keyB) {
    return keyA < keyB ? -1 : 1;
  }
  const tokensA = hasRemovedTokens(a);
  const tokensB = hasRemovedTokens(b);
  if (tokensA !== tokensB) {
    return tokensA ? 1 : -1;
  }
  return 0;
}

function maxWithMirrorFirst(snapshots: SyncPlaylistSongDeletion[]): SyncPlaylistSongDeletion | null {
  let best: SyncPlaylistSongDeletion | null = null;
  for (const snapshot of snapshots) {
    if (best === null || deletionMirrorComparator(snapshot, best) > 0) {
      best = snapshot;
    }
  }
  return best;
}

function deletionEquals(a: SyncPlaylistSongDeletion, b: SyncPlaylistSongDeletion): boolean {
  if (a.playlistId !== b.playlistId || a.songId !== b.songId || a.album !== b.album ||
    a.mediaUri !== b.mediaUri || a.deletedAt !== b.deletedAt || a.deviceId !== b.deviceId ||
    a.syncSongIdText !== b.syncSongIdText ||
    a.removedMembershipTokens.length !== b.removedMembershipTokens.length) {
    return false;
  }
  for (let i = 0; i < a.removedMembershipTokens.length; i++) {
    if (!causalTokenEquals(a.removedMembershipTokens[i], b.removedMembershipTokens[i])) {
      return false;
    }
  }
  return true;
}

function cloneDeletion(
  deletion: SyncPlaylistSongDeletion,
  removedMembershipTokens: SyncCausalToken[]
): SyncPlaylistSongDeletion {
  return new SyncPlaylistSongDeletion(
    deletion.playlistId,
    deletion.songId,
    deletion.album,
    deletion.mediaUri,
    deletion.deletedAt,
    deletion.deviceId,
    removedMembershipTokens,
    deletion.syncSongIdText
  );
}

function tokenListEquals(a: SyncCausalToken[], b: SyncCausalToken[]): boolean {
  if (a.length !== b.length) {
    return false;
  }
  for (let i = 0; i < a.length; i++) {
    if (!causalTokenEquals(a[i], b[i])) {
      return false;
    }
  }
  return true;
}

function mergeDeletionSnapshots(snapshots: SyncPlaylistSongDeletion[]): SyncPlaylistSongDeletion[] {
  const causalSnapshots: SyncPlaylistSongDeletion[] = [];
  const legacySnapshots: SyncPlaylistSongDeletion[] = [];
  for (const deletion of snapshots) {
    if (hasRemovedTokens(deletion)) {
      causalSnapshots.push(deletion);
    } else {
      legacySnapshots.push(deletion);
    }
  }

  const causalMirror = maxWithMirrorFirst(causalSnapshots);
  const tokenBuffer: SyncCausalToken[] = [];
  for (const snapshot of causalSnapshots) {
    for (const token of snapshot.removedMembershipTokens) {
      tokenBuffer.push(token);
    }
  }
  const removedTokens = normalizedSyncCausalTokens(tokenBuffer);
  let mergedCausal: SyncPlaylistSongDeletion | null = null;
  if (causalMirror !== null) {
    mergedCausal = tokenListEquals(removedTokens, causalMirror.removedMembershipTokens)
      ? causalMirror
      : cloneDeletion(causalMirror, removedTokens);
  }

  const latestLegacyBase = maxWithMirrorFirst(legacySnapshots);
  const latestLegacy = latestLegacyBase === null
    ? null
    : cloneDeletion(latestLegacyBase, []);

  const result: SyncPlaylistSongDeletion[] = [];
  if (latestLegacy !== null) {
    result.push(latestLegacy);
  }
  if (mergedCausal !== null) {
    result.push(mergedCausal);
  }
  return result;
}

export function mergeDeletions(
  local: SyncPlaylistSongDeletion[],
  remote: SyncPlaylistSongDeletion[]
): SyncPlaylistSongDeletion[] {
  const groups = new Map<string, SyncPlaylistSongDeletion[]>();
  for (const deletion of local) {
    pushIntoGroup(groups, deletion);
  }
  for (const deletion of remote) {
    pushIntoGroup(groups, deletion);
  }
  const merged: SyncPlaylistSongDeletion[] = [];
  groups.forEach((snapshots: SyncPlaylistSongDeletion[]) => {
    for (const snapshot of mergeDeletionSnapshots(snapshots)) {
      merged.push(snapshot);
    }
  });
  return merged.sort(deletionOrderComparator);
}

function pushIntoGroup(
  groups: Map<string, SyncPlaylistSongDeletion[]>,
  deletion: SyncPlaylistSongDeletion
): void {
  const key = deletion.stableKey();
  const bucket = groups.get(key);
  if (bucket === undefined) {
    groups.set(key, [deletion]);
  } else {
    bucket.push(deletion);
  }
}

/**
 * Keep both tombstone flavours inside a bounded capacity: legacy gets up to
 * maxCount/2 first, then causal fills the remainder, leftovers re-fill legacy
 * before causal.
 */
export function limitDeletions(
  deletions: SyncPlaylistSongDeletion[],
  maxCount: number = MAX_PLAYLIST_SONG_DELETIONS
): SyncPlaylistSongDeletion[] {
  if (maxCount < 0) {
    throw new Error('Deletion capacity must not be negative');
  }
  if (deletions.length === 0 || maxCount === 0) {
    return [];
  }
  const merged = mergeDeletions(deletions, []);
  if (merged.length <= maxCount) {
    return merged;
  }

  const causal: SyncPlaylistSongDeletion[] = [];
  const legacy: SyncPlaylistSongDeletion[] = [];
  for (const deletion of merged) {
    if (hasRemovedTokens(deletion)) {
      causal.push(deletion);
    } else {
      legacy.push(deletion);
    }
  }
  const preferredLegacyCapacity = causal.length === 0
    ? maxCount
    : (legacy.length === 0 ? 0 : Math.floor(maxCount / 2));

  let legacyCapacity = Math.min(legacy.length, preferredLegacyCapacity);
  let causalCapacity = Math.min(causal.length, maxCount - legacyCapacity);

  let remainingCapacity = maxCount - legacyCapacity - causalCapacity;
  if (remainingCapacity > 0) {
    const extraLegacy = Math.min(legacy.length - legacyCapacity, remainingCapacity);
    legacyCapacity += extraLegacy;
    remainingCapacity -= extraLegacy;
  }
  if (remainingCapacity > 0) {
    causalCapacity += Math.min(causal.length - causalCapacity, remainingCapacity);
  }

  const result: SyncPlaylistSongDeletion[] = [];
  for (let i = 0; i < causalCapacity; i++) {
    result.push(causal[i]);
  }
  for (let i = 0; i < legacyCapacity; i++) {
    result.push(legacy[i]);
  }
  return result.sort(deletionOrderComparator);
}

export function applyDeletions(
  playlistId: number,
  songs: SyncSong[],
  deletions: SyncPlaylistSongDeletion[]
): SyncSong[] {
  if (songs.length === 0 || deletions.length === 0) {
    return songs;
  }
  const relevantDeletions: SyncPlaylistSongDeletion[] = [];
  for (const deletion of mergeDeletions(deletions, [])) {
    if (deletion.playlistId === playlistId) {
      relevantDeletions.push(deletion);
    }
  }
  if (relevantDeletions.length === 0) {
    return songs;
  }

  // Causal tombstones remove tokens globally, regardless of identity aliasing.
  const causalRemovedTokens = new Set<string>();
  for (const deletion of relevantDeletions) {
    for (const token of deletion.removedMembershipTokens) {
      causalRemovedTokens.add(causalTokenKey(token));
    }
  }
  const deletionsByIdentity = new Map<string, SyncPlaylistSongDeletion[]>();
  for (const deletion of relevantDeletions) {
    // Grouped by the bare identity stable key (no playlistId prefix), which
    // is what song.identityStableKeys() produces on the lookup side.
    const key = deletion.identity().stableKey();
    const bucket = deletionsByIdentity.get(key);
    if (bucket === undefined) {
      deletionsByIdentity.set(key, [deletion]);
    } else {
      bucket.push(deletion);
    }
  }

  const result: SyncSong[] = [];
  for (const song of songs) {
    const identityDeletions: SyncPlaylistSongDeletion[] = [];
    const seen = new Set<number>();
    for (const stableKey of syncSongIdentityStableKeys(song)) {
      const bucket = deletionsByIdentity.get(stableKey);
      if (bucket === undefined) {
        continue;
      }
      for (const deletion of bucket) {
        let duplicate = false;
        seen.forEach((index: number) => {
          if (deletionEquals(identityDeletions[index], deletion)) {
            duplicate = true;
          }
        });
        if (!duplicate) {
          identityDeletions.push(deletion);
          seen.add(identityDeletions.length - 1);
        }
      }
    }
    const surviving = applyDeletionsToSong(song, causalRemovedTokens, identityDeletions);
    if (surviving !== null) {
      result.push(surviving);
    }
  }
  return result;
}

function cloneSongWithTokens(song: SyncSong, tokens: SyncCausalToken[]): SyncSong {
  const copy = new SyncSong(
    song.id, song.name, song.artist, song.album, song.albumId, song.durationMs,
    song.coverUrl, song.mediaUri, song.addedAt, song.matchedLyric,
    song.matchedTranslatedLyric, song.matchedLyricSource, song.matchedSongId,
    song.userLyricOffsetMs, song.customCoverUrl, song.customName, song.customArtist,
    song.originalName, song.originalArtist, song.originalCoverUrl, song.originalLyric,
    song.originalTranslatedLyric, song.channelId, song.audioId, song.subAudioId,
    song.playlistContextId, tokens, song.syncMetadataVersion, song.legacyAddedAt
  );
  return copy;
}

function applyDeletionsToSong(
  song: SyncSong,
  causalRemovedTokens: Set<string>,
  identityDeletions: SyncPlaylistSongDeletion[]
): SyncSong | null {
  const songTokens = normalizedSyncCausalTokens(song.syncMembershipTokens);
  if (songTokens.length === 0) {
    // Legacy path: identity tombstone, survived only when re-added later.
    const latestIdentityDeletion = maxWithMirrorFirst(identityDeletions);
    if (latestIdentityDeletion === null) {
      return song;
    }
    return effectiveAddedAt(song) > latestIdentityDeletion.deletedAt ? song : null;
  }

  const remainingTokens = songTokens.filter((token: SyncCausalToken): boolean => {
    return !causalRemovedTokens.has(causalTokenKey(token));
  });
  if (remainingTokens.length === 0) {
    return null;
  }
  if (tokenListEquals(remainingTokens, song.syncMembershipTokens)) {
    return song;
  }
  return cloneSongWithTokens(song, remainingTokens);
}

export function pruneResolvedDeletions(
  deletions: SyncPlaylistSongDeletion[],
  playlists: SyncPlaylist[]
): SyncPlaylistSongDeletion[] {
  if (deletions.length === 0) {
    return [];
  }
  const normalizedDeletions = mergeDeletions(deletions, []);
  const activeSongsByKey = new Map<string, SyncSong>();
  for (const playlist of playlists) {
    if (playlist.isDeleted) {
      continue;
    }
    for (const song of playlist.songs) {
      for (const identityKey of syncSongIdentityStableKeys(song)) {
        activeSongsByKey.set(`${playlist.id}|${identityKey}`, song);
      }
    }
  }

  const kept: SyncPlaylistSongDeletion[] = [];
  for (const deletion of normalizedDeletions) {
    if (hasRemovedTokens(deletion)) {
      kept.push(deletion);
      continue;
    }
    const activeSong = activeSongsByKey.get(deletion.stableKey());
    // Only prune a legacy tombstone when the active song carries membership
    // tokens (genuinely re-added under causal ownership). A tokenless song's
    // addedAt may be a synthesized legacy migration value; trusting it would
    // resurrect deleted songs (Android P1-1).
    if (activeSong !== undefined &&
      activeSong.syncMembershipTokens.length > 0 &&
      effectiveAddedAt(activeSong) > deletion.deletedAt) {
      continue;
    }
    kept.push(deletion);
  }
  return limitDeletions(kept);
}

export function clearLegacyDeletionsForReaddedSongs(
  deletions: SyncPlaylistSongDeletion[],
  playlistId: number,
  identities: SongIdentityKey[]
): SyncPlaylistSongDeletion[] {
  if (deletions.length === 0 || identities.length === 0) {
    return deletions;
  }
  const readdedKeys = new Set<string>();
  for (const identity of identities) {
    readdedKeys.add(`${playlistId}|${identity.stableKey()}`);
  }
  const result: SyncPlaylistSongDeletion[] = [];
  for (const deletion of mergeDeletions(deletions, [])) {
    if (readdedKeys.has(deletion.stableKey()) && !hasRemovedTokens(deletion)) {
      continue;
    }
    result.push(deletion);
  }
  return result;
}

function cloneFavorite(
  base: SyncFavoritePlaylist,
  songs: SyncSong[],
  trackCount: number,
  sortOrder: number,
  coverUrl: string | null = base.coverUrl,
  addedTime: number = base.addedTime,
  modifiedAt: number = base.modifiedAt,
  isDeleted: boolean = base.isDeleted
): SyncFavoritePlaylist {
  return new SyncFavoritePlaylist(
    base.id,
    base.name,
    coverUrl,
    trackCount,
    base.source,
    songs,
    addedTime,
    modifiedAt,
    isDeleted,
    sortOrder,
    base.browseId,
    base.playlistId,
    base.subtitle
  );
}

function distinctByIdentity(songs: SyncSong[]): SyncSong[] {
  const seen = new Set<string>();
  const result: SyncSong[] = [];
  for (const song of songs) {
    const key = syncSongIdentity(song).mapKey();
    if (!seen.has(key)) {
      seen.add(key);
      result.push(song);
    }
  }
  return result;
}

/** Two-way favorites merge: newer modifiedAt wins; equal timestamps favor deleted. */
export function mergeFavoritePlaylists(
  left: SyncFavoritePlaylist,
  right: SyncFavoritePlaylist
): SyncFavoritePlaylist {
  const newer = right.modifiedAt > left.modifiedAt ? right : left;
  const older = newer === left ? right : left;

  if (left.isDeleted !== right.isDeleted) {
    if (left.modifiedAt === right.modifiedAt) {
      const deleted = left.isDeleted ? left : right;
      return cloneFavorite(
        deleted,
        [],
        0,
        Math.max(left.sortOrder, right.sortOrder),
        deleted.coverUrl,
        Math.max(left.addedTime, right.addedTime),
        Math.max(left.modifiedAt, right.modifiedAt),
        deleted.isDeleted
      );
    }
    if (newer.isDeleted) {
      return cloneFavorite(newer, [], 0, Math.max(left.sortOrder, right.sortOrder));
    }
    const mergedSongs = distinctByIdentity(left.songs.concat(right.songs));
    return cloneFavorite(
      newer,
      mergedSongs,
      Math.max(left.trackCount, right.trackCount, left.songs.length, right.songs.length),
      newer.sortOrder > 0 ? newer.sortOrder : older.sortOrder
    );
  }

  if (newer.isDeleted) {
    return cloneFavorite(
      newer,
      [],
      0,
      Math.max(left.sortOrder, right.sortOrder),
      newer.coverUrl,
      Math.max(left.addedTime, right.addedTime),
      newer.modifiedAt,
      newer.isDeleted
    );
  }

  const mergedSongs = distinctByIdentity(left.songs.concat(right.songs));
  return cloneFavorite(
    newer,
    mergedSongs,
    Math.max(left.trackCount, right.trackCount, mergedSongs.length),
    newer.sortOrder > 0 ? newer.sortOrder : older.sortOrder,
    newer.coverUrl !== null ? newer.coverUrl : older.coverUrl,
    Math.max(left.addedTime, right.addedTime),
    Math.max(left.modifiedAt, right.modifiedAt),
    false
  );
}
