import { describe, it, expect } from '@ohos/hypium';
import {
  CURRENT_DISCLAIMER_VERSION,
  isDisclaimerConfirmationRequired
} from '../../../main/ets/util/DisclaimerConsentPolicy';

export default function disclaimerConsentPolicyTest(): void {
  describe('DisclaimerConsentPolicy', () => {
    it('freshInstallRequiresConfirmation', 0, () => {
      expect(isDisclaimerConfirmationRequired(false, '')).assertTrue();
    });

    it('olderConsentVersionRequiresReconfirmation', 0, () => {
      expect(isDisclaimerConfirmationRequired(true, '1')).assertTrue();
    });

    it('preVersioningConsentRequiresReconfirmation', 0, () => {
      // 版本化之前的安装只写过布尔同意，版本键为空串。
      expect(isDisclaimerConfirmationRequired(true, '')).assertTrue();
    });

    it('currentVersionConsentSkipsGate', 0, () => {
      expect(isDisclaimerConfirmationRequired(true, CURRENT_DISCLAIMER_VERSION)).assertFalse();
    });
  });
}
