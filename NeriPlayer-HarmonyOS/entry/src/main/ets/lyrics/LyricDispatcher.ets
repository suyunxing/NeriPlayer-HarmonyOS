// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

import { LrcParser } from './LrcParser';
import { LyricApi } from '../network/LyricApi';
import { LyricLine } from '../model/LyricLine';
import { MusicPlatform } from '../model/MusicPlatform';
import { SongItem } from '../model/SongItem';
import { stableKeyOf } from '../model/SongIdentity';
import { Logger } from '../app/Logger';
import { NeteaseApi } from '../network/NeteaseApi';
import { SongMatchScorer } from '../util/SongMatchScorer';

/** Session-level supplement cache entry: one netease lyric payload per song key. */
class NeteaseSupplementEntry {
  payloadLyric: string = '';
  payloadTranslated: string = '';
  payloadPhonetic: string = '';
}

/**
 * True when the parsed lines carry no translation or no romanization at all
 * (upstream #483): LRCLIB results never do, so a duration-guarded netease
 * lookup should fill the gap instead of leaving the rows mute.
 */
export function shouldSupplementLyrics(lines: LyricLine[]): boolean {
  if (lines.length === 0) {
    return true;
  }
  let hasTranslation = false;
  let hasPhonetic = false;
  for (const line of lines) {
    if (line.translated.length > 0) {
      hasTranslation = true;
    }
    if (line.phonetic.length > 0) {
      hasPhonetic = true;
    }
  }
  return !hasTranslation || !hasPhonetic;
}

/**
 * Picks the best-scoring netease search candidate for the expected song, or
 * null when nothing clears the auto-apply threshold (title/artist tokens plus
 * the ±8s duration guard inside SongMatchScorer — the cross-source duration
 * guard of upstream #417). Pure and unit-testable.
 */
export function pickBestNeteaseCandidate(expected: SongItem,
  candidates: SongItem[]): SongItem | null {
  let best: SongItem | null = null;
  let bestScore = 0;
  for (const candidate of candidates) {
    const score = SongMatchScorer.score(expected.displayName, expected.displayArtist,
      expected.durationMs, candidate.displayName, candidate.displayArtist, candidate.durationMs);
    if (score > bestScore) {
      best = candidate;
      bestScore = score;
    }
  }
  return bestScore >= SongMatchScorer.AUTO_APPLY_THRESHOLD ? best : null;
}

/**
 * Lyric source dispatch, mirroring the priority ladder of Android
 * PlayerLyricsProvider.getLyrics minus the AMLL word-timed TTML upgrade
 * source (removed together with the word-karaoke renderer; lyrics render
 * with the plain line highlight):
 *  - netease: platform lyrics (+translation/romalrc).
 *  - YouTube Music and everything else: LRCLIB, supplemented by a
 *    duration-guarded netease lookup for translation/romaji (#483).
 */
export class LyricDispatcher {
  private static supplementCache: Map<string, NeteaseSupplementEntry> = new Map<string, NeteaseSupplementEntry>();
  private static readonly SUPPLEMENT_CACHE_CAP: number = 50;

  static async loadLyrics(song: SongItem): Promise<LyricLine[]> {
    // An explicit「匹配歌曲信息」result wins over every automatic source:
    // it is the user's chosen lyric (and possibly translation) for this song.
    if (song.matchedLyric.trim().length > 0) {
      let parsed = LrcParser.parse(song.matchedLyric);
      parsed = LrcParser.mergeTranslation(parsed, song.matchedTranslatedLyric);
      parsed = LrcParser.mergePhonetic(parsed, song.matchedPhoneticLyric);
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
    parsed = LrcParser.mergePhonetic(parsed, payload.phonetic);
    if (shouldSupplementLyrics(parsed)) {
      const supplement = await LyricDispatcher.neteaseSupplement(song);
      if (parsed.length === 0 && supplement.payloadLyric.length > 0) {
        parsed = LrcParser.parse(supplement.payloadLyric);
      }
      parsed = LrcParser.mergeTranslation(parsed, supplement.payloadTranslated);
      parsed = LrcParser.mergePhonetic(parsed, supplement.payloadPhonetic);
    }
    return parsed;
  }

  /**
   * Cross-source supplement: search netease by name+artist, accept the hit
   * only through the scored duration/keyword guard, then fetch its lyric
   * payload for the translation/romaji blocks. Failures resolve to an empty
   * entry (cached too) — a supplement miss must never mask the LRCLIB lines.
   */
  private static async neteaseSupplement(song: SongItem): Promise<NeteaseSupplementEntry> {
    const key = stableKeyOf(song);
    const cached = LyricDispatcher.supplementCache.get(key);
    if (cached !== undefined) {
      return cached;
    }
    const entry = new NeteaseSupplementEntry();
    try {
      const keyword = song.displayName.length > 0
        ? `${song.displayName} ${song.displayArtist}`.trim() : song.displayArtist;
      if (keyword.trim().length > 0) {
        const candidates = await NeteaseApi.search(keyword, 10);
        const best = pickBestNeteaseCandidate(song, candidates);
        if (best !== null) {
          const id = best.audioId.length > 0 ? Number(best.audioId) : best.id;
          if (!Number.isNaN(id) && id > 0) {
            const payload = await NeteaseApi.getLyric(id);
            entry.payloadLyric = payload.lyric;
            entry.payloadTranslated = payload.translated;
            entry.payloadPhonetic = payload.phonetic;
          }
        }
      }
    } catch (error) {
      const e = error as Error;
      // Empty entry below: lyric display continues from the primary source.
      Logger.debug(`neteaseSupplement(${song.displayName}) skipped: ${e.message}`);
    }
    LyricDispatcher.cacheSupplement(key, entry);
    return entry;
  }

  private static cacheSupplement(key: string, entry: NeteaseSupplementEntry): void {
    if (LyricDispatcher.supplementCache.size >= LyricDispatcher.SUPPLEMENT_CACHE_CAP) {
      const oldest = LyricDispatcher.supplementCache.keys().next();
      if (!oldest.done) {
        LyricDispatcher.supplementCache.delete(oldest.value);
      }
    }
    LyricDispatcher.supplementCache.set(key, entry);
  }
}
