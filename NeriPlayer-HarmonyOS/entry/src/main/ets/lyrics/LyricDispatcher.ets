// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

import { LrcParser } from './LrcParser';
import { LyricApi } from '../network/LyricApi';
import { LyricLine } from '../model/LyricLine';
import { MusicPlatform } from '../model/MusicPlatform';
import { SongItem } from '../model/SongItem';

/**
 * Lyric source dispatch, mirroring the priority ladder of Android
 * PlayerLyricsProvider.getLyrics minus the AMLL word-timed TTML upgrade
 * source (removed together with the word-karaoke renderer; lyrics render
 * with the plain line highlight):
 *  - netease: platform lyrics (+translation/romalrc).
 *  - YouTube Music and everything else: LRCLIB.
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
      return parsed;
    }
    const payload = await LyricApi.fetchFromLrcLib(name, artist, song.durationMs);
    let parsed = LrcParser.parse(payload.lyric);
    parsed = LrcParser.mergeTranslation(parsed, payload.translated);
    return parsed;
  }
}
