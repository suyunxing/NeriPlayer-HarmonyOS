// SPDX-License-Identifier: GPL-3.0

/**
 * Extracts a searchable (title, artist) pair from a raw display name or file
 * name ("01 周杰伦 - 晴天 [FLAC].mp3" -> 晴天 / 周杰伦). Regex heuristics run
 * everywhere; an optional NaturalLanguageKit assistant (real devices,
 * mainland China only) disambiguates no-separator Chinese names and
 * artist-title direction. Dependency-free so unit tests can drive it with
 * fakes; every NLP path degrades to the plain heuristics when unavailable.
 */

export interface NlpWord {
  word: string;
  wordTag: string;
}

export interface ExtractedTitle {
  title: string;
  artist: string;
}

/** Implemented by the NaturalLanguageKit adapter in player/AutoSongMatcher. */
export interface TitleNlpAssistant {
  /** Word segmentation with part-of-speech tags; resolves [] on failure. */
  segmentWords(text: string): Promise<NlpWord[]>;
  /** Person-name entities (EntityType.NAME); resolves [] on failure. */
  extractPersonNames(text: string): Promise<string[]>;
}

const AUDIO_EXTENSION_RE = /\.(mp3|flac|m4a|aac|wav|ogg|oga|opus|wma|ape|dsf|dff|aiff?|alac|wv|tta|tak)$/i;
// 2-3 digits only: "7 rings" and "2002" are songs, "01 晴天" and "010 晴天" are tracks.
const TRACK_NUMBER_RE = /^(\d{2,3})([\s._-]+)(.+)$/;
const NOISE_LABEL_RE = /(official|mv\b|pv\b|video|audio|lyric|visualizer|instrumental|hd\b|4k|8k|60fps|flac|mp3|aac|wav|opus|kbps|bit|hi-?res|lossless|hq\b|音质|无损|高清|官方|完整版|歌词|歌詞|字幕)/i;
const BRACKETED_RE = /([([{（【《「『])([^\])}】》」』]*)([\])}】》」』])/g;
// Corner brackets usually quote the song name inside a video-style title
// ("《show》官方MV「song」中文字幕"); book-title brackets quote the show itself.
const CORNER_SEGMENT_RE = /[「『]([^「」『』]{2,})[」』]/g;
const BOOK_SEGMENT_RE = /《([^《》]{2,})》/g;
// Lenticular brackets tag the upload itself (【洛天依原创】, 【MAD】, 【9.1万粉
// 感谢】) and never hold the song name, unlike the quoting brackets above.
const TAG_BRACKET_RE = /【[^【】]*】/g;
// A corner segment only takes over when the remainder looks like a show
// wrapper: book-title brackets, bare noise labels, or that much plain text.
const BARE_TAKEOVER_LENGTH = 10;
const CJK_RE = /[\u3400-\u9fff\uf900-\ufaff]/;
const SPACED_DASH_RE = /\s+[-–—]\s+/;
// Tight dash split requires a CJK side so "AC-DC" style names survive.
const TIGHT_DASH_RE = /^([^-–—]+)[-–—]([^-–—]+)$/;
const EDGE_SEPARATOR_RE = /^[\s\-–—_]+|[\s\-–—_]+$/g;

export class SongTitleExtractor {
  /** Drops a trailing audio extension; names without one pass through. */
  static stripAudioExtension(raw: string): string {
    return raw.replace(AUDIO_EXTENSION_RE, '');
  }

  /** Removes bracketed noise labels ([FLAC], (Official MV), (无损) …), keeping
   * brackets that carry real information like "(Taylor's Version)". */
  static stripNoiseLabels(text: string): string {
    let result = text;
    // Two rounds flatten one nesting level ("(Official (HD))").
    for (let round = 0; round < 2; round++) {
      result = result.replace(BRACKETED_RE, (full: string, open: string, inner: string, close: string): string => {
        if (NOISE_LABEL_RE.test(inner)) {
          return '';
        }
        return full;
      });
    }
    return result.trim().replace(/\s{2,}/g, ' ');
  }

