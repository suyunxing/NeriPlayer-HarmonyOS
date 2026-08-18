import { MusicPlatform } from './MusicPlatform';
import { SongItem } from './SongItem';

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
  }

  toJson(): string {
    return JSON.stringify(this);
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
    return playlist;
  }
}
