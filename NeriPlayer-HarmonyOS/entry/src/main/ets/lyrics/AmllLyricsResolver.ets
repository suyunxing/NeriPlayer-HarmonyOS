import { LyricLine } from '../model/LyricLine';
import { AmllSearchResult } from '../network/AmllTtmlApi';
import { TtmlParser } from './TtmlParser';

/**
 * AMLL lyrics selection pipeline, mirroring Android AmllLyricsResolver +
 * scoreAmllSearchResult/isAmllDurationCompatible: normalize both sides of the
 * comparison (NFKC-ish fold, lowercase, & -> and, strip feat/parentheses and
 * symbols), score title/artist matches, drop results whose artist score is
 * too low, then walk the top 5 candidates fetching raw TTML until one parses
 * with word timings AND (optionally) matches the track duration.
 *
 * Pure logic with injected fetchers so tests run without @ohos APIs; the
 * network-bound wrapper is AmllLyricsService below.
 */

export const AMLL_MIN_SEARCH_MATCH_SCORE = 70;
export const AMLL_MIN_ARTIST_SCORE = 30;
const AMLL_CANDIDATE_LIMIT = 5;
const AMLL_CACHE_CAPACITY = 32;

export type AmllSearchFetcher = (trackName: string) => Promise<AmllSearchResult[]>;
export type AmllRawFetcher = (file: string) => Promise<string>;

export class AmllDurationCheck {
  readonly compatible: boolean;
  readonly lyricsDurationMs: number;

  constructor(compatible: boolean, lyricsDurationMs: number) {
    this.compatible = compatible;
    this.lyricsDurationMs = lyricsDurationMs;
  }
}

export class AmllLyricsResolver {
  /**
   * Duration tolerance from Android: lyrics ending early (before the track)
   * may differ by max(12s, 10% of track) capped at 30s; lyrics running past
   * the track may differ by max(30s, 15%) capped at 60s (TTML last lines end
   * before audio, so the past-side window is wider).
   */
  static isDurationCompatible(trackDurationMs: number, lyricsDurationMs: number): AmllDurationCheck {
    if (lyricsDurationMs <= 0) {
      return new AmllDurationCheck(false, lyricsDurationMs);
    }
    const diff = lyricsDurationMs - trackDurationMs;
    if (diff <= 0) {
      const tolerance = Math.min(30000, Math.max(12000, trackDurationMs * 0.1));
      return new AmllDurationCheck(-diff <= tolerance, lyricsDurationMs);
    }
    const tolerance = Math.min(60000, Math.max(30000, trackDurationMs * 0.15));
    return new AmllDurationCheck(diff <= tolerance, lyricsDurationMs);
  }

  /** NFKC-style fold + lowercase + "&"->"and" + drop feat/ft markers and
   * bracket characters themselves (bracketed content is kept, matching the
   * Android normalization test: "Ｈｅｌｌｏ（World）" -> "hello world"). */
  static normalizeSearchText(input: string): string {
    let text = input.normalize('NFKC').toLowerCase();
    text = text.split('&').join(' and ');
    text = text.replace(/\bfeat\.?\b|\bft\.?\b/g, ' ');
    text = text.replace(/[()[\]{}]/g, ' ');
    text = text.replace(/[^0-9a-z\u00c0-\uffff]+/g, ' ');
    return text.trim().replace(/\s+/g, ' ');
  }

  static tokenize(text: string): string[] {
    return AmllLyricsResolver.normalizeSearchText(text).split(' ').filter((token: string): boolean => token.length > 0);
  }

  /** (titleScore, artistScore) per Android scoreAmllSearchResult. */
  static scoreCandidate(trackName: string, artistName: string, candidateTitle: string, candidateArtist: string): [number, number] {
    const trackTokens = AmllLyricsResolver.tokenize(trackName);
    const candidateTokens = AmllLyricsResolver.tokenize(candidateTitle);
    let titleScore = 0;
    if (candidateTitle.length > 0) {
      const track = AmllLyricsResolver.normalizeSearchText(trackName);
      const candidate = AmllLyricsResolver.normalizeSearchText(candidateTitle);
      if (candidate === track && track.length > 0) {
        titleScore = 90;
      } else if (candidate.startsWith(track) && track.length > 0) {
        titleScore = 78;
      } else if ((candidate.includes(track) || track.includes(candidate)) && track.length > 0) {
        titleScore = 64;
      }
    }
    if (titleScore < 90 && trackTokens.length > 0) {
      let overlap = 0;
      for (const token of trackTokens) {
        if (candidateTokens.indexOf(token) >= 0) {
          overlap += 1;
        }
      }
      titleScore = Math.max(titleScore, Math.min(overlap * 6, 63));
    }
    let artistScore = 0;
    if (candidateArtist.length > 0 && artistName.length > 0) {
      const artist = AmllLyricsResolver.normalizeSearchText(artistName);
      const candidate = AmllLyricsResolver.normalizeSearchText(candidateArtist);
      if (candidate === artist) {
        artistScore = 55;
      } else if (candidate.includes(artist) || artist.includes(candidate)) {
        artistScore = 40;
      }
    }
    if (artistScore === 0 && artistName.length > 0) {
      const artistTokens = AmllLyricsResolver.tokenize(artistName);
      const candidateTokens2 = AmllLyricsResolver.tokenize(candidateArtist);
      let overlap = 0;
      for (const token of artistTokens) {
        if (candidateTokens2.indexOf(token) >= 0) {
          overlap += 1;
        }
      }
      artistScore = Math.min(overlap * 8, AMLL_MIN_ARTIST_SCORE - 1);
    }
    return [titleScore, artistScore];
  }

