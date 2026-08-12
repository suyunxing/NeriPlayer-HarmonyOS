/**
 * A single timed lyric line with optional translation, mirroring the
 * accompanist-lyrics-core model used by the Android app.
 */
export class LyricLine {
  timeMs: number;
  text: string;
  translated: string;

  constructor(timeMs: number = 0, text: string = '', translated: string = '') {
    this.timeMs = timeMs;
    this.text = text;
    this.translated = translated;
  }
}
