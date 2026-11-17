// SPDX-License-Identifier: GPL-3.0

import { Playlist, mergePlaylistSongs } from '../model/Playlist';
import { SongItem } from '../model/SongItem';
import { stableKeyOf } from '../model/SongIdentity';
import { PlaylistSyncSource, SOURCE_SYNC_MODE_APPEND, sourceKeyOf, sourceBindingTokenOf } from './SourceSyncModels';

function uniqueKeys(keys: string[]): string[] {
  return Array.from(new Set<string>(keys));
}

/** Upgrade legacy single mirrors lazily: their old members belong to that source. */
export function ensurePlaylistOwnership(playlist: Playlist): void {
  const sources = playlist.getSyncSources();
  for (const source of sources) {
    if (!source.ownershipKnown) {
      if (sources.length === 1) {
        source.ownedSongKeys = uniqueKeys(source.ownedSongKeys.concat(playlist.songKeys.filter(
          (key: string): boolean => playlist.manualSongKeys.indexOf(key) < 0)));
      }
      source.ownershipKnown = true;
    }
  }
  if (!playlist.manualOwnershipKnown) {
    for (const key of playlist.songKeys) {
      if (!sources.some((source: PlaylistSyncSource): boolean => source.ownedSongKeys.indexOf(key) >= 0)) {
        playlist.manualSongKeys.push(key);
      }
    }
    playlist.manualSongKeys = uniqueKeys(playlist.manualSongKeys);
    playlist.manualOwnershipKnown = true;
  }
}

export function findPlaylistSource(playlist: Playlist, sourceKey: string = ''): PlaylistSyncSource | null {
  const sources = playlist.getSyncSources();
  if (sourceKey.length === 0) {
    return sources.length > 0 ? sources[0] : null;
  }
  return sources.find((source: PlaylistSyncSource): boolean => sourceKeyOf(source) === sourceKey) ?? null;
}

export function currentSourceForApply(playlist: Playlist, sourceKey: string = '',
  expectedBindingToken: string = ''): PlaylistSyncSource | null {
  const source = findPlaylistSource(playlist, sourceKey);
  if (source === null || !source.enabled || (expectedBindingToken.length > 0
    && sourceBindingTokenOf(source) !== expectedBindingToken)) {
    return null;
  }
  return source;
}

/** New bindings own nothing until seeded/fetched; rebinding preserves their bookkeeping. */
export function attachPlaylistSource(playlist: Playlist, incoming: PlaylistSyncSource, bindingId: string): boolean {
  if (incoming.remoteId.length === 0) {
    return false;
  }
  ensurePlaylistOwnership(playlist);
  const existing = findPlaylistSource(playlist, sourceKeyOf(incoming));
  if (existing !== null) {
    if (existing.mode !== incoming.mode || existing.enabled !== incoming.enabled) {
      existing.bindingRevision += 1;
      existing.lastFingerprint = '';
      existing.lastCheckedAt = 0;
    }
    existing.remoteName = incoming.remoteName;
    existing.mode = incoming.mode;
    existing.enabled = incoming.enabled;
    return true;
  }
  const copy = PlaylistSyncSource.fromJson(JSON.parse(incoming.toJson()) as Object);
  if (copy === null) {
    return false;
  }
  copy.bindingId = bindingId;
  copy.bindingRevision = 0;
  copy.ownershipKnown = true;
  playlist.syncSources.push(copy);
  playlist.getSyncSources();
  return true;
}

/** Detached membership becomes manual, including shared members; skipped songs stay absent. */
export function detachPlaylistSource(playlist: Playlist, sourceKey: string = ''): boolean {
  ensurePlaylistOwnership(playlist);
  const sources = playlist.getSyncSources();
  const detached = sources.filter((source: PlaylistSyncSource): boolean =>
    sourceKey.length === 0 || sourceKeyOf(source) === sourceKey);
  if (detached.length === 0) {
    return false;
  }
  for (const source of detached) {
    for (const key of playlist.songKeys) {
      if (source.ownedSongKeys.indexOf(key) >= 0) {
        playlist.manualSongKeys.push(key);
      }
    }
  }
  playlist.manualSongKeys = uniqueKeys(playlist.manualSongKeys);
  playlist.syncSources = sources.filter((source: PlaylistSyncSource): boolean => detached.indexOf(source) < 0);
  // Clear alias first so removing the last binding cannot resurrect it.
  playlist.syncSource = null;
  playlist.getSyncSources();
  return true;
}

export function markPlaylistSongManual(playlist: Playlist, key: string): void {
  ensurePlaylistOwnership(playlist);
  if (playlist.manualSongKeys.indexOf(key) < 0) {
    playlist.manualSongKeys.push(key);
  }
  clearPlaylistSongSkips(playlist, key);
}

export function clearPlaylistSongSkips(playlist: Playlist, key: string): void {
  for (const source of playlist.getSyncSources()) {
    source.skipKeys = source.skipKeys.filter((skip: string): boolean => skip !== key);
    source.lastFingerprint = '';
    source.lastCheckedAt = 0;
  }
}

