import { describe, it, expect } from '@ohos/hypium';
import { AudioQualityPolicy } from '../../../main/ets/player/AudioQualityPolicy';

export default function audioQualityPolicyTest(): void {
  describe('AudioQualityPolicy', () => {
    it('perNetworkChoiceWins', 0, () => {
      expect(AudioQualityPolicy.resolve(true, 'lossless', 'standard', 'exhigh'))
        .assertEqual('lossless');
      expect(AudioQualityPolicy.resolve(false, 'lossless', 'standard', 'exhigh'))
        .assertEqual('standard');
    });

    it('emptyPerNetworkValueInheritsLegacy', 0, () => {
      // 未单独设置过的网络沿用旧的单选值（np.audio_quality）。
      expect(AudioQualityPolicy.resolve(true, '', 'hires', 'exhigh'))
        .assertEqual('exhigh');
      expect(AudioQualityPolicy.resolve(false, 'hires', '', 'exhigh'))
        .assertEqual('exhigh');
    });

    it('allEmptyFallsBackToDefault', 0, () => {
      expect(AudioQualityPolicy.resolve(true, '', '', ''))
        .assertEqual(AudioQualityPolicy.DEFAULT_QUALITY);
      expect(AudioQualityPolicy.resolve(false, '', '', ''))
        .assertEqual(AudioQualityPolicy.DEFAULT_QUALITY);
    });

    it('legacyEmptyStillHonorsPerNetworkChoice', 0, () => {
      expect(AudioQualityPolicy.resolve(true, 'hires', '', ''))
        .assertEqual('hires');
      expect(AudioQualityPolicy.resolve(false, '', 'high', ''))
        .assertEqual('high');
    });
  });
}
