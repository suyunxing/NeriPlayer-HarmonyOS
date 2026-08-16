import { SongItem } from './SongItem';
import { RepeatMode } from '../player/PlaybackConstants';

/**
 * Durable snapshot of the playback session, written to preferences so the
 * queue and position survive cold starts. Mirrors the Android
 * PersistedState (last_playlist.json): the shuffle bag itself is not
 * persisted; it is rebuilt on restore keeping the current song first.
 */
export class PersistedPlaybackState {
  static readonly CURRENT_VERSION: number = 1;

  version: number;
  songs: SongItem[];
  queueIndex: number;
  positionMs: number;
  repeatMode: RepeatMode;
  shuffle: boolean;
  speed: number;

  constructor(
    songs: SongItem[] = [],
    queueIndex: number = 0,
    positionMs: number = 0,
    repeatMode: RepeatMode = RepeatMode.ALL,
    shuffle: boolean = false,
    speed: number = 1.0
  ) {
    this.version = PersistedPlaybackState.CURRENT_VERSION;
    this.songs = songs;
    this.queueIndex = queueIndex;
    this.positionMs = positionMs;
    this.repeatMode = repeatMode;
    this.shuffle = shuffle;
    this.speed = speed;
  }

  toJson(): string {
    return JSON.stringify(this);
  }

  /**
   * Parses a persisted snapshot. Unknown/missing fields fall back to defaults
   * and an invalid repeatMode falls back to ALL (Android applies the same
   * whitelist on restore). Returns null when the payload is not usable.
   */
  static fromJson(json: string): PersistedPlaybackState | null {
    let raw: Record<string, Object>;
    try {
      raw = JSON.parse(json) as Record<string, Object>;
    } catch (error) {
      return null;
    }
    const songs: SongItem[] = [];
    const rawSongs = raw['songs'];
    if (rawSongs !== undefined && !Array.isArray(rawSongs)) {
      return null;
    }
    if (rawSongs !== undefined) {
      const entries = rawSongs as Object[];
      for (const entry of entries) {
        try {
          songs.push(SongItem.fromJson(JSON.stringify(entry)));
        } catch (error) {
          return null;
        }
      }
    }
    const repeatModeRaw = Number(raw['repeatMode'] ?? RepeatMode.ALL);
    const repeatMode = PersistedPlaybackState.validRepeatMode(repeatModeRaw);
    const speedRaw = Number(raw['speed'] ?? 1.0);
    return new PersistedPlaybackState(
      songs,
      Math.max(0, Number(raw['queueIndex'] ?? 0)),
      Math.max(0, Number(raw['positionMs'] ?? 0)),
      repeatMode,
      Boolean(raw['shuffle'] ?? false),
      speedRaw > 0 ? speedRaw : 1.0
    );
  }

  static validRepeatMode(mode: number): RepeatMode {
    if (mode === RepeatMode.OFF || mode === RepeatMode.ONE || mode === RepeatMode.ALL) {
      return mode;
    }
    return RepeatMode.ALL;
  }
}
