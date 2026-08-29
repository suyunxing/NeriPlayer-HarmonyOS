import { LyricLine } from '../model/LyricLine';

/**
 * Resolves which lyric line a playhead sits on.
 *
 * Split out of LyricView so the hint-resumption logic is unit-testable without
 * an ArkUI render tree. LyricView needs this on the highest-frequency path in
 * the app (once per position tick, to decide whether to auto-scroll), and the
 * code it replaced re-scanned the whole line list four times for every
 * rendered line inside a ForEach.
 *
 * Distinct from LyricLineTracker, which answers "did the line just change?"
 * for the floating bar / AVSession title and only exposes a cached index that
 * is -1 until the playhead has crossed a boundary. The view needs the correct
 * index immediately, including while paused, so it resolves its own.
 */
export class LyricIndexResolver {
  /**
   * Index of the last line whose timestamp has been reached, or -1 when the
   * playhead is before the first line or there are no lines.
   *
   * `timeMs` is display time, i.e. the raw position plus the np.lyric_offset_ms
   * setting (positive offset = lyrics advance), matching LyricLineTracker.
   *
   * `hint` is the previously resolved index. When it is still consistent with
   * `timeMs` the walk resumes from it, which costs one comparison while
   * playback advances normally. Pass -1 to force a scan from the top; a stale
   * or out-of-range hint is detected and degrades to the same full scan, so a
   * backward seek stays correct.
   */
  static resolve(lines: LyricLine[], timeMs: number, hint: number): number {
    if (lines.length === 0) {
      return -1;
    }
    let index = hint;
    if (index < 0 || index >= lines.length || lines[index].timeMs > timeMs) {
      index = -1;
      for (let i = 0; i < lines.length; i++) {
        if (lines[i].timeMs <= timeMs) {
          index = i;
        } else {
          break;
        }
      }
      return index;
    }
    while (index + 1 < lines.length && lines[index + 1].timeMs <= timeMs) {
      index++;
    }
    return index;
  }
}
