import { describe, it, expect } from '@ohos/hypium';
import {
  buildWebSessionSeed,
  fallbackNmtid,
  cloudmusicDllEncodeId,
  buildRegisterUsername
} from '../../../main/ets/network/NeteasePhoneLogin';

/**
 * Fingerprint-cookie seed and anonymous-device helpers of the phone-login web
 * session. The captcha → login round-trip depends on these cookies surviving
 * intact in the shared jar, so the exact value set is pinned here (web client
 * osMap "pc" set); the dll-encode id vectors are known answers computed with
 * Node crypto over the canonical magic string.
 */
export default function neteasePhoneLoginSeedTest(): void {
  describe('NeteasePhoneLoginSeed', () => {
    it('buildWebSessionSeedCarriesPcFingerprint', 0, () => {
      const seed = buildWebSessionSeed('a'.repeat(32), 'abcdef', 1695000000000);
      expect(seed).assertContain('os=pc');
      expect(seed).assertContain('appver=3.1.17.204416');
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
      // 32 random hex chars — the shape the community client generates when
      // the server never issues an NMTID (api-enhanced PR #243 behaviour).
      const nmtid = fallbackNmtid();
      expect(nmtid.length).assertEqual(32);
      expect(/^[0-9a-f]+$/.test(nmtid)).assertTrue();
      expect(fallbackNmtid() === nmtid).assertFalse();
    });

    it('cloudmusicDllEncodeIdMatchesNodeVectors', 0, () => {
      // Known answers: XOR with '3go8&$8*3*3h0k(2)2', MD5 over the bytes,
      // base64 of the digest (Node crypto reference implementation).
      expect(cloudmusicDllEncodeId('testdev')).assertEqual('aUNnZQ4t4g9xOuS/lFXa7Q==');
      expect(cloudmusicDllEncodeId('AB23CD45EF67AB23CD45EF67AB23CD45EF67AB23CD45EF67AB23CD4'))
        .assertEqual('AQnKVRmBziu7FJISAzbr6A==');
    });

    it('buildRegisterUsernameBase64EncodesDeviceIdAndDigest', 0, () => {
      expect(buildRegisterUsername('testdev'))
        .assertEqual('dGVzdGRldiBhVU5uWlE0dDRnOXhPdVMvbEZYYTdRPT0=');
    });
  });
}
