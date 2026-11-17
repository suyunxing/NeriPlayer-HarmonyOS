// SPDX-License-Identifier: GPL-3.0

import { Playlist } from '../model/Playlist';
import { SongItem } from '../model/SongItem';
import { MusicPlatform } from '../model/MusicPlatform';
import { PlaylistSyncSource, sourceKeyOf, sourceBindingTokenOf } from './SourceSyncModels';
import { SyncSourceAdapter } from './SyncSourceAdapter';

/** Injectable I/O boundary: the same orchestration runs against deterministic fakes. */
export interface SourceSyncDependencies {
  adapterFor: (source: PlaylistSyncSource) => SyncSourceAdapter | null;
  isLoggedIn: (platform: MusicPlatform) => boolean;
  now: () => number;
  apply: (playlistId: string, songs: SongItem[], fingerprint: string,
    sourceKey: string, bindingToken: string) => Promise<boolean>;
  onFailure: (source: PlaylistSyncSource, error: Error) => void;
}

export class SourceSyncRunResult {
  changed: boolean = false;
  syncedCount: number = 0;
  failedSourceKeys: string[] = [];
}

const FULL_CHECK_INTERVAL_MS: number = 24 * 3600 * 1000;

export async function runSourceSync(playlists: Playlist[], dependencies: SourceSyncDependencies,
  playlistId: string = '', sourceKey: string = '', forceFull: boolean = false): Promise<SourceSyncRunResult> {
  const result = new SourceSyncRunResult();
  const targeted = playlistId.length > 0 || sourceKey.length > 0;
  let matched = 0;
  let firstFailure: Error | null = null;
  for (const playlist of playlists) {
    if (playlistId.length > 0 && playlist.id !== playlistId) {
      continue;
    }
    for (const source of playlist.getSyncSources()) {
      const key = sourceKeyOf(source);
      if (sourceKey.length > 0 && key !== sourceKey) {
        continue;
      }
      if (!source.enabled) {
        continue;
      }
      matched += 1;
      // Capture before any awaited I/O. The repository validates against live state.
      const token = sourceBindingTokenOf(source);
      try {
        const adapter = dependencies.adapterFor(source);
        if (adapter === null) {
          throw new Error('Unsupported sync source');
        }
        if (!dependencies.isLoggedIn(source.platform)) {
          throw new Error('Sync source account is not signed in');
        }
        const fingerprintPending: Promise<string> = adapter.peekFingerprint();
        const fingerprint = await fingerprintPending;
        if (!forceFull && source.ownershipKnown && fingerprint === source.lastFingerprint
          && dependencies.now() - source.lastCheckedAt < FULL_CHECK_INTERVAL_MS) {
          continue;
        }
        const songsPending: Promise<SongItem[]> = adapter.fetchSongs();
        const songs = await songsPending;
        if (songs.length === 0) {
          // Existing adapters may translate a platform business error to an empty list.
          throw new Error('Empty source snapshot; retained current membership');
        }
        const applyPending: Promise<boolean> = dependencies.apply(playlist.id, songs, fingerprint, key, token);
        const changed = await applyPending;
        result.changed = result.changed || changed;
        result.syncedCount += 1;
      } catch (error) {
        const failure = error as Error;
        dependencies.onFailure(source, failure);
        result.failedSourceKeys.push(key);
        if (firstFailure === null) {
          firstFailure = failure;
        }
      }
    }
  }
  if (targeted && matched === 0) {
    throw new Error('No enabled matching sync source');
  }
  if (targeted && firstFailure !== null) {
    throw firstFailure;
  }
  return result;
}
