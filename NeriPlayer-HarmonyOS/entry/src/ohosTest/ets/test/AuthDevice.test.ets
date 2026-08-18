import { describe, it, expect } from '@ohos/hypium';
import { CredentialStore } from '../../../main/ets/data/auth/CredentialStore';
import { NeteaseCookieRepository } from '../../../main/ets/data/auth/NeteaseCookieRepository';
import { NeteaseQrLoginClient } from '../../../main/ets/network/NeteaseQrLogin';
import { BiliCookieRepository } from '../../../main/ets/data/auth/BiliCookieRepository';
import { BiliQrLoginClient } from '../../../main/ets/network/BiliQrLogin';

/**
 * Device tests for the credential infrastructure (M4.1) and the NetEase QR
 * login flow (M4.2). The QR smoke test only exercises createSession +
 * checkLogin against the real network: a fresh session must report 801
 * (waiting for scan) without any phone-side confirmation.
 */
export default function authDeviceTest(): void {
  describe('ActsCredentialStoreTest', () => {
    const alias = `neri_test_asset_${Date.now()}`;

    it('putGetStringRoundtrip', 0, async () => {
      const putOk = await CredentialStore.putString(alias, 'secret-value-123');
      expect(putOk).assertTrue();
      const value = await CredentialStore.getString(alias);
      expect(value).assertEqual('secret-value-123');
    });

    it('removeMakesValueEmpty', 0, async () => {
      const removed = await CredentialStore.remove(alias);
      expect(removed).assertTrue();
      const value = await CredentialStore.getString(alias);
      expect(value).assertEqual('');
    });

    it('backendIsReported', 0, async () => {
      // Either 'asset' (persistent) or 'memory' (degraded session-only).
      // Both must round-trip values; only persistence differs.
      const name = CredentialStore.backendName();
      expect(name === 'asset' || name === 'memory').assertTrue();
      const ok = await CredentialStore.putString(alias, 'backend-probe');
      expect(ok).assertTrue();
      const v = await CredentialStore.getString(alias);
      expect(v).assertEqual('backend-probe');
      await CredentialStore.remove(alias);
    });
  });

  describe('ActsNeteaseCookieRepositoryTest', () => {
    it('savePastedCookiesAndClear', 0, async () => {
      const saved = NeteaseCookieRepository.saveFromPastedText('MUSIC_U=device-test-token; __csrf=csrf1; os=pc');
      expect(saved).assertTrue();
      expect(NeteaseCookieRepository.isLoggedIn()).assertTrue();

      // The bundle must be persisted through the credential backend.
      const raw = await CredentialStore.getString(NeteaseCookieRepository.ALIAS);
      expect(raw.length > 0).assertTrue();
      expect(raw.indexOf('MUSIC_U') >= 0).assertTrue();
      expect(raw.indexOf('device-test-token') >= 0).assertTrue();

      await NeteaseCookieRepository.clear();
      expect(NeteaseCookieRepository.isLoggedIn()).assertFalse();
      const rawAfter = await CredentialStore.getString(NeteaseCookieRepository.ALIAS);
      expect(rawAfter).assertEqual('');
    });

    it('rejectsPasteWithoutMusicU', 0, () => {
      const saved = NeteaseCookieRepository.saveFromPastedText('__csrf=only; os=pc');
      expect(saved).assertFalse();
      expect(NeteaseCookieRepository.isLoggedIn()).assertFalse();
    });
  });

  describe('ActsNeteaseQrLoginTest', () => {
    it('createSessionBuildsScanUrlAndFreshCheckIsWaiting', 0, async () => {
      const session = await NeteaseQrLoginClient.createSession();
      expect(session.key.length > 0).assertTrue();
      expect(session.qrContent.startsWith('https://music.163.com/st/platform/scanlogin?codekey=')).assertTrue();
      expect(session.qrContent.indexOf(session.key) > 0).assertTrue();
      expect(session.chainId.startsWith('v1_')).assertTrue();

      const check = await NeteaseQrLoginClient.checkLogin(session);
      // Nobody scanned this fresh key: the documented stable states are 801
      // (waiting). 800 (expired) would mean the key aged out mid-test.
      expect(check.code === 801 || check.code === 800).assertTrue();
    });
  });

  describe('ActsBiliCookieRepositoryTest', () => {
    it('savePastedCookiesAndClear', 0, async () => {
      const saved = BiliCookieRepository.saveFromPastedText(
        'SESSDATA=device-test-sess; bili_jct=jct1; DedeUserID=425555; buvid3=XY123'
      );
      expect(saved).assertTrue();
      expect(BiliCookieRepository.isLoggedIn()).assertTrue();
      expect(BiliCookieRepository.getMid()).assertEqual(425555);

      // The bundle must be persisted through the credential backend, values
      // never logged.
      const raw = await CredentialStore.getString(BiliCookieRepository.ALIAS);
      expect(raw.length > 0).assertTrue();
      expect(raw.indexOf('SESSDATA') >= 0).assertTrue();
      expect(raw.indexOf('device-test-sess') >= 0).assertTrue();

      await BiliCookieRepository.clear();
      expect(BiliCookieRepository.isLoggedIn()).assertFalse();
      expect(BiliCookieRepository.getMid()).assertEqual(0);
      const rawAfter = await CredentialStore.getString(BiliCookieRepository.ALIAS);
      expect(rawAfter).assertEqual('');
    });

    it('rejectsPasteWithoutSessdata', 0, () => {
      const saved = BiliCookieRepository.saveFromPastedText('buvid3=only; sid=zz');
      expect(saved).assertFalse();
      expect(BiliCookieRepository.isLoggedIn()).assertFalse();
    });
  });

  describe('ActsBiliQrLoginTest', () => {
    it('createSessionBuildsScanUrlAndFreshCheckIsWaiting', 0, async () => {
      const session = await BiliQrLoginClient.createSession();
      expect(session.key.length > 0).assertTrue();
      // qrContent is data.url from the generate endpoint: a passport scan URL
      // embedding the qrcode_key.
      expect(session.qrContent.startsWith('https://')).assertTrue();
      expect(session.qrContent.indexOf(session.key) > 0).assertTrue();

      const check = await BiliQrLoginClient.checkLogin(session);
      // Fresh unscanned key: 86101 (waiting); 86038 would mean it expired
      // mid-test. Both are stable non-confirmed outcomes.
      expect(check.code === 86101 || check.code === 86038).assertTrue();
      expect(check.cookies.size === 0).assertTrue();
    });
  });
}
