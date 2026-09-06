import { describe, it, expect } from '@ohos/hypium';
import { TtmlParser } from '../../../main/ets/lyrics/TtmlParser';

// Fixture mirrors the word-timed TTML shape pinned by Android's
// PlayerLyricsProviderTest / AdvancedLyricsViewTest: word spans with
// begin/end, plus x-translation / x-roman annotation spans.
const WORD_TIMED_TTML = `
<tt xmlns="http://www.w3.org/ns/ttml" xmlns:ttm="http://www.w3.org/ns/ttml#metadata">
  <body><div>
    <p begin="00:01.000" end="00:02.000">
      <span begin="00:01.000" end="00:01.500">Hello</span>
      <span begin="00:01.500" end="00:02.000">World</span>
      <span ttm:role="x-translation">你好世界</span>
      <span ttm:role="x-roman">Halo Waludo</span>
    </p>
    <p begin="00:02.000" end="00:03.000">
      <span begin="00:02.000" end="00:02.400">Foo</span>
      <span begin="00:02.400" end="00:03.000">Bar</span>
    </p>
  </div></body>
</tt>`;

const PLAIN_TTML = `
<tt xmlns="http://www.w3.org/ns/ttml">
  <body><div>
    <p begin="00:04.000" end="00:06.000">plain line &amp; more</p>
  </div></body>
</tt>`;

export default function ttmlParserTest(): void {
  describe('TtmlParser', () => {
    it('parsesWordTimedLineLikeAndroidProvider', 0, () => {
      const lines = TtmlParser.parse(WORD_TIMED_TTML)!;
      expect(lines.length).assertEqual(2);
      const first = lines[0];
      // Android LyricEntry assertion: text = "HelloWorld", words.size == 2.
      expect(first.text).assertEqual('HelloWorld');
      expect(first.words.length).assertEqual(2);
      expect(first.words[0].text).assertEqual('Hello');
      expect(first.words[0].startMs).assertEqual(1000);
      expect(first.words[0].endMs).assertEqual(1500);
      expect(first.words[1].startMs).assertEqual(1500);
      expect(first.words[1].endMs).assertEqual(2000);
      expect(first.timeMs).assertEqual(1000);
      expect(first.endTimeMs).assertEqual(2000);
      expect(first.translated).assertEqual('你好世界');
      expect(first.phonetic).assertEqual('Halo Waludo');
      // Second line has no annotation spans -> empty slots.
      expect(lines[1].translated).assertEqual('');
      expect(lines[1].phonetic).assertEqual('');
    });

    it('parsesPlainLinesAndDecodesEntities', 0, () => {
      const lines = TtmlParser.parse(PLAIN_TTML)!;
      expect(lines.length).assertEqual(1);
      expect(lines[0].text).assertEqual('plain line & more');
      expect(lines[0].words.length).assertEqual(0);
      expect(lines[0].endTimeMs).assertEqual(6000);
    });

    it('supportsClockSecondsAndBareTimeExpressions', 0, () => {
      expect(TtmlParser.timeToMs('00:00:02.500')).assertEqual(2500);
      expect(TtmlParser.timeToMs('01:02:03')).assertEqual(3723000);
      expect(TtmlParser.timeToMs('00:01.000')).assertEqual(1000);
      expect(TtmlParser.timeToMs('3.25s')).assertEqual(3250);
      expect(TtmlParser.timeToMs('1500ms')).assertEqual(1500);
      expect(TtmlParser.timeToMs('1250')).assertEqual(1250);
      expect(TtmlParser.timeToMs('12.5t')).assertNull();
      expect(TtmlParser.timeToMs('00:00:01:12')).assertNull();
      expect(TtmlParser.timeToMs('')).assertNull();
    });

    it('sortsLinesAndBackfillsLastLineEnd', 0, () => {
      const ttml = [
        '<tt><body><div>',
        '<p begin="00:10.000">late</p>',
        '<p begin="00:02.000">early</p>',
        '</div></body></tt>'
      ].join('');
      const lines = TtmlParser.parse(ttml)!;
      expect(lines[0].text).assertEqual('early');
      expect(lines[1].text).assertEqual('late');
      // Last line without end: start + 5000ms (LrcParser semantics).
      expect(lines[1].endTimeMs).assertEqual(15000);
    });

    it('returnsNullForEmptyOrPlessInput', 0, () => {
      expect(TtmlParser.parse('')).assertNull();
      expect(TtmlParser.parse('   ')).assertNull();
      expect(TtmlParser.parse('<tt><body><div></div></body></tt>')).assertNull();
      expect(TtmlParser.parse('<p begin="bad time">x</p>')).assertNull();
    });
  });
}
