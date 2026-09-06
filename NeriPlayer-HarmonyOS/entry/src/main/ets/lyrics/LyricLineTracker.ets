import { LyricLine } from '../model/LyricLine';

/** Sink for whole-lyric replacement, see setLinesListener. */
export type LyricLinesListener = (lines: LyricLine[]) => void;

/**
 * Tracks which lyric line the playhead is on, the shared data source for the
 * in-app floating lyric bar (D4 fallback: ordinary HarmonyOS apps have no
 * SYSTEM_ALERT_WINDOW equivalent) and for the AVSession metadata lyric line
 * (the Android "bluetooth lyrics" trick of writing the current line into the
 * session title). Pure logic so line-advance semantics are unit-testable;
 * the position feed is PlayerManager.publishPosition.
 */
export class LyricLineTracker {
  private static instance: LyricLineTracker | null = null;

  static getInstance(): LyricLineTracker {
    if (LyricLineTracker.instance === null) {
      LyricLineTracker.instance = new LyricLineTracker();
    }
    return LyricLineTracker.instance;
  }

  private lines: LyricLine[] = [];
  private lastIndex: number = -1;
  private linesListener: LyricLinesListener | null = null;

  /**
   * Registers the sink for whole-lyric changes. Lyrics are loaded by the UI
   * layer (NowPlayingPage -> LyricDispatcher), but AVMetadata.lyric needs the
   * full LRC from the player layer; rather than duplicating the fetch in
   * PlayerManager, it subscribes here. Single slot: PlayerManager owns it.
   */
  setLinesListener(listener: LyricLinesListener | null): void {
    this.linesListener = listener;
  }

  setLines(lines: LyricLine[]): void {
    this.lines = lines;
    this.lastIndex = -1;
    const listener = this.linesListener;
    if (listener !== null) {
      listener(lines);
    }
  }

  reset(): void {
    this.setLines([]);
  }

  /**
   * Returns the new line's text when the playhead crossed into a different
   * line (the offset setting mirrors display-time semantics), null when the
   * line did not change or there are no lyrics. Called once per position
   * tick, so the common path is a single comparison.
   */
  onPosition(positionMs: number, offsetMs: number = 0): string | null {
    if (this.lines.length === 0) {
      return null;
    }
    const time = positionMs + offsetMs;
    let index = -1;
    for (let i = 0; i < this.lines.length; i++) {
      if (this.lines[i].timeMs <= time) {
        index = i;
      } else {
        break;
      }
    }
    if (index === this.lastIndex || index < 0) {
      return null;
    }
    this.lastIndex = index;
    const line = this.lines[index];
    return line.text.length > 0 ? line.text : line.translated;
  }

  currentIndex(): number {
    return this.lastIndex;
  }
}
