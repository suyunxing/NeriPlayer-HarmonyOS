// SPDX-License-Identifier: GPL-3.0

import { SongItem } from '../model/SongItem';
import { stableKeyOf } from '../model/SongIdentity';

/**
 * Pure diff between a mirror playlist's local membership and one fetched
 * remote snapshot. Pure so both modes stay unit-testable; the repository
 * (LocalPlaylistRepository.applyMirrorSync) turns the result into writes.
 */
export class SourceSyncDiffResult {
  /** Remote songs missing locally; skipKeys already filtered, batch deduped. */
  toAdd: SongItem[] = [];
  /** Local keys that must go (mirror mode only: absent from the remote list). */
  toRemoveKeys: string[] = [];
  /** Full ordered key list the playlist should hold (mirror mode; [] for append). */
  finalOrder: string[] = [];
  /** True when membership or order differs from the current local state. */
  changed: boolean = false;
}

class RemoteSongIndex {
  songByKey: Map<string, SongItem> = new Map();
  order: string[] = [];
}

function indexRemoteSongs(remoteSongs: SongItem[], skipped: Set<string>): RemoteSongIndex {
  const index = new RemoteSongIndex();
  for (const song of remoteSongs) {
    const key = stableKeyOf(song);
    if (key.length === 0 || skipped.has(key) || index.songByKey.has(key)) {
      continue;
    }
    index.songByKey.set(key, song);
    index.order.push(key);
  }
  return index;
}

function orderedKeysEqual(a: string[], b: string[]): boolean {
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

/**
 * Mirror mode: the remote list wins. Songs gone from the remote are removed,
 * new ones are added, and finalOrder reproduces the remote order (skipped
 * keys — user deletions — are excluded from both directions, so they are
 * neither re-added nor reported as removals).
 */
export function mirrorDiff(localKeys: string[], remoteSongs: SongItem[], skipKeys: string[]): SourceSyncDiffResult {
  const result = new SourceSyncDiffResult();
  const skipped = new Set<string>(skipKeys);
  const remote = indexRemoteSongs(remoteSongs, skipped);

  const localSet = new Set<string>(localKeys);
  for (const key of remote.order) {
    if (!localSet.has(key)) {
      const song = remote.songByKey.get(key);
      if (song !== undefined) {
        result.toAdd.push(song);
      }
    }
  }

  for (const key of localKeys) {
    if (!remote.songByKey.has(key)) {
      result.toRemoveKeys.push(key);
    }
  }

  result.finalOrder = remote.order.slice();
  const keptLocalOrder: string[] = [];
  for (const key of localKeys) {
    if (remote.songByKey.has(key)) {
      keptLocalOrder.push(key);
    }
  }
  result.changed = result.toAdd.length > 0 || result.toRemoveKeys.length > 0
    || !orderedKeysEqual(keptLocalOrder, result.finalOrder);
  return result;
}

/**
 * Append mode: never removes, never reorders — only lists remote songs that
 * are neither stored locally nor in the user-deletion skip set.
 */
export function appendDiff(localKeys: string[], remoteSongs: SongItem[], skipKeys: string[]): SourceSyncDiffResult {
  const result = new SourceSyncDiffResult();
  const skipped = new Set<string>(skipKeys);
  const localSet = new Set<string>(localKeys);
  const seen = new Set<string>();
  for (const song of remoteSongs) {
    const key = stableKeyOf(song);
    if (key.length === 0 || skipped.has(key) || localSet.has(key) || seen.has(key)) {
      continue;
    }
    seen.add(key);
    result.toAdd.push(song);
  }
  result.changed = result.toAdd.length > 0;
  return result;
}
