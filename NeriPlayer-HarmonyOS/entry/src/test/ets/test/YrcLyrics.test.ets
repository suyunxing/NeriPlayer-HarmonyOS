import { describe, it, expect } from '@ohos/hypium';
import { LrcParser } from '../../../main/ets/lyrics/LrcParser';

/**
 * NetEase YRC (逐字歌词) fixtures. The first block is the real fragment used
 * by the Android PlayerLyricsProviderTest; the full document below it follows
 * the same wire format (metadata tags, header-only lines, English words with
 * trailing spaces).
 */
const YRC_REAL_FRAGMENT = '[12580,3470](12580,250,0)难(12830,300,0)以(13130,200,0)忘记';

const YRC_FULL = [
  '[ti:难以忘记]',
  '[ar:歌手名]',
  '[by:歌词制作者]',
  '[0,3500]作词 : 张三',
  '[3500,2000]作曲 : 李四',
  '[12580,3470](12580,250,0)难(12830,300,0)以(13130,1200,0)忘(14330,1720,0)记',
  '[16500,4200](16500,400,0)初(16900,600,0)次(17500,800,0)见(18300,1200,0)你(19500,1200,0)的',
  '[21000,3800](21000,800,0)微(21800,1200,0)笑(23000,1800,0)',
  '[25000,2500]间奏',
  '[28000,4500](28000,500,0)Just (28500,600,0)keep (29100,400,0)your (29500,800,0)head (30300,2200,0)up'
].join('\n');

export default function yrcLyricsTest(): void {
  describe('YrcLyrics', () => {
    it('detectsYrcContent', 0, () => {
      expect(LrcParser.isNeteaseYrc(YRC_REAL_FRAGMENT)).assertTrue();
      expect(LrcParser.isNeteaseYrc(YRC_FULL)).assertTrue();
      expect(LrcParser.isNeteaseYrc('[00:12.58]难以忘记')).assertFalse();
      expect(LrcParser.isNeteaseYrc('[ti:标题]')).assertFalse();
      expect(LrcParser.isNeteaseYrc('')).assertFalse();
    });

    it('parsesWordTimingsFromRealFragment', 0, () => {
      const lines = LrcParser.parse(YRC_REAL_FRAGMENT);
      expect(lines.length).assertEqual(1);
      const line = lines[0];
      expect(line.timeMs).assertEqual(12580);
      expect(line.text).assertEqual('难以忘记');
      expect(line.words.length).assertEqual(3);
      expect(line.words[0].text).assertEqual('难');
      expect(line.words[0].startMs).assertEqual(12580);
      expect(line.words[0].endMs).assertEqual(12830);
      expect(line.words[1].startMs).assertEqual(12830);
      expect(line.words[2].text).assertEqual('忘记');
      expect(line.words[2].endMs).assertEqual(13330);
      // Explicit line end: start + duration, not the +5000ms last-line rule.
      expect(line.endTimeMs).assertEqual(16050);
    });

    it('parsesFullYrcDocument', 0, () => {
      const parsed = LrcParser.parseWithMetadata(YRC_FULL);
      // Metadata tags are preserved, header-only lines become plain lines.
      expect(parsed.metadata.title).assertEqual('难以忘记');
      expect(parsed.metadata.artist).assertEqual('歌手名');
      expect(parsed.metadata.author).assertEqual('歌词制作者');
      expect(parsed.lines.length).assertEqual(7);
      expect(parsed.lines[0].text).assertEqual('作词 : 张三');
      expect(parsed.lines[0].words.length).assertEqual(0);
      expect(parsed.lines[0].endTimeMs).assertEqual(3500);
      // Sorted by start time; word-timed line text is the concatenation.
      const main = parsed.lines[2];
      expect(main.timeMs).assertEqual(12580);
      expect(main.text).assertEqual('难以忘记');
      expect(main.words.length).assertEqual(4);
      // Explicit end preserved even with later lines present.
      expect(main.endTimeMs).assertEqual(16050);
      // English words keep their trailing spaces inside word text.
      const english = parsed.lines[6];
      expect(english.words[0].text).assertEqual('Just ');
      expect(english.text).assertEqual('Just keep your head up');
      // A word whose duration overruns still yields start+dur.
      expect(english.words[4].endMs).assertEqual(32500);
    });

    it('mixedLrcAndYrcLinesCoexist', 0, () => {
      const mixed = '[00:05.00]plain line\n[12580,3470](12580,3470,0)整行一字\n[00:20.00]another';
      const lines = LrcParser.parse(mixed);
      expect(lines.length).assertEqual(3);
      expect(lines[0].text).assertEqual('plain line');
      expect(lines[1].words.length).assertEqual(1);
      // Plain LRC line still gets the next-line-start end; YRC keeps explicit.
      expect(lines[0].endTimeMs).assertEqual(12580);
      expect(lines[1].endTimeMs).assertEqual(16050);
      expect(lines[2].endTimeMs).assertEqual(25000);
    });

    it('translationMergesOntoYrcLines', 0, () => {
      const lines = LrcParser.parse(YRC_REAL_FRAGMENT);
      const merged = LrcParser.mergeTranslation(lines, '[00:12.58]hard to forget');
      expect(merged[0].translated).assertEqual('hard to forget');
    });

    it('serializeDegradesYrcToPlainLrc', 0, () => {
      const parsed = LrcParser.parseWithMetadata(YRC_REAL_FRAGMENT);
      const serialized = LrcParser.serialize(parsed.lines, parsed.metadata);
      // Round trip: the plain-text line survives with its timestamp; word
      // timings are intentionally dropped for player compatibility.
      const back = LrcParser.parse(serialized);
      expect(back.length).assertEqual(1);
      expect(back[0].text).assertEqual('难以忘记');
      expect(back[0].timeMs).assertEqual(12580);
    });
  });
}
