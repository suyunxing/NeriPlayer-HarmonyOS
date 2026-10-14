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
import { SettingsRepository } from '../data/SettingsRepository';
import { SchemaStore } from '../data/schema/SchemaStore';
import { LyricCacheStore, LyricSourceTag, DEFAULT_LYRIC_CACHE_ENTRIES } from './LyricCacheStore';

/** Session-level supplement cache entry: one netease lyric payload per song key. */
class NeteaseSupplementEntry {
  payloadLyric: string = '';
  payloadTranslated: string = '';
  payloadPhonetic: string = '';
}

/** Resolved lyric payload plus the source it came from (offsets + cache). */
export class LyricLoadResult {
  lines: LyricLine[] = [];
  source: LyricSourceTag = LyricSourceTag.LRCLIB;

  constructor(lines: LyricLine[], source: LyricSourceTag) {
    this.lines = lines;
    this.source = source;
  }
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
 *  - matched: user-chosen「匹配歌曲信息」lyrics win over every source.
 *  - netease: platform lyrics (+translation/romalrc).
 *  - YouTube Music/local and everything else: LRCLIB, supplemented by a
 *    duration-guarded netease lookup for translation/romaji (#483); the
 *    np.lyric_source_preference setting can promote that guarded netease
 *    hit to the primary lyric (#417).
 *
 * Resolved network results are persisted into an LRU cache table (#349) so
 * replays and offline sessions show lyrics without re-fetching.
 */
export class LyricDispatcher {
  private static supplementCache: Map<string, NeteaseSupplementEntry> = new Map<string, NeteaseSupplementEntry>();
  private static readonly SUPPLEMENT_CACHE_CAP: number = 50;

  private static cache: LyricCacheStore | null = null;
  private static cacheReady: Promise<void> | null = null;
  private static readonly CACHE_SCHEMA_KEY: string = 'lyric_cache';

  /** Compatibility wrapper (download sidecar etc.): lines only. */
  static async loadLyrics(song: SongItem): Promise<LyricLine[]> {
    const result = await LyricDispatcher.loadLyricsResolved(song);
    return result.lines;
  }

  static async loadLyricsResolved(song: SongItem): Promise<LyricLoadResult> {
    // An explicit「匹配歌曲信息」result wins over every automatic source:
    // it is the user's chosen lyric (and possibly translation) for this song.
    if (song.matchedLyric.trim().length > 0) {
      let parsed = LrcParser.parse(song.matchedLyric);
      parsed = LrcParser.mergeTranslation(parsed, song.matchedTranslatedLyric);
      parsed = LrcParser.mergePhonetic(parsed, song.matchedPhoneticLyric);
      return new LyricLoadResult(parsed, LyricSourceTag.MATCHED);
    }
    const cacheEnabled = SettingsRepository.getBoolean(SettingsRepository.KEY_LYRIC_CACHE_ENABLED, true);
    const key = stableKeyOf(song);
    if (cacheEnabled) {
      await LyricDispatcher.ensureCache();
      const cache = LyricDispatcher.cache;
      if (cache !== null) {
        const hit = cache.lookup(key, Date.now());
        if (hit !== null) {
          LyricDispatcher.persistCache();
          return new LyricLoadResult(hit.lines, hit.source);
        }
      }
    }
    const result = await LyricDispatcher.fetchLyrics(song);
    if (cacheEnabled && result.lines.length > 0) {
      await LyricDispatcher.ensureCache();
      const cache = LyricDispatcher.cache;
      if (cache !== null && cache.record(key, result.source, result.lines, Date.now(), DEFAULT_LYRIC_CACHE_ENTRIES)) {
        LyricDispatcher.persistCache();
      }
    }
    return result;
  }

  private static async fetchLyrics(song: SongItem): Promise<LyricLoadResult> {
    if (song.platform === MusicPlatform.NETEASE && song.audioId.length > 0) {
      const payload = await LyricApi.fetchFromNetease(Number(song.audioId));
      let parsed = LrcParser.parse(payload.lyric);
      parsed = LrcParser.mergeTranslation(parsed, payload.translated);
      parsed = LrcParser.mergePhonetic(parsed, payload.phonetic);
      return new LyricLoadResult(parsed, LyricSourceTag.NETEASE);
    }
    // np.lyric_source_preference (#417): 'netease_first' promotes a
    // duration-guarded netease hit to the primary lyric — users who care
    // about built-in translations get them on the first try.
    const preference = SettingsRepository.getString(
      SettingsRepository.KEY_LYRIC_SOURCE_PREFERENCE, 'lrclib_first');
    if (preference === 'netease_first') {
      const supplement = await LyricDispatcher.neteaseSupplement(song);
      if (supplement.payloadLyric.length > 0) {
        let parsed = LrcParser.parse(supplement.payloadLyric);
        parsed = LrcParser.mergeTranslation(parsed, supplement.payloadTranslated);
        parsed = LrcParser.mergePhonetic(parsed, supplement.payloadPhonetic);
        if (parsed.length > 0) {
          return new LyricLoadResult(parsed, LyricSourceTag.NETEASE);
        }
      }
    }
    const payload = await LyricApi.fetchFromLrcLib(song.displayName, song.displayArtist, song.durationMs);
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
    return new LyricLoadResult(parsed, LyricSourceTag.LRCLIB);
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

  private static ensureCache(): Promise<void> {
    if (LyricDispatcher.cacheReady === null) {
      LyricDispatcher.cacheReady = SchemaStore.load(
        LyricDispatcher.CACHE_SCHEMA_KEY,
        new LyricCacheStore(),
        (json: string): LyricCacheStore | null => LyricCacheStore.fromJson(json)
      ).then((loaded: LyricCacheStore) => {
        LyricDispatcher.cache = loaded;
      }).catch((error: Error) => {
        Logger.warn(`LyricDispatcher cache load failed: ${error.message}`);
        LyricDispatcher.cache = new LyricCacheStore();
      });
    }
    return LyricDispatcher.cacheReady;
  }

  private static persistCache(): void {
    const cache = LyricDispatcher.cache;
    if (cache === null) {
      return;
    }
    SchemaStore.save(LyricDispatcher.CACHE_SCHEMA_KEY, cache, (value: LyricCacheStore): string => value.toJson())
      .catch((error: Error) => {
        Logger.warn(`LyricDispatcher cache persist failed: ${error.message}`);
      });
  }

  /** Settings「清除歌词缓存」入口（F-8 存储分区接线）。 */
  static async clearPersistentCache(): Promise<void> {
    await LyricDispatcher.ensureCache();
    const cache = LyricDispatcher.cache;
    if (cache !== null) {
      cache.clear();
      LyricDispatcher.persistCache();
    }
  }

  /** F-8 存储分析：歌词缓存条目数（preferences 值，字节量小按条计）。 */
  static async cachedLyricEntryCount(): Promise<number> {
    await LyricDispatcher.ensureCache();
    const cache = LyricDispatcher.cache;
    return cache !== null ? cache.size() : 0;
  }
}
