import { describe, it, expect } from '@ohos/hypium';
import { LyricLineTracker } from '../../../main/ets/lyrics/LyricLineTracker';
import { LyricLine } from '../../../main/ets/model/LyricLine';

export default function lyricLineTrackerTest(): void {
  describe('LyricLineTracker', () => {
    it('emitsLineTextOnLineAdvanceOnly', 0, () => {
      const tracker = new LyricLineTracker();
      tracker.setLines([
        new LyricLine(0, 'first', ''),
        new LyricLine(5000, 'second', ''),
        new LyricLine(9000, 'third', '')
      ]);
      // Before the first line's start: no emission.
      expect(tracker.onPosition(0)).assertEqual('first');
      // Same line: no re-emission.
      expect(tracker.onPosition(1200)).assertNull();
      expect(tracker.onPosition(4999)).assertNull();
      // Crossing into the second line emits exactly once.
      expect(tracker.onPosition(5000)).assertEqual('second');
      expect(tracker.onPosition(7000)).assertNull();
      expect(tracker.onPosition(9500)).assertEqual('third');
    });

    it('appliesOffsetLikeDisplayTime', 0, () => {
      const tracker = new LyricLineTracker();
      tracker.setLines([
        new LyricLine(1000, 'a', ''),
        new LyricLine(3000, 'b', '')
      ]);
      // +500ms offset advances effective time: 2600+500=3100 crosses into b.
      expect(tracker.onPosition(2600, 500)).assertEqual('b');
    });

    it('beforeFirstLineEmitsNothing', 0, () => {
      const tracker = new LyricLineTracker();
      tracker.setLines([
        new LyricLine(1000, 'a', ''),
        new LyricLine(3000, 'b', '')
      ]);
      expect(tracker.onPosition(999)).assertNull();
      expect(tracker.onPosition(1000)).assertEqual('a');
    });

    it('fallsBackToTranslationForEmptyText', 0, () => {
      const tracker = new LyricLineTracker();
      const instrumental = new LyricLine(0, '', '间奏');
      tracker.setLines([instrumental]);
      expect(tracker.onPosition(0)).assertEqual('间奏');
    });

    it('resetClearsLinesAndIndex', 0, () => {
      const tracker = new LyricLineTracker();
      tracker.setLines([new LyricLine(0, 'a', '')]);
      expect(tracker.onPosition(0)).assertEqual('a');
      tracker.reset();
      expect(tracker.onPosition(0)).assertNull();
      // Re-setting lines restarts emission from the first line.
      tracker.setLines([new LyricLine(0, 'b', '')]);
      expect(tracker.onPosition(0)).assertEqual('b');
    });

    it('notifiesLinesListenerOnEveryReplacement', 0, () => {
      const tracker = new LyricLineTracker();
      const seen: number[] = [];
      tracker.setLinesListener((lines: LyricLine[]) => {
        seen.push(lines.length);
      });

      tracker.setLines([new LyricLine(0, 'a', ''), new LyricLine(1000, 'b', '')]);
      // reset() goes through setLines, so clearing must notify too — that is
      // what wipes the previous song's AVMetadata.lyric.
      tracker.reset();

      expect(seen.length).assertEqual(2);
      expect(seen[0]).assertEqual(2);
      expect(seen[1]).assertEqual(0);
    });

    it('detachedLinesListenerStopsReceiving', 0, () => {
      const tracker = new LyricLineTracker();
      let calls = 0;
      tracker.setLinesListener(() => {
        calls++;
      });
      tracker.setLines([new LyricLine(0, 'a', '')]);
      tracker.setLinesListener(null);
      tracker.setLines([new LyricLine(0, 'b', '')]);

      expect(calls).assertEqual(1);
    });
  });
}
