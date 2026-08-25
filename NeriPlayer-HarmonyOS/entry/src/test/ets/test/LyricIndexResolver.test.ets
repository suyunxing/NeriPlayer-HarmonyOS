import { describe, it, expect } from '@ohos/hypium';
import { LyricIndexResolver } from '../../../main/ets/lyrics/LyricIndexResolver';
import { LyricLine } from '../../../main/ets/model/LyricLine';

function lines(): LyricLine[] {
  return [
    new LyricLine(0, 'a', ''),
    new LyricLine(5000, 'b', ''),
    new LyricLine(9000, 'c', ''),
    new LyricLine(12000, 'd', '')
  ];
}

export default function lyricIndexResolverTest(): void {
  describe('LyricIndexResolver', () => {
    it('returnsMinusOneForEmptyLines', 0, () => {
      expect(LyricIndexResolver.resolve([], 1000, -1)).assertEqual(-1);
      // A stale hint must not survive an empty list.
      expect(LyricIndexResolver.resolve([], 1000, 3)).assertEqual(-1);
    });

    it('returnsMinusOneBeforeFirstLine', 0, () => {
      const list = [new LyricLine(1000, 'a', ''), new LyricLine(3000, 'b', '')];
      expect(LyricIndexResolver.resolve(list, 999, -1)).assertEqual(-1);
      expect(LyricIndexResolver.resolve(list, 1000, -1)).assertEqual(0);
    });

    it('coldScanFindsCorrectLine', 0, () => {
      const list = lines();
      expect(LyricIndexResolver.resolve(list, 0, -1)).assertEqual(0);
      expect(LyricIndexResolver.resolve(list, 4999, -1)).assertEqual(0);
      expect(LyricIndexResolver.resolve(list, 5000, -1)).assertEqual(1);
      expect(LyricIndexResolver.resolve(list, 11000, -1)).assertEqual(2);
      expect(LyricIndexResolver.resolve(list, 99000, -1)).assertEqual(3);
    });

    it('hintResumptionMatchesColdScan', 0, () => {
      // The whole point of the hint is that it never changes the answer, only
      // the cost. Walk the timeline twice and compare every step.
      const list = lines();
      let hint = -1;
      for (let t = 0; t <= 14000; t += 250) {
        const warm = LyricIndexResolver.resolve(list, t, hint);
        const cold = LyricIndexResolver.resolve(list, t, -1);
        expect(warm).assertEqual(cold);
        hint = warm;
      }
    });

    it('advancesOneLineAtATime', 0, () => {
      const list = lines();
      expect(LyricIndexResolver.resolve(list, 4000, 0)).assertEqual(0);
      expect(LyricIndexResolver.resolve(list, 5000, 0)).assertEqual(1);
      expect(LyricIndexResolver.resolve(list, 9000, 1)).assertEqual(2);
    });

    it('skipsAheadOnForwardJump', 0, () => {
      // Forward seek past several lines: the walk must catch up, not stop at
      // hint + 1.
      expect(LyricIndexResolver.resolve(lines(), 12500, 0)).assertEqual(3);
    });

    it('recoversOnBackwardSeek', 0, () => {
      // hint is ahead of the playhead, which is exactly what a rewind looks
      // like; the resolver has to fall back to the full scan.
      const list = lines();
      expect(LyricIndexResolver.resolve(list, 0, 3)).assertEqual(0);
      expect(LyricIndexResolver.resolve(list, 6000, 3)).assertEqual(1);
      // Rewinding to before the first stamp yields -1 even from a stale hint.
      // (lines() starts at 0, so it can never report -1 — use a later start.)
      const late = [new LyricLine(1000, 'a', ''), new LyricLine(3000, 'b', '')];
      expect(LyricIndexResolver.resolve(late, 999, 1)).assertEqual(-1);
    });

    it('toleratesOutOfRangeHint', 0, () => {
      // A hint left over from a longer previous song must not index past the
      // end of the new one.
      const list = lines();
      expect(LyricIndexResolver.resolve(list, 6000, 99)).assertEqual(1);
      expect(LyricIndexResolver.resolve(list, 6000, -7)).assertEqual(1);
    });

    it('handlesSingleLine', 0, () => {
      const list = [new LyricLine(2000, 'only', '')];
      expect(LyricIndexResolver.resolve(list, 0, -1)).assertEqual(-1);
      expect(LyricIndexResolver.resolve(list, 2000, -1)).assertEqual(0);
      expect(LyricIndexResolver.resolve(list, 60000, 0)).assertEqual(0);
    });

    it('picksLastOfDuplicateTimestamps', 0, () => {
      // Enhanced LRC can carry two lines on the same stamp (line + its
      // romanization split by the parser); the later one wins, and the hint
      // path must agree with the cold path.
      const list = [
        new LyricLine(0, 'a', ''),
        new LyricLine(4000, 'b', ''),
        new LyricLine(4000, 'b2', ''),
        new LyricLine(8000, 'c', '')
      ];
      expect(LyricIndexResolver.resolve(list, 4000, -1)).assertEqual(2);
      expect(LyricIndexResolver.resolve(list, 4000, 1)).assertEqual(2);
    });

    it('offsetIsCallerAppliedDisplayTime', 0, () => {
      // The resolver takes display time; a +500ms offset at raw 4600 lands in
      // line b exactly as LyricLineTracker.onPosition(4600, 500) would.
      const list = lines();
      expect(LyricIndexResolver.resolve(list, 4600 + 500, -1)).assertEqual(1);
      expect(LyricIndexResolver.resolve(list, 4600 - 500, -1)).assertEqual(0);
    });
  });
}
