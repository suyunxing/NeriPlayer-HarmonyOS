import { textProcessing, EntityType } from '@kit.NaturalLanguageKit';
import { Logger } from '../app/Logger';
import { SongItem } from '../model/SongItem';
import { stableKeyOf } from '../model/SongIdentity';
import { MatchCandidate, MatchSource, SongMatchApi, matchSourceTag } from '../network/SongMatchApi';
import { LocalPlaylistRepository } from '../data/LocalPlaylistRepository';
import { ExtractedTitle, NlpWord, SongTitleExtractor, TitleNlpAssistant } from '../util/SongTitleExtractor';
import { AutoMatchPolicy, MatchDetailPatch } from '../util/AutoMatchPolicy';
import { SongMatchScorer } from '../util/SongMatchScorer';

/**
 * Automatic counterpart of the manual「匹配歌曲信息」sheet: when a song starts
 * playing with missing metadata (no lyric, no artist, no cover) and has not
 * been matched in this session, extract a clean title (NaturalLanguageKit
 * segmentation/person-name entities on capable devices, filename heuristics
 * everywhere), search the match platform, score the candidates and silently
 * apply the best one above threshold. Fire-and-forget from loadSong: it must
 * never block or fail playback, so everything is swallowed into log lines.
 */

/** Playback-side effects, injected to keep this module free of a circular
 * PlayerManager import and the orchestrator itself out of unit tests. */
export interface AutoMatchPlaybackEnv {
  isCurrentSong(song: SongItem): boolean;
  applyToPlayerQueue(song: SongItem): void;
}

/** AppStorage key bumped after a match landed on the current song so the
 * NowPlaying page reloads its lyrics (cover refresh rides the regular
 * currentSong publish). */
const AUTO_MATCH_TICK_KEY = 'player.autoMatchTick';
const SEARCH_SOURCE = MatchSource.NETEASE;

class ScoredCandidate {
  candidate: MatchCandidate;
  score: number;

  constructor(candidate: MatchCandidate, score: number) {
    this.candidate = candidate;
    this.score = score;
  }
}

/**
 * textProcessing adapter: the Kit has no music entity type and is real-device
 * / mainland-China only (not even the emulator), so every failure —
 * unsupported syscap, engine busy (1011200002), timeout (200) — resolves []
 * and the extractor degrades to pure filename heuristics. The Kit rejects
 * concurrent calls of the same feature; the attempted-keys guard below keeps
 * auto-match single-flight, and the manual sheet never runs this path.
 */
class SystemNlpAssistant implements TitleNlpAssistant {
  private static supported: boolean | null = null;
  /** Client-side guard: on images that claim the syscap but lack a working
   * engine (some emulator images), the service promise may never settle and
   * would silently stall the whole auto-match chain. */
  private static readonly CALL_TIMEOUT_MS = 5000;

  private static isSupported(): boolean {
    if (SystemNlpAssistant.supported === null) {
      try {
        SystemNlpAssistant.supported = canIUse('SystemCapability.AI.NaturalLanguage.TextProcessing');
      } catch (error) {
        SystemNlpAssistant.supported = false;
      }
    }
    return SystemNlpAssistant.supported;
  }

  private static withTimeout<T>(promise: Promise<T>): Promise<T> {
    return new Promise<T>((resolve: (value: T) => void, reject: (reason: Error) => void) => {
      const timer = setTimeout(() => {
        reject(new Error(`nlp call timed out after ${SystemNlpAssistant.CALL_TIMEOUT_MS}ms`));
      }, SystemNlpAssistant.CALL_TIMEOUT_MS);
      promise.then((value: T) => {
        clearTimeout(timer);
        resolve(value);
      }, (reason: Error) => {
        clearTimeout(timer);
        reject(reason);
      });
    });
  }

  async segmentWords(text: string): Promise<NlpWord[]> {
    if (!SystemNlpAssistant.isSupported() || text.trim().length === 0) {
      return [];
    }
    try {
      const segments = await SystemNlpAssistant.withTimeout(textProcessing.getWordSegment(text));
      return segments.map((segment: textProcessing.WordSegment): NlpWord => {
        return { word: segment.word, wordTag: segment.wordTag };
      });
    } catch (error) {
      const e = error as Error;
      Logger.info(`AutoSongMatcher word segment skipped: ${e.message}`);
      return [];
    }
  }

  async extractPersonNames(text: string): Promise<string[]> {
    if (!SystemNlpAssistant.isSupported() || text.trim().length === 0) {
      return [];
    }
    try {
      const entities = await SystemNlpAssistant.withTimeout(
        textProcessing.getEntity(text, { entityTypes: [EntityType.NAME] }));
      return entities.map((entity: textProcessing.Entity): string => entity.text);
    } catch (error) {
      const e = error as Error;
      Logger.info(`AutoSongMatcher entity extraction skipped: ${e.message}`);
      return [];
    }
  }
}

