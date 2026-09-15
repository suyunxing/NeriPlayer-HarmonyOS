// SPDX-License-Identifier: GPL-3.0

import { SongItem } from '../model/SongItem';
import { stableKeyOf } from '../model/SongIdentity';
import { Constants } from '../app/Constants';

export interface AlbumQuery {
  album: string;
  albumId: number;
}

/**
 * Album membership math for the「查看专辑」page. Pure functions so the
 * matching rules stay unit-testable.
 */
export class AlbumSongs {
  /** True when the song carries real album data (not the YTM identity placeholder). */
  static hasAlbumData(song: SongItem): boolean {
    const album = song.album.trim();
    return album.length > 0 && album !== Constants.YOUTUBE_MUSIC_IDENTITY_ALBUM;
  }

  static matches(song: SongItem, query: AlbumQuery): boolean {
    if (query.albumId > 0) {
      return song.albumId === query.albumId;
    }
    const album = query.album.trim();
    return album.length > 0 && song.album.trim() === album;
  }

  /** Deduped songs (by stable key) from the pool that belong to the queried album. */
  static collect(pool: SongItem[], query: AlbumQuery): SongItem[] {
    const seen: Set<string> = new Set<string>();
    const result: SongItem[] = [];
    for (const song of pool) {
      if (!AlbumSongs.matches(song, query)) {
        continue;
      }
      const key = stableKeyOf(song);
      if (seen.has(key)) {
        continue;
      }
      seen.add(key);
      result.push(song);
    }
    return result;
  }
}
