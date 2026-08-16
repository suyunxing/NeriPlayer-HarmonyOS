import { SongItem } from '../model/SongItem';
import { Playlist } from '../model/Playlist';
import { MusicPlatform } from '../model/MusicPlatform';

/**
 * Parsers for JSON exported by the Android app, aligned field-by-field with
 * the Gson contract (camelCase property names, no version envelopes):
 * - play_history.json: array of PlayedEntry;
 * - local_playlists.json: array of LocalPlaylist (id/name/songs/modifiedAt/
 *   customCoverUrl/songOrderVersion);
 * - playback_stats.json: array of TrackStat (identityKey + counters).
 *
 * These power the explicit "import from Android" tool; unknown fields are
 * ignored, missing fields fall back to defaults.
 */
export class AndroidDataParser {
  /** Parses Android play_history.json into songs (newest first as stored). */
  static parseHistory(json: string): SongItem[] | null {
    let rawList: Object[];
    try {
      const parsed = JSON.parse(json) as Object[];
      if (!Array.isArray(parsed)) {
        return null;
      }
      rawList = parsed;
    } catch (error) {
      return null;
    }
    const songs: SongItem[] = [];
    for (const entry of rawList) {
      const song = AndroidDataParser.songFromEntry(JSON.stringify(entry));
      songs.push(song);
    }
    return songs;
  }

  /** Parses Android local_playlists.json into playlists. */
  static parsePlaylists(json: string): Playlist[] | null {
    let rawList: Object[];
    try {
      const parsed = JSON.parse(json) as Object[];
      if (!Array.isArray(parsed)) {
        return null;
      }
      rawList = parsed;
    } catch (error) {
      return null;
    }
    const playlists: Playlist[] = [];
    for (const entry of rawList) {
      const raw = JSON.parse(JSON.stringify(entry)) as Record<string, Object>;
      const playlist = new Playlist();
      playlist.id = String(raw['id'] ?? '');
      playlist.name = String(raw['name'] ?? '');
      playlist.coverUrl = String(raw['customCoverUrl'] ?? '');
      playlist.updatedAt = Number(raw['modifiedAt'] ?? 0);
      playlist.createdAt = playlist.updatedAt;
      const songs = raw['songs'];
      if (songs !== undefined && Array.isArray(songs)) {
        for (const songEntry of songs as Object[]) {
          const song = AndroidDataParser.songFromEntry(JSON.stringify(songEntry));
          playlist.songs.push(song);
        }
        for (const song of playlist.songs) {
          playlist.songKeys.push(`${song.id}|${song.album}|${song.mediaUri}`);
        }
      }
      playlists.push(playlist);
    }
    return playlists;
  }

  /**
   * Maps an Android PlayedEntry / SongItem Gson object to our SongItem.
   * `playedAt` maps to `addedAt` (closest semantic slot we persist).
   */
  static songFromEntry(json: string): SongItem {
    const song = SongItem.fromJson(json);
    // SongItem.fromJson already whitelists the shared camelCase fields;
    // re-stamp addedAt from the Android playedAt when present.
    const raw = JSON.parse(json) as Record<string, Object>;
    const playedAt = Number(raw['playedAt'] ?? 0);
    if (playedAt > 0) {
      song.addedAt = playedAt;
    }
    return song;
  }
}

/**
 * Playlist sync-pending markers (Android `<file>.sync-pending.json`
 * semantics): a playlist id stays marked until a successful sync upload
 * consumes it. Pure logic here; the sync transport in M5 reads and clears.
 */
export class SyncPendingState {
  static readonly KEY: string = 'playlists.sync_pending';

  static markPending(ids: string[], playlistId: string): string[] {
    if (ids.indexOf(playlistId) < 0) {
      return ids.concat([playlistId]);
    }
    return ids.slice();
  }

  static clearPending(ids: string[], playlistId: string): string[] {
    return ids.filter((id: string) => id !== playlistId);
  }

  static isPending(ids: string[], playlistId: string): boolean {
    return ids.indexOf(playlistId) >= 0;
  }

  static toJson(ids: string[]): string {
    return JSON.stringify(ids);
  }

  static fromJson(json: string): string[] {
    try {
      const parsed = JSON.parse(json) as Object[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      return parsed.map((id: Object) => String(id));
    } catch (error) {
      return [];
    }
  }
}
