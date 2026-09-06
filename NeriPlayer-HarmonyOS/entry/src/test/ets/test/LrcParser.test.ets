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

    it('parsesLegacyColonTimestampsLikeAndroidNormalizer', 0, () => {
      // Android SyncedLyricsTimingTest: [00:00:15] -> 150ms, [00:12:76] -> 12760ms.
      const lines = LrcParser.parse('[00:00:15]The sky blue archive!\n[00:12:76]新しい景色');
      expect(lines.length).assertEqual(2);
      expect(lines[0].timeMs).assertEqual(150);
      expect(lines[0].text).assertEqual('The sky blue archive!');
      expect(lines[1].timeMs).assertEqual(12760);
    });

    it('keepsMetadataHeaderOutOfLinesAndExposesIt', 0, () => {
      const result = LrcParser.parseWithMetadata(
        '[by:夜羽小猫]\n[ti:晴天]\n[ar:周杰伦]\n[al:叶惠美]\n[00:01.00]第一行'
      );
      expect(result.lines.length).assertEqual(1);
      expect(result.lines[0].text).assertEqual('第一行');
      expect(result.metadata.title).assertEqual('晴天');
      expect(result.metadata.artist).assertEqual('周杰伦');
      expect(result.metadata.album).assertEqual('叶惠美');
      expect(result.metadata.author).assertEqual('夜羽小猫');
      expect(result.metadata.offsetMs).assertEqual(0);
    });

    it('appliesOffsetHeaderWithAdvanceSemantics', 0, () => {
      // Positive [offset:] advances lyrics: effective time = timestamp - offset.
      const advanced = LrcParser.parse('[offset:+500]\n[00:02.00]line');
      expect(advanced[0].timeMs).assertEqual(1500);
      const delayed = LrcParser.parse('[offset:-250]\n[00:02.00]line');
      expect(delayed[0].timeMs).assertEqual(2250);
      // Invalid / out-of-range offsets are ignored.
      const invalid = LrcParser.parse('[offset:abc]\n[00:02.00]line');
      expect(invalid[0].timeMs).assertEqual(2000);
      const clamped = LrcParser.parseWithMetadata('[offset:999999]\n[00:02.00]line');
      expect(clamped.metadata.offsetMs).assertEqual(60000);
    });

    it('parsesEnhancedWordTimingsIntoChainedWords', 0, () => {
      const lines = LrcParser.parse(
        '[00:01.00]<00:01.00>你<00:01.20>好<00:01.50>呀\n[00:04.00]plain next'
      );
      const wordLine = lines[0];
      expect(wordLine.text).assertEqual('你好呀');
      expect(wordLine.timeMs).assertEqual(1000);
      expect(wordLine.words.length).assertEqual(3);
      expect(wordLine.words[0].startMs).assertEqual(1000);
      expect(wordLine.words[0].endMs).assertEqual(1200);
      expect(wordLine.words[1].startMs).assertEqual(1200);
      expect(wordLine.words[1].endMs).assertEqual(1500);
      // Last word ends at the line end (= next line's start).
      expect(wordLine.words[2].endMs).assertEqual(4000);
      // Plain line untouched.
      expect(lines[1].words.length).assertEqual(0);
      expect(lines[1].text).assertEqual('plain next');
    });

    it('keepsUntimedPrefixTextOfWordLine', 0, () => {
      const lines = LrcParser.parse('[00:01.00]pre<00:01.00>字');
      expect(lines[0].text).assertEqual('pre字');
      expect(lines[0].words.length).assertEqual(1);
      expect(lines[0].words[0].text).assertEqual('字');
    });

    it('fillsLineEndTimesFromNextLineAndTail', 0, () => {
      const lines = LrcParser.parse('[00:01.00]a\n[00:03.00]b\n[00:05.00]c');
      expect(lines[0].endTimeMs).assertEqual(3000);
      expect(lines[1].endTimeMs).assertEqual(5000);
      // Last line: start + 5000ms (Android parseNeteaseLrc semantics).
      expect(lines[2].endTimeMs).assertEqual(10000);
    });

    it('stripsCarriageReturnFromCrlfLyrics', 0, () => {
      const lines = LrcParser.parse('[00:01.00]line\r\n[00:02.00]next\r\n');
      expect(lines[0].text).assertEqual('line');
      expect(lines[1].text).assertEqual('next');
    });

    // ------------------------------------------------------------------
    // serialize(): the inverse direction, feeding AVMetadata.lyric.
    // ------------------------------------------------------------------

    it('serializesLinesAsStandardLrcTimestamps', 0, () => {
      const lines = LrcParser.parse('[00:01.00]first\n[01:05.43]second');

      expect(LrcParser.serialize(lines)).assertEqual('[00:01.000]first\n[01:05.430]second');
    });

    it('serializeRoundTripsThroughParse', 0, () => {
      const source = '[00:00.123]a\n[00:12.456]b\n[02:03.789]c';
      const lines = LrcParser.parse(source);
      const reparsed = LrcParser.parse(LrcParser.serialize(lines));

      expect(reparsed.length).assertEqual(3);
      for (let i = 0; i < reparsed.length; i++) {
        expect(reparsed[i].timeMs).assertEqual(lines[i].timeMs);
        expect(reparsed[i].text).assertEqual(lines[i].text);
      }
    });

    it('serializeClampsNegativeTimesToZero', 0, () => {
      // A positive [offset:] advances lines past zero (timeMs -= offset).
      const lines = LrcParser.parse('[offset:+2000]\n[00:01.00]early');
      expect(lines[0].timeMs).assertEqual(-1000);

      expect(LrcParser.serialize(lines)).assertEqual('[00:00.000]early');
    });

    it('serializeNeverReEmitsOffsetTag', 0, () => {
      // parse() already folded the offset into every timeMs; writing the tag
      // back would apply it a second time on the next read.
      const parsed = LrcParser.parseWithMetadata('[offset:+500]\n[ti:Song]\n[00:02.00]a');
      const text = LrcParser.serialize(parsed.lines, parsed.metadata);

      expect(text.includes('offset')).assertFalse();
      expect(text).assertEqual('[ti:Song]\n[00:01.500]a');
    });

    it('serializeWritesOnlyNonEmptyMetadataTags', 0, () => {
      const parsed = LrcParser.parseWithMetadata('[ti:T]\n[by:B]\n[00:01.00]a');

      expect(LrcParser.serialize(parsed.lines, parsed.metadata)).assertEqual('[ti:T]\n[by:B]\n[00:01.000]a');
    });

    it('serializeDropsWordTagsAndKeepsPlainText', 0, () => {
      // Enhanced-LRC word tags would show up as literal text in readers that
      // do not understand them, so only line.text is written out.
      const lines = LrcParser.parse('[00:01.00]<00:01.00>he<00:01.50>llo');
      expect(lines[0].words.length).assertEqual(2);

      expect(LrcParser.serialize(lines)).assertEqual('[00:01.000]hello');
    });

    it('serializeFallsBackToTranslationForEmptyText', 0, () => {
      const lines = LrcParser.parse('[00:01.00]original');
      lines[0].text = '';
      lines[0].translated = 'translated';

      expect(LrcParser.serialize(lines)).assertEqual('[00:01.000]translated');
    });

    it('serializeSkipsLinesWithNoUsableText', 0, () => {
      const lines = LrcParser.parse('[00:01.00]a\n[00:02.00]b');
      lines[0].text = '   ';

      expect(LrcParser.serialize(lines)).assertEqual('[00:02.000]b');
    });

    it('serializeReturnsEmptyStringForNoLines', 0, () => {
      expect(LrcParser.serialize([])).assertEqual('');
    });
  });
}
