import { SongItem } from '../model/SongItem';
import { ExtractedTitle } from './SongTitleExtractor';

/**
 * Pure decision layer of the automatic「匹配歌曲信息」flow (the player/
 * AutoSongMatcher orchestrator applies these). No platform imports, so the
 * local hypium environment can test the fill-only-what-is-missing semantics
 * without a queue, network, or the NaturalLanguageKit.
 */

/** Normalized「匹配歌曲信息」result handed to buildMatchUpdate. Kept separate
 * from network/SongMatchApi.MatchedSongDetail so this file stays free of the
 * HTTP-client import chain. */
export interface MatchDetailPatch {
  /** matchSourceTag value ('netease' | 'qq'). */
  source: string;
  id: string;
  name: string;
  artist: string;
  coverUrl: string;
  lyric: string;
  translatedLyric: string;
}

export class AutoMatchPolicy {
  /** A song is auto-matched when any of lyric / artist / cover is absent. */
  static hasMissingMetadata(song: SongItem): boolean {
    return song.matchedLyric.trim().length === 0
      || song.displayArtist.trim().length === 0
      || song.effectiveCoverUrl.trim().length === 0;
  }

  /** Search keyword: cleaned title first, extracted artist before the
   * existing display artist; title alone when neither artist is known. */
  static buildSearchKeyword(info: ExtractedTitle, fallbackArtist: string): string {
    const artist = info.artist.trim().length > 0 ? info.artist.trim() : fallbackArtist.trim();
    return artist.length > 0 ? `${info.title} ${artist}` : info.title;
  }

  /**
   * Fills only what the song is missing (same custom-star / matched-star
   * field conventions as the manual sheet: custom overrides only when they
   * differ from the original, '' means no override) and never overwrites an
   * existing artist/cover. The matched song id is only stamped alongside a
   * lyric, the primary missing piece.
   * Returns null when the detail adds nothing worth persisting.
   */
  static buildMatchUpdate(base: SongItem, detail: MatchDetailPatch): SongItem | null {
    const updated = SongItem.fromJson(base.toJson());
    let changed = false;
    if (detail.name.length > 0 && detail.name !== base.name) {
      updated.customName = detail.name;
      changed = true;
    }
    if (base.displayArtist.trim().length === 0 && detail.artist.length > 0 && detail.artist !== base.artist) {
      updated.customArtist = detail.artist;
      changed = true;
    }
    if (base.effectiveCoverUrl.trim().length === 0 && detail.coverUrl.length > 0 && detail.coverUrl !== base.coverUrl) {
      updated.customCoverUrl = detail.coverUrl;
      changed = true;
    }
    if (detail.lyric.length > 0 && detail.lyric !== base.matchedLyric) {
      updated.matchedLyric = detail.lyric;
      updated.matchedTranslatedLyric = detail.translatedLyric;
      updated.matchedSongId = `${detail.source}:${detail.id}`;
      changed = true;
    }
    return changed ? updated : null;
  }
}
