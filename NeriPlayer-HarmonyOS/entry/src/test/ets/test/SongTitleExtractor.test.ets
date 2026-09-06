import { describe, it, expect } from '@ohos/hypium';
import { ExtractedTitle, NlpWord, SongTitleExtractor, TitleNlpAssistant } from '../../../main/ets/util/SongTitleExtractor';

/** Fake NLP assistant: scriptable person names / tagged words, never throws. */
class FakeNlp implements TitleNlpAssistant {
  names: string[] = [];
  words: NlpWord[] = [];

  constructor(names: string[], words: NlpWord[]) {
    this.names = names;
    this.words = words;
  }

  async segmentWords(_text: string): Promise<NlpWord[]> {
    return this.words;
  }

  async extractPersonNames(_text: string): Promise<string[]> {
    return this.names;
  }
}

export default function songTitleExtractorTest(): void {
  describe('SongTitleExtractor', () => {
    it('stripsAudioExtensionCaseInsensitively', 0, () => {
      expect(SongTitleExtractor.stripAudioExtension('晴天.mp3')).assertEqual('晴天');
      expect(SongTitleExtractor.stripAudioExtension('track.FLAC')).assertEqual('track');
      expect(SongTitleExtractor.stripAudioExtension('no extension')).assertEqual('no extension');
    });

    it('stripsNoiseLabelsButKeepsMeaningfulBrackets', 0, () => {
      expect(SongTitleExtractor.stripNoiseLabels('晴天 [FLAC]')).assertEqual('晴天');
      expect(SongTitleExtractor.stripNoiseLabels('晴天 (Official MV)')).assertEqual('晴天');
      expect(SongTitleExtractor.stripNoiseLabels('晴天 (320kbps)')).assertEqual('晴天');
      expect(SongTitleExtractor.stripNoiseLabels('晴天 (无损)')).assertEqual('晴天');
      expect(SongTitleExtractor.stripNoiseLabels('22 (Lavender Version)')).assertEqual('22 (Lavender Version)');
    });

    it('stripsTrackNumberOnlyForTwoThreeDigitsWithCjkRemainder', 0, () => {
      expect(SongTitleExtractor.stripTrackNumber('01 晴天')).assertEqual('晴天');
      expect(SongTitleExtractor.stripTrackNumber('010.晴天')).assertEqual('晴天');
      expect(SongTitleExtractor.stripTrackNumber('7 rings')).assertEqual('7 rings');
      expect(SongTitleExtractor.stripTrackNumber('2002')).assertEqual('2002');
      expect(SongTitleExtractor.stripTrackNumber('22 Yesterday')).assertEqual('22 Yesterday');
    });

    it('splitsArtistTitleOnSpacedDash', 0, () => {
      const pair = SongTitleExtractor.splitOnSpacedDash('周杰伦 - 晴天') as ExtractedTitle;
      expect(pair.artist).assertEqual('周杰伦');
      expect(pair.title).assertEqual('晴天');
      const multi = SongTitleExtractor.splitOnSpacedDash('A - B - C') as ExtractedTitle;
      expect(multi.artist).assertEqual('A');
      expect(multi.title).assertEqual('B - C');
      expect(SongTitleExtractor.splitOnSpacedDash('晴天')).assertNull();
    });

    it('splitsTightDashWithConventionAndPersonNameFlip', 0, () => {
      const plain = SongTitleExtractor.splitOnTightDash('晴天', '周杰伦', []) as ExtractedTitle;
      expect(plain.title).assertEqual('晴天');
      expect(plain.artist).assertEqual('周杰伦');
      // Person name on the left flips the download-site convention.
      const flipped = SongTitleExtractor.splitOnTightDash('周杰伦', '晴天', ['周杰伦']) as ExtractedTitle;
      expect(flipped.title).assertEqual('晴天');
      expect(flipped.artist).assertEqual('周杰伦');
    });

    it('splitsSeparatorlessTextOnEdgePersonNames', 0, () => {
      const prefix = SongTitleExtractor.splitOnPersonNames('周杰伦晴天', ['周杰伦'], []) as ExtractedTitle;
      expect(prefix.title).assertEqual('晴天');
      expect(prefix.artist).assertEqual('周杰伦');
      const suffix = SongTitleExtractor.splitOnPersonNames('晴天周杰伦', ['周杰伦'], []) as ExtractedTitle;
      expect(suffix.title).assertEqual('晴天');
      expect(suffix.artist).assertEqual('周杰伦');
      // Segmentation tags as fallback when the entity pass found nothing.
      const words: NlpWord[] = [
        { word: '晴天', wordTag: 'nz' },
        { word: '周杰伦', wordTag: 'nr' }
      ];
      const tagged = SongTitleExtractor.splitOnPersonNames('晴天周杰伦', [], words) as ExtractedTitle;
      expect(tagged.title).assertEqual('晴天');
      expect(tagged.artist).assertEqual('周杰伦');
      expect(SongTitleExtractor.splitOnPersonNames('晴天', [], [])).assertNull();
    });

    it('extractRunsFullHeuristicPipelineWithoutNlp', 0, async () => {
      const dirty = await SongTitleExtractor.extract('01 周杰伦 - 晴天 [FLAC].mp3', null);
      expect(dirty.title).assertEqual('晴天');
      expect(dirty.artist).assertEqual('周杰伦');
      const plain = await SongTitleExtractor.extract('晴天', null);
      expect(plain.title).assertEqual('晴天');
      expect(plain.artist).assertEqual('');
      const tight = await SongTitleExtractor.extract('晴天-周杰伦', null);
      expect(tight.title).assertEqual('晴天');
      expect(tight.artist).assertEqual('周杰伦');
    });

    it('extractUsesNlpForSeparatorlessNamesAndDegradesSilently', 0, async () => {
      const withNlp = await SongTitleExtractor.extract('周杰伦晴天', new FakeNlp(['周杰伦'], []));
      expect(withNlp.title).assertEqual('晴天');
      expect(withNlp.artist).assertEqual('周杰伦');
      // Assistant without evidence: whole string stays the title, artist empty.
      const degraded = await SongTitleExtractor.extract('周杰伦晴天', new FakeNlp([], []));
      expect(degraded.title).assertEqual('周杰伦晴天');
      expect(degraded.artist).assertEqual('');
      const spaced = await SongTitleExtractor.extract('周杰伦 - 晴天', new FakeNlp(['周杰伦'], []));
      expect(spaced.title).assertEqual('晴天');
      expect(spaced.artist).assertEqual('周杰伦');
    });

    it('cornerSegmentTakesOverVideoStyleShowTitles', 0, async () => {
      // Real-device case: a Bilibili upload whose name wraps the song in
      // corner brackets between the show title and subtitle labels.
      const bili = '《少女乐队的呐喊》官方MV「薄采ディスプレイ」中文字幕（淡彩Display）';
      expect(SongTitleExtractor.preferCornerSegment(bili)).assertEqual('薄采ディスプレイ');
      const extracted = await SongTitleExtractor.extract(bili, new FakeNlp([], []));
      expect(extracted.title).assertEqual('薄采ディスプレイ');
      expect(extracted.artist).assertEqual('');
      // Bare noise words next to the quote are enough evidence too.
      expect(SongTitleExtractor.preferCornerSegment('新曲「薄采ディスプレイ」MV 试听')).assertEqual('薄采ディスプレイ');
      // Book-title / corner brackets now count as noise-label brackets.
      expect(SongTitleExtractor.stripNoiseLabels('「官方MV」晴天')).assertEqual('晴天');
      expect(SongTitleExtractor.stripNoiseLabels('《晴天》')).assertEqual('《晴天》');
    });

    it('cornerSegmentStaysDownWithoutShowWrapper', 0, async () => {
      // A quoted accent on a plain song name is not a show wrapper.
      expect(SongTitleExtractor.preferCornerSegment('晴天「Acoustic Version」')).assertEqual('晴天「Acoustic Version」');
      // Quoted show name followed by an episode marker: taking the segment
      // would search the show, so the whole name stays the title.
      expect(SongTitleExtractor.preferCornerSegment('「少女乐队的呐喊」第二季 OP')).assertEqual('「少女乐队的呐喊」第二季 OP');
      expect(SongTitleExtractor.preferCornerSegment('晴天')).assertEqual('晴天');
      const plain = await SongTitleExtractor.extract('晴天「Acoustic Version」', null);
      expect(plain.title).assertEqual('晴天「Acoustic Version」');
    });

    it('bracketedSegmentsListsQuotedPartsLongestFirst', 0, () => {
      const segments = SongTitleExtractor.bracketedSegments(
        '《少女乐队的呐喊》官方MV「薄采ディスプレイ」中文字幕（淡彩Display）');
      expect(segments.length).assertEqual(2);
      expect(segments[0]).assertEqual('薄采ディスプレイ');
      expect(segments[1]).assertEqual('少女乐队的呐喊');
      expect(SongTitleExtractor.bracketedSegments('周杰伦 - 晴天.mp3').length).assertEqual(0);
      // Duplicates collapse; single-character quotes are skipped.
      expect(SongTitleExtractor.bracketedSegments('「晴天」「晴天」「x」').length).assertEqual(1);
    });

    it('tagBracketsDropOutOfVideoStyleNames', 0, async () => {
      // Second real-device case: 【tag】 brackets label the upload, the song
      // name sits outside them and must become the search title.
      const tagged = '【洛天依原创/9.1万粉感谢】91度的水汽凝结';
      expect(SongTitleExtractor.stripTagBrackets(tagged)).assertEqual('91度的水汽凝结');
      const extracted = await SongTitleExtractor.extract(tagged, new FakeNlp([], []));
      expect(extracted.title).assertEqual('91度的水汽凝结');
      expect(extracted.artist).assertEqual('');
      // Tags around a quoted name: the quote wins once the tags are gone.
      expect(SongTitleExtractor.preferCornerSegment(
        SongTitleExtractor.stripTagBrackets('【MAD】「薄采ディスプレイ」'))).assertEqual('薄采ディスプレイ');
      // Nothing but tags keeps the original text.
      expect(SongTitleExtractor.stripTagBrackets('【tag】')).assertEqual('【tag】');
      // The untagged remainder doubles as the retry keyword.
      const segments = SongTitleExtractor.bracketedSegments(tagged);
      expect(segments.length).assertEqual(1);
      expect(segments[0]).assertEqual('91度的水汽凝结');
    });
  });
}
