// SPDX-License-Identifier: GPL-3.0

import { MusicPlatform } from './MusicPlatform';
import { SongItem } from './SongItem';
import { stableKeyOf } from './SongIdentity';
import { PlaylistSyncSource, sourceKeyOf } from '../sourcesync/SourceSyncModels';

/**
 * Playlist model shared by local playlists, favorites, and remote platform playlists.
 * Song membership is stored as stable keys (see SongIdentity) so playlists survive
 * platform metadata changes, matching the Android/Desktop sync format.
 */
export class Playlist {
  id: string;
  name: string;
  coverUrl: string;
  description: string;
  source: MusicPlatform;
  songKeys: string[];
  songs: SongItem[];
  createdAt: number;
  updatedAt: number;
  /**
   * Sync binding for source-mirrored playlists (网易云歌单/B站收藏夹自动同步).
   * Null for plain local playlists; snapshots without the field parse back as
   * null, so the addition needs no storage migration.
   */
  syncSource: PlaylistSyncSource | null;
  /** Canonical multi-source bindings; syncSource remains the first-source alias. */
  syncSources: PlaylistSyncSource[];
  manualSongKeys: string[];
  manualOwnershipKnown: boolean;

  constructor(id: string = '', name: string = '', source: MusicPlatform = MusicPlatform.LOCAL) {
    this.id = id;
    this.name = name;
    this.coverUrl = '';
    this.description = '';
    this.source = source;
    this.songKeys = [];
    this.songs = [];
    this.createdAt = Date.now();
    this.updatedAt = Date.now();
    this.syncSource = null;
    this.syncSources = [];
    this.manualSongKeys = [];
    this.manualOwnershipKnown = false;
  }

  /**
   * Display cover: the first song's effective cover wins (custom covers
   * included), falling back to the playlist's own coverUrl; callers render a
   * placeholder when both are empty. Home cards and the playlist detail header
   * share this derivation — membership changes refresh updatedAt, and the
   * pages reload on that signal so the cover follows the first song.
   */
  get displayCoverUrl(): string {
    if (this.songs.length > 0) {
      const firstCover = this.songs[0].effectiveCoverUrl;
      if (firstCover.length > 0) {
        return firstCover;
      }
    }
    return this.coverUrl;
  }

  getSyncSources(): PlaylistSyncSource[] {
    if (this.syncSources.length === 0 && this.syncSource !== null) {
      this.syncSources.push(this.syncSource);
    }
    const seen = new Set<string>();
    this.syncSources = this.syncSources.filter((source: PlaylistSyncSource): boolean => {
      const key = sourceKeyOf(source);
      if (seen.has(key)) {
        return false;
      }
      seen.add(key);
      return true;
    });
    this.syncSource = this.syncSources.length > 0 ? this.syncSources[0] : null;
    return this.syncSources;
  }

  toJson(): string {
    this.getSyncSources();
    // Omit the nullable legacy alias on plain lists; both absent and null parse identically.
    return JSON.stringify(this, (key: string, value: Object | null): Object | null | undefined => {
      return key === 'syncSource' && value === null ? undefined : value;
    });
  }

  static fromJson(json: string): Playlist {
    const raw: Record<string, Object> = JSON.parse(json) as Record<string, Object>;
    const playlist = new Playlist();
    playlist.id = String(raw['id'] ?? '');
    playlist.name = String(raw['name'] ?? '');
    playlist.coverUrl = String(raw['coverUrl'] ?? '');
    playlist.description = String(raw['description'] ?? '');
    playlist.source = Number(raw['source'] ?? MusicPlatform.LOCAL) as MusicPlatform;
    playlist.createdAt = Number(raw['createdAt'] ?? 0);
    playlist.updatedAt = Number(raw['updatedAt'] ?? 0);
    const keys = raw['songKeys'];
    if (keys instanceof Array) {
      playlist.songKeys = keys.map((key: Object) => String(key));
    } else {
      playlist.songKeys = [];
    }
    const songs = raw['songs'];
    if (songs instanceof Array) {
      playlist.songs = songs.map((song: Object) => SongItem.fromJson(JSON.stringify(song)));
    } else {
      playlist.songs = [];
    }
    const sources = raw['syncSources'];
    if (sources instanceof Array) {
      for (const value of sources as Object[]) {
        const source = PlaylistSyncSource.fromJson(value as Object);
        if (source !== null) {
          playlist.syncSources.push(source);
        }
      }
    } else {
      playlist.syncSource = PlaylistSyncSource.fromJson(raw['syncSource'] ?? null);
    }
    const manualKeys = raw['manualSongKeys'];
    if (manualKeys instanceof Array) {
      playlist.manualSongKeys = manualKeys.map((key: Object): string => String(key));
    }
    playlist.manualOwnershipKnown = Boolean(raw['manualOwnershipKnown'] ?? false);
    playlist.getSyncSources();
    return playlist;
  }
}

/** Result of appending songs to a playlist: synced key/song lists + count. */
export class PlaylistSongMerge {
  keys: string[] = [];
  songs: SongItem[] = [];
  addedCount: number = 0;
}

/**
 * Appends `additions` to a playlist in order, skipping entries whose stable
 * key is already present (or duplicated inside the batch). Pure so batch
 * imports stay unit-testable.
 */
export function mergePlaylistSongs(existingKeys: string[], existingSongs: SongItem[], additions: SongItem[]): PlaylistSongMerge {
  const merge = new PlaylistSongMerge();
  const seen = new Set<string>();
  for (const key of existingKeys) {
    seen.add(key);
    merge.keys.push(key);
  }
  for (const song of existingSongs) {
    merge.songs.push(song);
  }
  for (const song of additions) {
    const key = stableKeyOf(song);
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    merge.keys.push(key);
    merge.songs.push(song);
    merge.addedCount += 1;
  }
  return merge;
}
