/**
 * A single timed lyric line with optional translation, mirroring the
 * accompanist-lyrics-core model used by the Android app. Enhanced (word
 * timed) lines carry per-word timings for karaoke-style highlighting
 * (Android WordTiming).
 */
export class LyricWord {
  text: string;
  startMs: number;
  endMs: number;

  constructor(text: string = '', startMs: number = 0, endMs: number = 0) {
    this.text = text;
    this.startMs = startMs;
    this.endMs = endMs;
  }
}

export class LyricLine {
  timeMs: number;
  text: string;
  translated: string;
  /** Romanization line aligned to this line (AMLL x-roman / netease romalrc). */
  phonetic: string;
  /** Word timings for enhanced LRC lines; empty for plain lines. */
  words: LyricWord[];
  /** End of the line: next line's start, or start + 5000ms for the last. */
  endTimeMs: number;

  constructor(timeMs: number = 0, text: string = '', translated: string = '', phonetic: string = '') {
    this.timeMs = timeMs;
    this.text = text;
    this.translated = translated;
    this.phonetic = phonetic;
    this.words = [];
    this.endTimeMs = 0;
  }
}

/**
 * Metadata header tags preserved from the LRC text ([ti:]/[ar:]/[al:]/[by:]
 * and the applied [offset:±ms]); empty strings when the tag is absent.
 */
export class LrcMetadata {
  title: string = '';
  artist: string = '';
  album: string = '';
  author: string = '';
  offsetMs: number = 0;
}

export class LrcParseResult {
  lines: LyricLine[] = [];
  metadata: LrcMetadata = new LrcMetadata();
}
