import { describe, it, expect } from '@ohos/hypium';
import {
  isNeteaseWebLoginComplete,
  isAllowedNeteaseLoginNavigation,
  mergeCookieHeaderTexts
} from '../../../main/ets/data/auth/NeteaseWebLogin';

/**
 * Pure helpers of the embedded NetEase web login: completion detection (the
 * page harvests the cookie pool as soon as MUSIC_U appears) and the
 * main-frame navigation allowlist.
 */
function mapOf(pairs: string[][]): Map<string, string> {
  const out = new Map<string, string>();
  for (const pair of pairs) {
    out.set(pair[0], pair[1]);
  }
  return out;
}

export default function neteaseWebLoginTest(): void {
  describe('NeteaseWebLogin', () => {
    it('webLoginCompleteRequiresNonEmptyMusicU', 0, () => {
      expect(isNeteaseWebLoginComplete(new Map())).assertFalse();
      expect(isNeteaseWebLoginComplete(mapOf([['__csrf', 'abc'], ['NMTID', 'x']]))).assertFalse();
      expect(isNeteaseWebLoginComplete(mapOf([['MUSIC_U', '']]))).assertFalse();
      expect(isNeteaseWebLoginComplete(mapOf([['__csrf', 'abc'], ['MUSIC_U', 'token']]))).assertTrue();
    });

    it('navigationAllowlistAcceptsOnlyHttpsNeteaseHosts', 0, () => {
      expect(isAllowedNeteaseLoginNavigation('https://music.163.com/#/login')).assertTrue();
      expect(isAllowedNeteaseLoginNavigation('https://music.163.com/')).assertTrue();
      expect(isAllowedNeteaseLoginNavigation('https://interface.music.163.com/eapi/x')).assertTrue();
      // 子域后缀必须按 label 边界匹配，notmusic.163.com 不是网易云域。
      expect(isAllowedNeteaseLoginNavigation('https://notmusic.163.com/login')).assertFalse();
      expect(isAllowedNeteaseLoginNavigation('https://music.163.com.evil.example/')).assertFalse();
      expect(isAllowedNeteaseLoginNavigation('http://music.163.com/')).assertFalse();
      expect(isAllowedNeteaseLoginNavigation('https://www.example.com/redirect')).assertFalse();
      expect(isAllowedNeteaseLoginNavigation('music.163.com')).assertFalse();
    });

    it('mergeDropsBlankValuesSoExpiringOverwriteNeverWins', 0, () => {
      const merged = mergeCookieHeaderTexts([
        'MUSIC_U=token; __csrf=abc',
        'MUSIC_U=; os=pc'
      ]);
      expect(merged.get('MUSIC_U')).assertEqual('token');
      expect(merged.get('os')).assertEqual('pc');
    });
  });
}