  /** Ranked candidates that pass the artist floor and total threshold. */
  static rankCandidates(
    trackName: string,
    artistName: string,
    results: AmllSearchResult[]
  ): AmllSearchResult[] {
    const scored: [number, number, AmllSearchResult][] = [];
    for (const result of results) {
      const scores = AmllLyricsResolver.scoreCandidate(trackName, artistName, result.title, result.artist);
      const titleScore = scores[0];
      const artistScore = scores[1];
      if (artistScore < AMLL_MIN_ARTIST_SCORE) {
        continue;
      }
      const total = titleScore + artistScore;
      if (total < AMLL_MIN_SEARCH_MATCH_SCORE) {
        continue;
      }
      scored.push([total, result.score, result]);
    }
    scored.sort((a: [number, number, AmllSearchResult], b: [number, number, AmllSearchResult]): number => {
      if (a[0] !== b[0]) {
        return b[0] - a[0];
      }
      return b[1] - a[1];
    });
    return scored.map((entry: [number, number, AmllSearchResult]): AmllSearchResult => entry[2]);
  }

  static lyricsDurationMs(lines: LyricLine[]): number {
    if (lines.length === 0) {
      return 0;
    }
    return lines[lines.length - 1].endTimeMs;
  }

  static hasWordTimings(lines: LyricLine[]): boolean {
    for (const line of lines) {
      if (line.words.length > 0) {
        return true;
      }
    }
    return false;
  }

  /**
   * Full pipeline. requireDurationMatch=true (YTM path) rejects candidates
   * whose duration is off; false (netease upgrade path) accepts any parsed
   * word-timed candidate.
   */
  static async resolve(
    trackName: string,
    artistName: string,
    trackDurationMs: number,
    search: AmllSearchFetcher,
    fetchRaw: AmllRawFetcher,
    requireDurationMatch: boolean
  ): Promise<LyricLine[] | null> {
    const results = await search(trackName);
    const candidates = AmllLyricsResolver.rankCandidates(trackName, artistName, results).slice(0, AMLL_CANDIDATE_LIMIT);
    for (const candidate of candidates) {
      let raw = '';
      try {
        raw = await fetchRaw(candidate.file);
      } catch (error) {
        void error;
        continue;
      }
      const lines = TtmlParser.parse(raw);
      if (lines === null || !AmllLyricsResolver.hasWordTimings(lines)) {
        continue;
      }
      if (requireDurationMatch) {
        const check = AmllLyricsResolver.isDurationCompatible(trackDurationMs, AmllLyricsResolver.lyricsDurationMs(lines));
        if (!check.compatible) {
          continue;
        }
      }
      return lines;
    }
    return null;
  }
}

/**
 * Production wrapper: binds the HTTP fetchers and a small result cache keyed
 * like Android's PlayerLyricsProvider cache (identity-ish key + duration
 * match mode), capacity 32.
 */
export class AmllLyricsService {
  private static readonly cache: Map<string, LyricLine[] | null> = new Map<string, LyricLine[] | null>();

  static clearCache(): void {
    AmllLyricsService.cache.clear();
  }

  static async resolveForSong(
    stableKey: string,
    trackName: string,
    artistName: string,
    durationMs: number,
    requireDurationMatch: boolean,
    search: AmllSearchFetcher,
    fetchRaw: AmllRawFetcher
  ): Promise<LyricLine[] | null> {
    const key = `${stableKey}|${trackName}|${artistName}|${durationMs}|${requireDurationMatch}`;
    const hit = AmllLyricsService.cache.get(key);
    if (hit !== undefined) {
      return hit;
    }
    const lines = await AmllLyricsResolver.resolve(trackName, artistName, durationMs, search, fetchRaw, requireDurationMatch);
    if (lines !== null) {
      if (AmllLyricsService.cache.size >= AMLL_CACHE_CAPACITY) {
        const oldest = AmllLyricsService.cache.keys().next();
        if (!oldest.done) {
          AmllLyricsService.cache.delete(oldest.value);
        }
      }
      AmllLyricsService.cache.set(key, lines);
    }
    return lines;
  }
}