/** Keep ownership even after deletion, so undo knows every source that owned it. */
export function markPlaylistSongDeleted(playlist: Playlist, key: string): void {
  ensurePlaylistOwnership(playlist);
  playlist.manualSongKeys = playlist.manualSongKeys.filter((manual: string): boolean => manual !== key);
  for (const source of playlist.getSyncSources()) {
    if (source.ownedSongKeys.indexOf(key) >= 0 && source.skipKeys.indexOf(key) < 0) {
      source.skipKeys.push(key);
    }
  }
}

export class SourcePlaylistChange {
  keys: string[] = [];
  songs: SongItem[] = [];
  toAdd: SongItem[] = [];
  toRemove: SongItem[] = [];
  changed: boolean = false;
}

/** One source changes only its own membership; shared and manual entries retain metadata. */
export function applySourceSnapshot(playlist: Playlist, source: PlaylistSyncSource,
  remoteSongs: SongItem[]): SourcePlaylistChange {
  ensurePlaylistOwnership(playlist);
  const previousOwned = new Set<string>(source.ownedSongKeys);
  const remoteByKey = new Map<string, SongItem>();
  for (const song of remoteSongs) {
    const key = stableKeyOf(song);
    if (!remoteByKey.has(key)) {
      remoteByKey.set(key, song);
    }
  }
  const remoteKeys = Array.from(remoteByKey.keys());
  source.ownedSongKeys = source.mode === SOURCE_SYNC_MODE_APPEND
    ? uniqueKeys(source.ownedSongKeys.concat(remoteKeys)) : remoteKeys;
  source.ownershipKnown = true;
  const protectedKeys = new Set<string>(playlist.manualSongKeys);
  for (const other of playlist.getSyncSources()) {
    if (other === source) {
      continue;
    }
    for (const key of other.ownedSongKeys) {
      if (other.skipKeys.indexOf(key) < 0) {
        protectedKeys.add(key);
      }
    }
  }
  const sourceKeys = source.ownedSongKeys.filter((key: string): boolean => source.skipKeys.indexOf(key) < 0);
  const desired = new Set<string>(Array.from(protectedKeys).concat(sourceKeys));
  const exclusive = sourceKeys.filter((key: string): boolean => !protectedKeys.has(key));
  const oldByKey = new Map<string, SongItem>();
  for (const song of playlist.songs) {
    oldByKey.set(stableKeyOf(song), song);
  }
  const result = new SourcePlaylistChange();
  const emitted = new Set<string>();
  let cursor = 0;
  for (const key of playlist.songKeys) {
    if (source.mode !== SOURCE_SYNC_MODE_APPEND && previousOwned.has(key) && !protectedKeys.has(key)) {
      if (cursor < exclusive.length) {
        const next = exclusive[cursor++];
        if (!emitted.has(next)) {
          result.keys.push(next);
          emitted.add(next);
        }
      }
    } else if (desired.has(key) && !emitted.has(key)) {
      result.keys.push(key);
      emitted.add(key);
    }
  }
  for (const key of sourceKeys) {
    if (!emitted.has(key)) {
      result.keys.push(key);
      emitted.add(key);
    }
  }
  // A removed skipped source key may also be missing from the source snapshot.
  // Other owners alone never create an absent song: their own next sync does.
  const availableKeys: string[] = [];
  for (const key of result.keys) {
    const song = oldByKey.get(key) ?? remoteByKey.get(key);
    if (song !== undefined) {
      availableKeys.push(key);
      result.songs.push(song);
      if (!oldByKey.has(key)) {
        result.toAdd.push(song);
      }
    }
  }
  result.keys = availableKeys;
  for (const song of playlist.songs) {
    if (result.keys.indexOf(stableKeyOf(song)) < 0) {
      result.toRemove.push(song);
    }
  }
  result.changed = result.keys.length !== playlist.songKeys.length
    || result.keys.some((key: string, index: number): boolean => key !== playlist.songKeys[index]);
  return result;
}

/** Merge a detached clone, never mutate/delete the original list. */
export function mergePlaylistContent(target: Playlist, original: Playlist, bindingId: string): number {
  ensurePlaylistOwnership(target);
  const sourcePlaylist = Playlist.fromJson(original.toJson());
  ensurePlaylistOwnership(sourcePlaylist);
  const merged = mergePlaylistSongs(target.songKeys, target.songs, sourcePlaylist.songs);
  target.songKeys = merged.keys;
  target.songs = merged.songs;
  for (const key of sourcePlaylist.manualSongKeys) {
    if (target.songKeys.indexOf(key) >= 0) {
      markPlaylistSongManual(target, key);
    }
  }
  for (const source of sourcePlaylist.getSyncSources()) {
    const existing = findPlaylistSource(target, sourceKeyOf(source));
    if (existing === null) {
      attachPlaylistSource(target, source, bindingId);
    } else {
      existing.ownedSongKeys = uniqueKeys(existing.ownedSongKeys.concat(source.ownedSongKeys));
      existing.skipKeys = uniqueKeys(existing.skipKeys.concat(source.skipKeys));
      existing.lastFingerprint = '';
      existing.lastCheckedAt = 0;
    }
  }
  // Every visible merged song wins over imported skips, including existing target songs.
  for (const key of target.songKeys) {
    clearPlaylistSongSkips(target, key);
  }
  return merged.addedCount;
}
