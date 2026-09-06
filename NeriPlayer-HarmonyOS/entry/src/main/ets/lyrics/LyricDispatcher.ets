import { Logger } from '../app/Logger';
import { SettingsRepository } from '../data/SettingsRepository';
import { AmllLyricsResolver, AmllLyricsService } from './AmllLyricsResolver';
import { LrcParser } from './LrcParser';
import { AmllTtmlApi } from '../network/AmllTtmlApi';
import { LyricApi } from '../network/LyricApi';
import { LyricLine } from '../model/LyricLine';
import { MusicPlatform } from '../model/MusicPlatform';
import { SongItem } from '../model/SongItem';
import { stableKeyOf } from '../model/SongIdentity';

/**
 * Lyric source dispatch, mirroring the priority ladder of Android
 * PlayerLyricsProvider.getLyrics:
 *  - netease: platform lyrics (+translation/romalrc); AMLL is an upgrade
 *    source — consulted only when the platform lyrics lack word timings
 *    (loose duration matching).
 *  - YouTube Music: AMLL first with strict duration matching, then LRCLIB.
 *  - everything else: LRCLIB, then AMLL upgrade when LRCLIB returned no
 *    word timings.
 * AMLL failures are silent: it is an enhancement source, never a blocker.
 */
export class LyricDispatcher {
  static async loadLyrics(song: SongItem): Promise<LyricLine[]> {
    // An explicit「匹配歌曲信息」result wins over every automatic source:
    // it is the user's chosen lyric (and possibly translation) for this song.
    if (song.matchedLyric.trim().length > 0) {
      let parsed = LrcParser.parse(song.matchedLyric);
      parsed = LrcParser.mergeTranslation(parsed, song.matchedTranslatedLyric);
      return parsed;
    }
    const name = song.displayName;
    const artist = song.displayArtist;
    if (song.platform === MusicPlatform.NETEASE && song.audioId.length > 0) {
      const payload = await LyricApi.fetchFromNetease(Number(song.audioId));
      let parsed = LrcParser.parse(payload.lyric);
      parsed = LrcParser.mergeTranslation(parsed, payload.translated);
      parsed = LrcParser.mergePhonetic(parsed, payload.phonetic);
      if (!AmllLyricsResolver.hasWordTimings(parsed)) {
        const amll = await LyricDispatcher.tryAmll(song, false);
        if (amll !== null) {
          return amll;
        }
      }
      return parsed;
    }
    if (song.platform === MusicPlatform.YOUTUBE_MUSIC) {
      const amll = await LyricDispatcher.tryAmll(song, true);
      if (amll !== null) {
        return amll;
      }
    }
    const payload = await LyricApi.fetchFromLrcLib(name, artist, song.durationMs);
    let parsed = LrcParser.parse(payload.lyric);
    parsed = LrcParser.mergeTranslation(parsed, payload.translated);
    if (song.platform !== MusicPlatform.YOUTUBE_MUSIC && !AmllLyricsResolver.hasWordTimings(parsed)) {
      const amll = await LyricDispatcher.tryAmll(song, false);
      if (amll !== null) {
        return amll;
      }
    }
    return parsed;
  }

  private static async tryAmll(song: SongItem, requireDurationMatch: boolean): Promise<LyricLine[] | null> {
    if (!SettingsRepository.getBoolean(SettingsRepository.KEY_AMLL_LYRICS, true)) {
      return null;
    }
    if (song.displayName.length === 0) {
      return null;
    }
    try {
      return await AmllLyricsService.resolveForSong(
        stableKeyOf(song),
        song.displayName,
        song.displayArtist,
        song.durationMs,
        requireDurationMatch,
        AmllTtmlApi.searchLyrics,
        AmllTtmlApi.fetchRawLyrics
      );
    } catch (error) {
      const e = error as Error;
      Logger.info(`amll lyrics skipped: ${e.message}`);
      return null;
    }
  }
}