  /**
   * Strips a leading track number ("01 晴天" -> 晴天). Conservative: requires
   * 2-3 digits AND a CJK remainder, so "7 rings", "2002" and "99 Luftballons"
   * survive; a dirty keyword is recoverable downstream, a mangled title is not.
   */
  static stripTrackNumber(text: string): string {
    const match = text.match(TRACK_NUMBER_RE);
    if (match !== null && CJK_RE.test(match[3])) {
      return match[3].trim();
    }
    return text;
  }

  /** "Artist - Title" on a spaced dash; the first dash splits, later ones
   * stay in the title ("A - B - C" -> A / "B - C"). */
  static splitOnSpacedDash(text: string): ExtractedTitle | null {
    const parts = text.split(SPACED_DASH_RE)
      .map((part: string): string => part.trim())
      .filter((part: string): boolean => part.length > 0);
    if (parts.length >= 2 && parts[0].length > 0 && parts[1].length > 0) {
      return { title: parts.slice(1).join(' - '), artist: parts[0] };
    }
    return null;
  }

  static isCjk(text: string): boolean {
    return CJK_RE.test(text);
  }

  /**
   * Drops every 【tag】 segment of a video-style name ("【洛天依原创】91度的水汽
   * 凝结" -> 91度的水汽凝结). Names that are nothing but tags pass through.
   */
  static stripTagBrackets(text: string): string {
    const stripped = text.replace(TAG_BRACKET_RE, ' ').trim().replace(/\s{2,}/g, ' ');
    return stripped.length > 0 ? stripped : text;
  }

  /**
   * Corner/book bracket segments of a video-style name, longest first — the
   * fallback search keywords AutoSongMatcher retries with when the whole-name
   * query drifts. The text left after dropping 【tag】 brackets counts as a
   * segment too. Empty when the name carries no such bracketing.
   */
  static bracketedSegments(raw: string): string[] {
    const text = SongTitleExtractor.stripNoiseLabels(
      SongTitleExtractor.stripAudioExtension(raw.trim()));
    const segments: string[] = [];
    const untagged = SongTitleExtractor.stripTagBrackets(text);
    if (untagged !== text) {
      segments.push(untagged);
    }
    CORNER_SEGMENT_RE.lastIndex = 0;
    let match = CORNER_SEGMENT_RE.exec(text);
    while (match !== null) {
      segments.push(match[1].trim());
      match = CORNER_SEGMENT_RE.exec(text);
    }
    BOOK_SEGMENT_RE.lastIndex = 0;
    match = BOOK_SEGMENT_RE.exec(text);
    while (match !== null) {
      segments.push(match[1].trim());
      match = BOOK_SEGMENT_RE.exec(text);
    }
    const unique = segments
      .filter((segment: string): boolean => segment.length > 0)
      .sort((a: string, b: string): number => b.length - a.length);
    const seen: string[] = [];
    for (const segment of unique) {
      if (seen.indexOf(segment) < 0) {
        seen.push(segment);
      }
    }
    return seen;
  }

  /**
   * Show-wrapper takeover for video titles ("《show》官方MV「song」中文字幕"):
   * the longest corner segment becomes the title when the remainder carries
   * program noise — book brackets, bare noise labels or that much plain text.
   * Plain quoted accents ("晴天「Acoustic Version」") keep the whole name.
   */
  static preferCornerSegment(text: string): string {
    if (!text.includes('「') && !text.includes('『')) {
      return text;
    }
    let corner = '';
    CORNER_SEGMENT_RE.lastIndex = 0;
    let match = CORNER_SEGMENT_RE.exec(text);
    while (match !== null) {
      if (match[1].trim().length > corner.length) {
        corner = match[1].trim();
      }
      match = CORNER_SEGMENT_RE.exec(text);
    }
    if (corner.length === 0) {
      return text;
    }
    let rest = text;
    for (const wrapped of [`「${corner}」`, `『${corner}』`]) {
      const at = rest.indexOf(wrapped);
      if (at >= 0) {
        rest = rest.substring(0, at) + rest.substring(at + wrapped.length);
        break;
      }
    }
    rest = rest.trim();
    const programWrapped = rest.length === 0 || rest.includes('《') || rest.includes('「') || rest.includes('『')
      || NOISE_LABEL_RE.test(rest) || rest.replace(/\s+/g, '').length > BARE_TAKEOVER_LENGTH;
    return programWrapped ? corner : text;
  }

