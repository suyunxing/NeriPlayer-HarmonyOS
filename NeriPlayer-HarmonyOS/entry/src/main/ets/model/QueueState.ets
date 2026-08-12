import { SongItem } from './SongItem';

/**
 * Serializable snapshot of the playback queue, used to persist it across restarts.
 */
export class QueueState {
  songs: SongItem[];
  queueIndex: number;
  repeatOne: boolean;
  shuffle: boolean;

  constructor(songs: SongItem[] = [], queueIndex: number = 0, repeatOne: boolean = false, shuffle: boolean = false) {
    this.songs = songs;
    this.queueIndex = queueIndex;
    this.repeatOne = repeatOne;
    this.shuffle = shuffle;
  }

  toJson(): string {
    return JSON.stringify(this);
  }

  static fromJson(json: string): QueueState {
    const raw: Record<string, Object> = JSON.parse(json) as Record<string, Object>;
    const songs: SongItem[] = [];
    const rawSongs = raw['songs'] as Object[] | undefined;
    if (rawSongs !== undefined) {
      for (const entry of rawSongs) {
        songs.push(SongItem.fromJson(JSON.stringify(entry)));
      }
    }
    return new QueueState(
      songs,
      Number(raw['queueIndex'] ?? 0),
      Boolean(raw['repeatOne'] ?? false),
      Boolean(raw['shuffle'] ?? false)
    );
  }
}
