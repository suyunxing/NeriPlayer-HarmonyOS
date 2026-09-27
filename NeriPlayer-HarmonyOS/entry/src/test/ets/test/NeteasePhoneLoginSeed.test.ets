import { describe, it, expect } from '@ohos/hypium';
import { buildWebSessionSeed, fallbackNmtid } from '../../../main/ets/network/NeteasePhoneLogin';

/**
 * Fingerprint-cookie seed of the phone-login web session. The captcha → login
 * round-trip depends on these cookies surviving intact in the shared jar, so
 * the exact value set is pinned here (web client osMap "pc" set).
 */
export default function neteasePhoneLoginSeedTest(): void {
  describe('NeteasePhoneLoginSeed', () => {
    it('buildWebSessionSeedCarriesPcFingerprint', 0, () => {
      const seed = buildWebSessionSeed('a'.repeat(32), 'abcdef', 1695000000000);
      expect(seed).assertContain('os=pc');
      expect(seed).assertContain('appver=8.10.35');
      expect(seed).assertContain('osver=Microsoft-Windows-10-Professional-build-19045-64bit');
      expect(seed).assertContain('channel=netease');
      expect(seed).assertContain('__remember_me=true');
      expect(seed).assertContain('ntes_kaola_ad=1');
      expect(seed).assertContain('WEVNSM=1.0.0');
    });

    it('buildWebSessionSeedEmbedsStableSessionIds', 0, () => {
      const seed = buildWebSessionSeed('0123abcdef', 'xyzabc', 1695000000000);
      expect(seed).assertContain('_ntes_nuid=0123abcdef');
      expect(seed).assertContain('_ntes_nnid=0123abcdef,1695000000000');
      expect(seed).assertContain('WNMCID=xyzabc.1695000000000.01.0');
    });

    it('fallbackNmtidMatchesCommunityShape', 0, () => {
      const nmtid = fallbackNmtid();
      expect(nmtid.startsWith('00O')).assertTrue();
      expect(nmtid.length).assertEqual(22);
      const tail = nmtid.substring(3);
      expect(/^[0-9a-f]+$/.test(tail)).assertTrue();
    });
  });
}
