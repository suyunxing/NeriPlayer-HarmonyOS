import { describe, it, expect } from '@ohos/hypium';
import { SongMatchScorer } from '../../../main/ets/util/SongMatchScorer';

export default function songMatchScorerTest(): void {
  describe('SongMatchScorer', () => {
    it('exactTitleWithCloseDurationPassesThreshold', 0, () => {
      const score = SongMatchScorer.score('晴天', '', 210000, '晴天', '', 205000);
      expect(score).assertEqual(100);
      expect(score >= SongMatchScorer.AUTO_APPLY_THRESHOLD).assertTrue();
    });

    it('normalizeFoldsCaseWidthAndBracketsToExact', 0, () => {
      expect(SongMatchScorer.normalizeText('Ｈｅｌｌｏ World')).assertEqual('hello world');
      expect(SongMatchScorer.normalizeText('Hello (World)!')).assertEqual('hello world');
      expect(SongMatchScorer.normalizeText('晴天 feat. 周杰伦')).assertEqual('晴天 周杰伦');
      const score = SongMatchScorer.score('Hello World', '', 0, 'ｈｅｌｌｏ ｗｏｒｌｄ', '', 0);
      expect(score).assertEqual(90);
    });

    it('partialTitleNeedsArtistOrDurationToApply', 0, () => {
      // Includes-only (64) stays below threshold on its own...
      const weak = SongMatchScorer.score('晴天', '', 0, '夜曲 晴天 live', '', 0);
      expect(weak).assertEqual(64);
      expect(weak >= SongMatchScorer.AUTO_APPLY_THRESHOLD).assertFalse();
      // ...and passes with a matching artist...
      expect(SongMatchScorer.score('晴天', '周杰伦', 0, '晴天', '周杰伦', 0)).assertEqual(145);
      // ...or a close duration.
      expect(SongMatchScorer.score('晴天', '', 200000, '夜曲 晴天 (Live)', '', 205000)).assertEqual(74);
      // Prefix variants (bracket noise folds away) score one notch higher.
      expect(SongMatchScorer.score('晴天', '', 200000, '晴天 (Live)', '', 205000)).assertEqual(88);
    });

    it('durationBonusOnlyWithinTolerance', 0, () => {
      expect(SongMatchScorer.score('晴天', '', 200000, '晴天', '', 205000)).assertEqual(100);
      expect(SongMatchScorer.score('晴天', '', 200000, '晴天', '', 230000)).assertEqual(90);
      expect(SongMatchScorer.score('晴天', '', 0, '晴天', '', 205000)).assertEqual(90);
    });

    it('unrelatedArtistRejectsCandidateEvenWithTokenOverlap', 0, () => {
      // Title tokens overlap but the expected artist is nowhere in the
      // candidate's artist or title: a drifted search hit, always rejected.
      const drifted = SongMatchScorer.score('晴天', '周杰伦', 200000, '晴天故事', '群星', 200000);
      expect(drifted).assertEqual(0);
      // ...unless the expected artist shows up in the candidate title
      // (e.g. a wrong-direction file split).
      const crossed = SongMatchScorer.score('周杰伦', '晴天', 0, '晴天', '周杰伦', 0);
      expect(crossed >= SongMatchScorer.AUTO_APPLY_THRESHOLD).assertFalse();
    });

    it('tokenOverlapFillsTitleScoreBelowExact', 0, () => {
      // "晴天 千里之外" tokens vs candidate "千里之外 晴天 特别版" -> partial overlap.
      const score = SongMatchScorer.score('晴天 千里之外', '', 0, '千里之外 晴天 特别版', '', 0);
      expect(score).assertEqual(12);
    });

    it('normalizeFoldsCjkQuotingBrackets', 0, () => {
      expect(SongMatchScorer.normalizeText('《晴天》')).assertEqual('晴天');
      expect(SongMatchScorer.normalizeText('「薄采ディスプレイ」（淡彩Display）')).assertEqual('薄采ディスプレイ 淡彩display');
      expect(SongMatchScorer.normalizeText('【官方MV】晴天・Live')).assertEqual('官方mv 晴天 live');
      expect(SongMatchScorer.tokenize('《少女乐队的呐喊》官方MV「薄采ディスプレイ」').length).assertEqual(3);
    });

    it('uploaderArtistDoesNotVetoCoveredTitleWithCloseDuration', 0, () => {
      // Real-device case: Bilibili upload, displayArtist is the uploader and
      // never appears in the real band's candidate. Exact title + duration
      // within tolerance must still auto-apply.
      const exact = SongMatchScorer.score(
        '薄采ディスプレイ', '少女乐队的呐喊官方', 187925, '薄采ディスプレイ', 'トゲナシトゲアリ', 188264);
      expect(exact).assertEqual(100);
      // Whole video name as the expected title: the candidate is a substring
      // of it (includes 64) and the duration bonus clears the threshold.
      const covered = SongMatchScorer.score(
        '《少女乐队的呐喊》官方MV「薄采ディスプレイ」中文字幕（淡彩Display）', '少女乐队的呐喊官方', 187925,
        '薄采ディスプレイ', 'トゲナシトゲアリ', 188264);
      expect(covered).assertEqual(74);
      expect(covered >= SongMatchScorer.AUTO_APPLY_THRESHOLD).assertTrue();
      // Without the duration agreement the veto stays in force.
      const farDuration = SongMatchScorer.score(
        '薄采ディスプレイ', '少女乐队的呐喊官方', 187925, '薄采ディスプレイ', 'トゲナシトゲアリ', 240000);
      expect(farDuration).assertEqual(0);
      // A candidate longer than the expected title (prefix hit) is not
      // "covered": the drift rejection from the previous test still applies.
      expect(SongMatchScorer.score('晴天', '周杰伦', 200000, '晴天故事', '群星', 200000)).assertEqual(0);
    });
  });
}
