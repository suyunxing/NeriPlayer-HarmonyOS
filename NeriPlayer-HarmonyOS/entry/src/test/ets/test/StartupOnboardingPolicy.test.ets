// SPDX-License-Identifier: GPL-3.0
// Unit tests for the onboarding policy port (upstream
// StartupOnboardingProgressTest, commit 01c57a11).

import { describe, it, expect } from '@ohos/hypium';
import {
  STARTUP_ONBOARDING_STEP_COUNT,
  calculateStartupOnboardingProgress,
  shouldWarnStartupNoPlatformConnected
} from '../../../main/ets/view/onboarding/StartupOnboardingPolicy';

export default function StartupOnboardingPolicyTest() {
  describe('StartupOnboardingPolicy', () => {
    it('progressMatchesTheCurrentStepAcrossTheFlow', 0, () => {
      expect(calculateStartupOnboardingProgress(0, 9)).assertEqual(1 / 9);
      expect(calculateStartupOnboardingProgress(3, 9)).assertEqual(4 / 9);
      expect(calculateStartupOnboardingProgress(7, 9)).assertEqual(8 / 9);
      expect(calculateStartupOnboardingProgress(8, 9)).assertEqual(1);
      expect(STARTUP_ONBOARDING_STEP_COUNT).assertEqual(7);
      expect(calculateStartupOnboardingProgress(6, STARTUP_ONBOARDING_STEP_COUNT))
        .assertEqual(1);
    });

    it('progressStaysWithinTheIndicatorRange', 0, () => {
      expect(calculateStartupOnboardingProgress(-4, 6)).assertEqual(0);
      expect(calculateStartupOnboardingProgress(12, 6)).assertEqual(1);
      expect(calculateStartupOnboardingProgress(0, 0)).assertEqual(0);
    });

    it('noPlatformWarningOnlyAppliesWhenEveryPlatformIsMissing', 0, () => {
      // 两平台都未登录才提醒。
      expect(shouldWarnStartupNoPlatformConnected(false, false)).assertTrue();
      expect(shouldWarnStartupNoPlatformConnected(true, false)).assertFalse();
      expect(shouldWarnStartupNoPlatformConnected(false, true)).assertFalse();
      expect(shouldWarnStartupNoPlatformConnected(true, true)).assertFalse();
    });
  });
}
