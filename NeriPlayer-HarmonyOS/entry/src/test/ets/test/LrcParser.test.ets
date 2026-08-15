import { describe, it, expect } from '@ohos/hypium';
import { LrcParser } from '../../../main/ets/lyrics/LrcParser';

export default function lrcParserTest(): void {
  describe('LrcParser', () => {
    it('parsesMultipleTimestampsAndSortsLines', 0, () => {
      const lines = LrcParser.parse('[00:02.50][00:03.250]second\n[00:01.00]first');

      expect(lines.length).assertEqual(3);
      expect(lines[0].timeMs).assertEqual(1000);
      expect(lines[0].text).assertEqual('first');
      expect(lines[1].timeMs).assertEqual(2500);
      expect(lines[2].timeMs).assertEqual(3250);
      expect(lines[2].text).assertEqual('second');
    });

    it('mergesTranslationWithinTimestampTolerance', 0, () => {
      const lines = LrcParser.parse('[00:10.00]original');
      LrcParser.mergeTranslation(lines, '[00:10.12]translation');

      expect(lines[0].translated).assertEqual('translation');
    });

    it('formatsNegativeAndMinuteTimes', 0, () => {
      expect(LrcParser.formatTime(-1)).assertEqual('0:00');
      expect(LrcParser.formatTime(125000)).assertEqual('2:05');
    });
  });
}
