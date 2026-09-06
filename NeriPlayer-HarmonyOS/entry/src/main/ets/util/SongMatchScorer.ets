/**
 * Scores a「匹配歌曲信息」candidate against the expected title/artist/duration
 * for AUTO-apply (player/AutoSongMatcher). Same scoring style as the AMLL
 * resolver (lyrics/AmllLyricsResolver) but independent of it: adds a duration
 * bonus and a keyword-drift rejection — when an expected artist is known but
 * appears in neither the candidate's artist nor its title, the candidate is a
 * wrong search hit and must never be applied automatically. Pure functions,
 * unit-testable without any network or system API.
 */

const TITLE_EXACT_SCORE = 90;
const TITLE_PREFIX_SCORE = 78;
const TITLE_INCLUDES_SCORE = 64;
const TITLE_TOKEN_UNIT = 6;
const TITLE_TOKEN_CAP = 63;
const ARTIST_EXACT_SCORE = 55;
const ARTIST_INCLUDES_SCORE = 40;
const ARTIST_TOKEN_UNIT = 8;
const ARTIST_TOKEN_CAP = 39;
const DURATION_BONUS = 10;
const DURATION_TOLERANCE_MS = 8000;
const FOLD_RE = /[^0-9a-z\u00c0-\uffff]+/g;

export class SongMatchScorer {
  /** Total score at or above which a candidate may be applied unattended. */
  static readonly AUTO_APPLY_THRESHOLD = 70;

  /** NFKC fold + lowercase + "&"->"and" + drop feat/ft + separators to spaces. */
  static normalizeText(input: string): string {
    let text = input.normalize('NFKC').toLowerCase();
    text = text.split('&').join(' and ');
    text = text.replace(/\bfeat\.?\b|\bft\.?\b/g, ' ');
    // CJK quoting brackets sit inside FOLD_RE's keep range, so they are
    // folded explicitly (NFKC already maps fullwidth parentheses to ASCII).
    text = text.replace(/[()[\]{}【】《》〈〉「」『』・]/g, ' ');
    text = text.replace(FOLD_RE, ' ');
    return text.trim().replace(/\s+/g, ' ');
  }

  static tokenize(input: string): string[] {
    return SongMatchScorer.normalizeText(input).split(' ')
      .filter((token: string): boolean => token.length > 0);
  }

  private static tokenOverlap(expected: string[], candidate: string[]): number {
    let overlap = 0;
    for (const token of expected) {
      if (candidate.indexOf(token) >= 0) {
        overlap++;
      }
    }
    return overlap;
  }

  /** 0-145; see the constants above for the weight table. */
  static score(
    expectedTitle: string,
    expectedArtist: string,
    expectedDurationMs: number,
    candTitle: string,
    candArtist: string,
    candDurationMs: number
  ): number {
    const expected = SongMatchScorer.normalizeText(expectedTitle);
    const candidate = SongMatchScorer.normalizeText(candTitle);
    let titleScore = 0;
    if (expected.length > 0 && candidate.length > 0) {
      if (candidate === expected) {
        titleScore = TITLE_EXACT_SCORE;
      } else if (candidate.startsWith(expected)) {
        titleScore = TITLE_PREFIX_SCORE;
      } else if (candidate.includes(expected) || expected.includes(candidate)) {
        titleScore = TITLE_INCLUDES_SCORE;
      }
    }
    if (titleScore < TITLE_EXACT_SCORE) {
      const overlap = SongMatchScorer.tokenOverlap(
        SongMatchScorer.tokenize(expectedTitle), SongMatchScorer.tokenize(candTitle));
      titleScore = Math.max(titleScore, Math.min(overlap * TITLE_TOKEN_UNIT, TITLE_TOKEN_CAP));
    }
    let artistScore = 0;
    if (expectedArtist.length > 0 && candArtist.length > 0) {
      const expectedArtistFolded = SongMatchScorer.normalizeText(expectedArtist);
      const candidateArtistFolded = SongMatchScorer.normalizeText(candArtist);
      if (candidateArtistFolded === expectedArtistFolded) {
        artistScore = ARTIST_EXACT_SCORE;
      } else if (candidateArtistFolded.includes(expectedArtistFolded) || expectedArtistFolded.includes(candidateArtistFolded)) {
        artistScore = ARTIST_INCLUDES_SCORE;
      } else {
        const overlap = SongMatchScorer.tokenOverlap(
          SongMatchScorer.tokenize(expectedArtist), SongMatchScorer.tokenize(candArtist));
        artistScore = Math.min(overlap * ARTIST_TOKEN_UNIT, ARTIST_TOKEN_CAP);
      }
    }
    const durationClose = expectedDurationMs > 0 && candDurationMs > 0
      && Math.abs(expectedDurationMs - candDurationMs) < DURATION_TOLERANCE_MS;
    if (expectedArtist.length > 0 && artistScore === 0) {
      // The artist is absent from the candidate artist; it must at least show
      // up in the candidate title (e.g. the direction of a tight-dash split
      // was guessed wrong), otherwise the hit is unrelated. Exception: the
      // candidate title is fully contained in the expected one AND the
      // durations agree — video uploads carry the uploader as artist, which
      // never matches the real band. The duration gate keeps this from
      // letting "晴天" apply onto "晴天故事".
      const covered = candidate.length > 0 && expected.includes(candidate);
      if (!(covered && durationClose)) {
        const overlap = SongMatchScorer.tokenOverlap(
          SongMatchScorer.tokenize(expectedArtist), SongMatchScorer.tokenize(candTitle));
        if (overlap === 0) {
          return 0;
        }
      }
    }
    const durationScore = durationClose ? DURATION_BONUS : 0;
    return titleScore + artistScore + durationScore;
  }
}
