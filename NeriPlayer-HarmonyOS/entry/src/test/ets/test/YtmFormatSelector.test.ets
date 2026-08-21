import { describe, it, expect } from '@ohos/hypium';
import {
  YtmQualityTier,
  satisfiesYtmQualityTier,
  ytmMimePreferenceScore,
  ytmQualityTierFromSetting,
  orderYtmCandidatesByQualityTier,
  selectYtmDirectAudioCandidate
} from '../../../main/ets/network/ytm/YtmFormatSelector';
import { YtmAudioCandidate } from '../../../main/ets/network/ytm/YtmPlayerParser';

/**
 * Spike-shaped IOS audio formats (docs/YTMUSIC_M60_SPIKE.md §1.2):
 * itag 249 webm ~50k, 250 webm ~70k, 140 mp4 ~130k, 251 webm ~140k.
 */
function candidate(
  itag: number,
  mime: string,
  bitrate: number,
  url: string = 'https://rr.example.com/videoplayback?itag=' + itag
): YtmAudioCandidate {
  const c = new YtmAudioCandidate();
  c.itag = itag;
  c.mimeType = mime;
  c.bitrate = bitrate;
  c.audioSampleRateHz = 44100;
  c.contentLength = bitrate * 300;
  c.directUrl = url;
  return c;
}

function spikeCandidates(): YtmAudioCandidate[] {
  return [
    candidate(249, 'audio/webm; codecs="opus"', 50125),
    candidate(250, 'audio/webm; codecs="opus"', 70121),
    candidate(140, 'audio/mp4; codecs="mp4a.40.2"', 130268),
    candidate(251, 'audio/webm; codecs="opus"', 140517)
  ];
}

