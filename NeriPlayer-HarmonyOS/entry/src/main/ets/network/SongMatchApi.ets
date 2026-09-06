import { Logger } from '../app/Logger';
import { NeteaseApi } from './NeteaseApi';
import { QQMusicApi } from './QQMusicApi';

/**
 * Match-source facade for「匹配歌曲信息」: searches a metadata platform for a
 * song by keyword and turns the chosen candidate into full details (lyrics
 * included). A match source is where metadata/lyrics come from — it is NOT a
 * playable MusicPlatform, hence a separate enum instead of extending
 * model/MusicPlatform.ets.
 */
export enum MatchSource {
  NETEASE = 0,
  QQ = 1
}

export function matchSourceTag(source: MatchSource): string {
  return source === MatchSource.QQ ? 'qq' : 'netease';
}

export class MatchCandidate {
  source: MatchSource = MatchSource.NETEASE;
  /** Platform song id (netease numeric id as text, or QQ songMid). */
  id: string = '';
  name: string = '';
  artist: string = '';
  album: string = '';
  coverUrl: string = '';
  durationMs: number = 0;
}

export class MatchedSongDetail {
  source: MatchSource = MatchSource.NETEASE;
  id: string = '';
  name: string = '';
  artist: string = '';
  album: string = '';
  coverUrl: string = '';
  lyric: string = '';
  translatedLyric: string = '';
}

export class SongMatchApi {
  /** Both branches resolve to [] on failure — the sheet shows its own error state. */
  static async searchCandidates(source: MatchSource, keyword: string): Promise<MatchCandidate[]> {
    try {
      if (source === MatchSource.QQ) {
        const songs = await QQMusicApi.search(keyword, 1);
        return songs.map((song): MatchCandidate => {
          const candidate = new MatchCandidate();
          candidate.source = MatchSource.QQ;
          candidate.id = song.songMid;
          candidate.name = song.name;
          candidate.artist = song.artist;
          candidate.album = song.albumName;
          candidate.coverUrl = song.coverUrl;
          candidate.durationMs = song.durationMs;
          return candidate;
        });
      }
      const songs = await NeteaseApi.search(keyword, 30);
      return songs.map((song): MatchCandidate => {
        const candidate = new MatchCandidate();
        candidate.source = MatchSource.NETEASE;
        candidate.id = song.audioId.length > 0 ? song.audioId : `${song.id}`;
        candidate.name = song.name;
        candidate.artist = song.artist;
        candidate.album = song.album;
        candidate.coverUrl = song.effectiveCoverUrl;
        candidate.durationMs = song.durationMs;
        return candidate;
      });
    } catch (error) {
      const e = error as Error;
      Logger.warn(`SongMatchApi.searchCandidates(${source}) failed: ${e.message}`);
      return [];
    }
  }

  /**
   * QQ re-fetches detail + lyrics from the platform; netease candidates
   * already carry complete metadata, so only the lyric is fetched.
   */
  static async fetchDetail(candidate: MatchCandidate): Promise<MatchedSongDetail | null> {
    try {
      if (candidate.source === MatchSource.QQ) {
        const detail = await QQMusicApi.getSongInfo(candidate.id);
        if (detail === null) {
          return null;
        }
        const result = new MatchedSongDetail();
        result.source = MatchSource.QQ;
        result.id = detail.songMid;
        result.name = detail.name;
        result.artist = detail.artist;
        result.album = detail.albumName;
        result.coverUrl = detail.coverUrl;
        result.lyric = detail.lyric;
        result.translatedLyric = detail.translatedLyric;
        return result;
      }
      const payload = await NeteaseApi.getLyric(Number(candidate.id));
      const result = new MatchedSongDetail();
      result.source = MatchSource.NETEASE;
      result.id = candidate.id;
      result.name = candidate.name;
      result.artist = candidate.artist;
      result.album = candidate.album;
      result.coverUrl = candidate.coverUrl;
      result.lyric = payload.lyric;
      result.translatedLyric = payload.translated;
      return result;
    } catch (error) {
      const e = error as Error;
      Logger.warn(`SongMatchApi.fetchDetail(${candidate.id}) failed: ${e.message}`);
      return null;
    }
  }
}