export class AutoSongMatcher {
  private static readonly attemptedKeys: Set<string> = new Set();
  private static readonly manualQueriedKeys: Set<string> = new Set();
  private static readonly nlp: TitleNlpAssistant = new SystemNlpAssistant();

  /** The user opened the manual sheet for this song: auto-match stands down
   * for the rest of the session (an applied match also clears the missing-
   * metadata condition on its own). */
  static markManualQuery(song: SongItem): void {
    AutoSongMatcher.manualQueriedKeys.add(stableKeyOf(song));
  }

  static buildSearchKeyword(info: ExtractedTitle, fallbackArtist: string): string {
    return AutoMatchPolicy.buildSearchKeyword(info, fallbackArtist);
  }

  /**
   * Second-chance keyword for video-style names ("《show》官方MV「song」中文字幕"):
   * the whole-name query drifts into unrelated hits, so retry with the quoted
   * song name alone — the corner segment when the extractor did not already
   * promote it, otherwise the bare title without the uploader suffix. Empty
   * (no retry) for names without such quoting, keeping plain files at one
   * search request per song.
   */
  static fallbackKeyword(info: ExtractedTitle, primary: string, displayName: string): string {
    const segments = SongTitleExtractor.bracketedSegments(displayName);
    if (segments.length === 0) {
      return '';
    }
    const title = info.title.trim();
    const fallback = segments.indexOf(title) >= 0 ? title : segments[0];
    return fallback === primary ? '' : fallback;
  }

  /** One search + scoring pass; null when nothing clears the threshold. */
  private static async pickBestMatch(keyword: string, info: ExtractedTitle, song: SongItem): Promise<ScoredCandidate | null> {
    Logger.info(`AutoSongMatcher searching "${keyword}" for ${song.displayName}`);
    const candidates = await SongMatchApi.searchCandidates(SEARCH_SOURCE, keyword);
    let best: MatchCandidate | null = null;
    let bestScore = 0;
    for (const candidate of candidates) {
      const score = SongMatchScorer.score(
        info.title, song.displayArtist, song.durationMs,
        candidate.name, candidate.artist, candidate.durationMs);
      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }
    if (best === null || bestScore < SongMatchScorer.AUTO_APPLY_THRESHOLD) {
      Logger.info(`AutoSongMatcher no confident candidate for "${keyword}" (best ${bestScore} of ${candidates.length} hits)`);
      return null;
    }
    return new ScoredCandidate(best, bestScore);
  }

  /**
   * Entry hook for PlayerManager.loadSong (fire-and-forget). At most one
   * attempt per song per session, regardless of outcome, to stay friendly to
   * the search platform's risk control (an attempt is at most two searches).
   */
  static async maybeAutoMatch(song: SongItem, env: AutoMatchPlaybackEnv): Promise<void> {
    const key = stableKeyOf(song);
    try {
      if (AutoSongMatcher.manualQueriedKeys.has(key) || AutoSongMatcher.attemptedKeys.has(key)) {
        return;
      }
      if (!AutoMatchPolicy.hasMissingMetadata(song) || song.displayName.trim().length === 0) {
        return;
      }
      AutoSongMatcher.attemptedKeys.add(key);
      const info = await SongTitleExtractor.extract(song.displayName, AutoSongMatcher.nlp);
      if (info.title.trim().length === 0) {
        return;
      }
      const keyword = AutoMatchPolicy.buildSearchKeyword(info, song.displayArtist);
      let picked = await AutoSongMatcher.pickBestMatch(keyword, info, song);
      if (picked === null) {
        const retry = AutoSongMatcher.fallbackKeyword(info, keyword, song.displayName);
        if (retry.length > 0) {
          picked = await AutoSongMatcher.pickBestMatch(retry, info, song);
        }
      }
      if (picked === null) {
        return;
      }
      const best = picked.candidate;
      const detail = await SongMatchApi.fetchDetail(best);
      if (detail === null) {
        return;
      }
      const patch: MatchDetailPatch = {
        source: matchSourceTag(detail.source),
        id: detail.id,
        name: detail.name,
        artist: detail.artist,
        coverUrl: detail.coverUrl,
        lyric: detail.lyric,
        translatedLyric: detail.translatedLyric
      };
      const updated = AutoMatchPolicy.buildMatchUpdate(song, patch);
      if (updated === null) {
        return;
      }
      // Playlist copies are updated regardless of what is on air; the queue /
      // AVSession / lyric refresh only for the song still playing (a newer
      // loadSong must not receive a stale match).
      const replaced = await LocalPlaylistRepository.updateSongMetadata(updated);
      if (env.isCurrentSong(song)) {
        env.applyToPlayerQueue(updated);
        AppStorage.setOrCreate(AUTO_MATCH_TICK_KEY, Date.now());
      }
      Logger.info(`AutoSongMatcher applied ${detail.name} - ${detail.artist} to ${updated.displayName} (score ${picked.score}, ${replaced} playlist entries)`);
    } catch (error) {
      const e = error as Error;
      Logger.warn(`AutoSongMatcher failed for ${song.displayName}: ${e.message}`);
    }
  }
}