  /**
   * Tight "Title-Artist" (晴天-周杰伦): download-site convention is title
   * first; a detected person name in either side flips it. Only called when a
   * CJK side exists, so "AC-DC" never reaches here.
   */
  static splitOnTightDash(left: string, right: string, names: string[]): ExtractedTitle | null {
    if (names.includes(right)) {
      return { title: left, artist: right };
    }
    if (names.includes(left)) {
      return { title: right, artist: left };
    }
    return { title: left, artist: right };
  }

  /**
   * Separator-less Chinese ("周杰伦晴天"): a person name at either edge, or a
   * head/tail run of person-name tags from segmentation, becomes the artist
   * and the rest the title. Returns null when the evidence does not fit an
   * edge, leaving the whole string as the title.
   */
  static splitOnPersonNames(text: string, names: string[], words: NlpWord[]): ExtractedTitle | null {
    for (const name of names) {
      if (name.length === 0 || name.length >= text.length) {
        continue;
      }
      if (text.startsWith(name)) {
        return { title: SongTitleExtractor.trimSeparators(text.substring(name.length)), artist: name };
      }
      if (text.endsWith(name)) {
        return { title: SongTitleExtractor.trimSeparators(text.substring(0, text.length - name.length)), artist: name };
      }
    }
    if (words.length >= 2) {
      let head = '';
      let index = 0;
      while (index < words.length && words[index].wordTag === 'nr') {
        head += words[index].word;
        index++;
      }
      if (head.length > 0 && index < words.length) {
        return { title: words.slice(index).map((w: NlpWord): string => w.word).join(''), artist: head };
      }
      let tail = '';
      for (let index2 = words.length - 1; index2 >= 0 && words[index2].wordTag === 'nr'; index2--) {
        tail = words[index2].word + tail;
      }
      if (tail.length > 0 && tail.length < text.length) {
        const title = words.slice(0, words.length - SongTitleExtractor.tailNrCount(words)).map((w: NlpWord): string => w.word).join('');
        if (title.length > 0) {
          return { title: title, artist: tail };
        }
      }
    }
    return null;
  }

  private static tailNrCount(words: NlpWord[]): number {
    let count = 0;
    for (let index = words.length - 1; index >= 0 && words[index].wordTag === 'nr'; index--) {
      count++;
    }
    return count;
  }

  private static trimSeparators(text: string): string {
    return text.replace(EDGE_SEPARATOR_RE, '').trim();
  }

  /**
   * Pipeline: extension -> noise labels -> 【tag】 brackets -> corner-segment
   * takeover -> track number -> spaced dash -> tight dash (CJK side required,
   * NLP direction check) -> NLP person names -> whole string as title. Never
   * throws; NLP results arrive pre-swallowed (the assistant resolves []
   * instead of rejecting).
   */
  static async extract(raw: string, nlp: TitleNlpAssistant | null): Promise<ExtractedTitle> {
    let text = SongTitleExtractor.stripAudioExtension(raw).trim();
    if (text.length === 0) {
      return { title: '', artist: '' };
    }
    text = SongTitleExtractor.stripNoiseLabels(text);
    text = SongTitleExtractor.stripTagBrackets(text);
    text = SongTitleExtractor.preferCornerSegment(text);
    text = SongTitleExtractor.stripTrackNumber(text);
    if (text.length === 0) {
      return { title: '', artist: '' };
    }
    const spaced = SongTitleExtractor.splitOnSpacedDash(text);
    if (spaced !== null) {
      return spaced;
    }
    let names: string[] = [];
    let words: NlpWord[] = [];
    if (nlp !== null) {
      names = await nlp.extractPersonNames(text);
    }
    const tight = text.match(TIGHT_DASH_RE);
    if (tight !== null && (SongTitleExtractor.isCjk(tight[1]) || SongTitleExtractor.isCjk(tight[2]))) {
      const tightSplit = SongTitleExtractor.splitOnTightDash(tight[1], tight[2], names);
      if (tightSplit !== null) {
        return tightSplit;
      }
    }
    if (nlp !== null && names.length === 0) {
      words = await nlp.segmentWords(text);
    }
    if (nlp !== null) {
      const byName = SongTitleExtractor.splitOnPersonNames(text, names, words);
      if (byName !== null) {
        return byName;
      }
    }
    return { title: text, artist: '' };
  }
}