export default function ytmFormatSelectorTest(): void {
  describe('YtmFormatSelector', () => {
    it('mapsSettingKeysToTiers', 0, () => {
      expect(ytmQualityTierFromSetting('standard')).assertEqual(YtmQualityTier.LOW);
      expect(ytmQualityTierFromSetting('medium')).assertEqual(YtmQualityTier.MEDIUM);
      expect(ytmQualityTierFromSetting('high')).assertEqual(YtmQualityTier.HIGH);
      expect(ytmQualityTierFromSetting('exhigh')).assertEqual(YtmQualityTier.VERY_HIGH);
      expect(ytmQualityTierFromSetting('lossless')).assertEqual(YtmQualityTier.VERY_HIGH);
      expect(ytmQualityTierFromSetting('hires')).assertEqual(YtmQualityTier.VERY_HIGH);
      expect(ytmQualityTierFromSetting(null)).assertEqual(YtmQualityTier.VERY_HIGH);
    });

    it('veryHighKeepsHighestBitrateFirst', 0, () => {
      const ordered = orderYtmCandidatesByQualityTier(spikeCandidates(), YtmQualityTier.VERY_HIGH);
      expect(ordered[0].itag).assertEqual(251);
      expect(ordered[1].itag).assertEqual(140);
      expect(ordered[2].itag).assertEqual(250);
    });

    it('lowPrefersLowestBitrate', 0, () => {
      const ordered = orderYtmCandidatesByQualityTier(spikeCandidates(), YtmQualityTier.LOW);
      expect(ordered[0].itag).assertEqual(249);
      const picked = selectYtmDirectAudioCandidate(spikeCandidates(), YtmQualityTier.LOW);
      expect(picked.selected!.itag).assertEqual(249);
    });

    it('mediumPrioritizesFirstCandidateAbove96k', 0, () => {
      // Ascending: 50,70,130,140 -> first >=96k is 130 -> head [130,140] + reversed tail [70,50].
      const ordered = orderYtmCandidatesByQualityTier(spikeCandidates(), YtmQualityTier.MEDIUM);
      expect(ordered[0].itag).assertEqual(140);
      expect(ordered[1].itag).assertEqual(251);
      expect(ordered[2].itag).assertEqual(250);
      expect(ordered[3].itag).assertEqual(249);
    });

    it('highPrioritizesFirstCandidateAbove128k', 0, () => {
      const ordered = orderYtmCandidatesByQualityTier(spikeCandidates(), YtmQualityTier.HIGH);
      expect(ordered[0].itag).assertEqual(140);
    });

    it('thresholdMissFallsBackToDescending', 0, () => {
      const lowOnly = [candidate(249, 'audio/webm; codecs="opus"', 50125),
        candidate(250, 'audio/webm; codecs="opus"', 70121)];
      const ordered = orderYtmCandidatesByQualityTier(lowOnly, YtmQualityTier.MEDIUM);
      expect(ordered[0].itag).assertEqual(250);
    });

    it('comparatorBreaksTiesBySampleRateThenMimeThenLength', 0, () => {
      const webmHiSr = candidate(250, 'audio/webm; codecs="opus"', 100000);
      webmHiSr.audioSampleRateHz = 48000;
      const mp4LoSr = candidate(140, 'audio/mp4; codecs="mp4a.40.2"', 100000);
      mp4LoSr.audioSampleRateHz = 44100;
      // Same bitrate: higher sample rate first regardless of mime.
      let ordered = orderYtmCandidatesByQualityTier([mp4LoSr, webmHiSr], YtmQualityTier.VERY_HIGH);
      expect(ordered[0].itag).assertEqual(250);

      const webmSameSr = candidate(249, 'audio/webm; codecs="opus"', 100000);
      const mp4SameSr = candidate(140, 'audio/mp4; codecs="mp4a.40.2"', 100000);
      // Same bitrate + sample rate: mp4 preferred over webm.
      ordered = orderYtmCandidatesByQualityTier([webmSameSr, mp4SameSr], YtmQualityTier.VERY_HIGH);
      expect(ordered[0].itag).assertEqual(140);

      const small = candidate(249, 'audio/webm; codecs="opus"', 100000);
      small.contentLength = 1;
      const large = candidate(250, 'audio/webm; codecs="opus"', 100000);
      large.contentLength = 999999;
      // Full tie except length: larger content wins.
      ordered = orderYtmCandidatesByQualityTier([small, large], YtmQualityTier.VERY_HIGH);
      expect(ordered[0].itag).assertEqual(250);
    });

    it('selectsDirectUrlOnlyAndFlagsCipherOnlyResponses', 0, () => {
      const cipherOnly = candidate(251, 'audio/webm; codecs="opus"', 140517, '');
      cipherOnly.directUrl = '';
      cipherOnly.hasCipher = true;
      const selection = selectYtmDirectAudioCandidate([cipherOnly], YtmQualityTier.VERY_HIGH);
      expect(selection.selected).assertNull();
      expect(selection.needsDecrypt).assertTrue();

      // Mixed: the cipher row must never win over a direct URL row.
      const directLow = candidate(249, 'audio/webm; codecs="opus"', 50125);
      const mixed = selectYtmDirectAudioCandidate([cipherOnly, directLow], YtmQualityTier.VERY_HIGH);
      expect(mixed.needsDecrypt).assertFalse();
      expect(mixed.selected!.directUrl.length > 0).assertTrue();
    });

    it('satisfiesTierThresholds', 0, () => {
      expect(ytmTierPasses(90000, 'medium')).assertFalse();
      expect(ytmTierPasses(100000, 'medium')).assertTrue();
      expect(ytmTierPasses(127000, 'high')).assertFalse();
      expect(ytmTierPasses(128500, 'high')).assertTrue();
      expect(ytmTierPasses(159000, 'exhigh')).assertFalse();
      expect(ytmTierPasses(160500, 'exhigh')).assertTrue();
      // LOW never filters.
      expect(ytmTierPasses(1, 'standard')).assertTrue();
    });

    it('mimePreferenceScores', 0, () => {
      expect(ytmMimePreferenceScore('audio/mp4; codecs="mp4a.40.2"')).assertEqual(2);
      expect(ytmMimePreferenceScore('audio/webm; codecs="opus"')).assertEqual(1);
      expect(ytmMimePreferenceScore('audio/ogg')).assertEqual(0);
    });
  });
}

function ytmTierPasses(bitrate: number, settingKey: string): boolean {
  const c = candidate(0, 'audio/webm', bitrate);
  return satisfiesYtmQualityTier(c, ytmQualityTierFromSetting(settingKey));
}
