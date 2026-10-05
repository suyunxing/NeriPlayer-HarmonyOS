import { describe, it, expect } from '@ohos/hypium';
import { privacyManager } from '@kit.AppGalleryKit';
import { pickHostedPrivacyLinks } from '../../../main/ets/util/AgcPrivacyHost';

function link(type: privacyManager.AppPrivacyLinkType, url: string): privacyManager.AppPrivacyLink {
  return { type: type, url: url, versionCode: 1, id: 'test' };
}

export default function agcPrivacyHostTest(): void {
  describe('AgcPrivacyHost', () => {
    it('picksBothHostedDocUrls', 0, () => {
      const hosted = pickHostedPrivacyLinks([
        link(privacyManager.AppPrivacyLinkType.PRIVACY_STATEMENT_LINK, 'https://host/privacy'),
        link(privacyManager.AppPrivacyLinkType.USER_AGREEMENT_LINK, 'https://host/agreement')
      ]);
      expect(hosted?.privacyUrl).assertEqual('https://host/privacy');
      expect(hosted?.agreementUrl).assertEqual('https://host/agreement');
    });

    it('missingUserAgreementStillCountsAsHosted', 0, () => {
      // 用户协议托管是官方非必须项：只有隐私声明链接即视为托管生效。
      const hosted = pickHostedPrivacyLinks([
        link(privacyManager.AppPrivacyLinkType.PRIVACY_STATEMENT_LINK, 'https://host/privacy')
      ]);
      expect(hosted !== null).assertTrue();
      expect(hosted?.agreementUrl).assertEqual('');
    });

    it('missingPrivacyStatementMeansNotHosted', 0, () => {
      const hosted = pickHostedPrivacyLinks([
        link(privacyManager.AppPrivacyLinkType.USER_AGREEMENT_LINK, 'https://host/agreement')
      ]);
      expect(hosted).assertNull();
    });

    it('ignoresEmptyUrlEntries', 0, () => {
      const hosted = pickHostedPrivacyLinks([
        link(privacyManager.AppPrivacyLinkType.PRIVACY_STATEMENT_LINK, ''),
        link(privacyManager.AppPrivacyLinkType.PRIVACY_STATEMENT_LINK, 'https://host/privacy'),
        link(privacyManager.AppPrivacyLinkType.USER_AGREEMENT_LINK, '')
      ]);
      expect(hosted?.privacyUrl).assertEqual('https://host/privacy');
      expect(hosted?.agreementUrl).assertEqual('');
    });
  });
}
