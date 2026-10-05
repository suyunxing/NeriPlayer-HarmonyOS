import { describe, it, expect } from '@ohos/hypium';
import {
  BILI_WEB_LOGIN_URL,
  BILI_WEB_COOKIE_FETCH_URLS,
  mergeCookieHeaderTexts,
  shouldAutoCompleteBiliWebLogin,
  isAllowedBiliLoginNavigation,
  sanitizeUrlForLog
} from '../../../main/ets/data/auth/BiliWebLogin';

function mapOf(pairs: string[][]): Map<string, string> {
  const out = new Map<string, string>();
  for (const pair of pairs) {
    out.set(pair[0], pair[1]);
  }
  return out;
}

export default function biliWebLoginTest(): void {
  describe('BiliWebLogin', () => {
    it('loginUrlMatchesAndroidUpstream', 0, () => {
      expect(BILI_WEB_LOGIN_URL).assertEqual('https://passport.bilibili.com/login');
      expect(BILI_WEB_COOKIE_FETCH_URLS[BILI_WEB_COOKIE_FETCH_URLS.length - 1])
        .assertEqual('https://passport.bilibili.com');
    });

    it('mergeCookieHeaderTextsMergesLaterDomainsOverEarlier', 0, () => {
      const merged = mergeCookieHeaderTexts([
        'buvid3=abc; sid=old; SESSDATA=stale',
        'DedeUserID=42; sid=new',
        // passport 放最后：host 级同名键覆盖前面的
        'SESSDATA=fresh; bili_jct=jct'
      ]);
      expect(merged.size).assertEqual(5);
      expect(merged.get('SESSDATA')).assertEqual('fresh');
      expect(merged.get('sid')).assertEqual('new');
      expect(merged.get('DedeUserID')).assertEqual('42');
      expect(merged.get('bili_jct')).assertEqual('jct');
      expect(merged.get('buvid3')).assertEqual('abc');
    });

    it('mergeCookieHeaderTextsDropsBlankValuesAndMalformedPairs', 0, () => {
      const merged = mergeCookieHeaderTexts([
        'k=v; expired=; novalue; =emptykey; =',
        '',
        'ok=1'
      ]);
      expect(merged.size).assertEqual(2);
      expect(merged.get('k')).assertEqual('v');
      expect(merged.get('ok')).assertEqual('1');
      expect(merged.has('expired')).assertFalse();
      expect(merged.has('novalue')).assertFalse();
    });

    it('mergeCookieHeaderTextsHandlesEmptyEntries', 0, () => {
      const merged = mergeCookieHeaderTexts([]);
      expect(merged.size).assertEqual(0);
    });

    it('autoCompleteRequiresNonBlankSessdata', 0, () => {
      expect(shouldAutoCompleteBiliWebLogin(mapOf([
        ['buvid3', 'abc'], ['DedeUserID', '42'], ['bili_jct', 'jct']
      ]))).assertFalse();
      expect(shouldAutoCompleteBiliWebLogin(mapOf([['SESSDATA', '']]))).assertFalse();
      expect(shouldAutoCompleteBiliWebLogin(mapOf([['SESSDATA', 'fresh-cookie']]))).assertTrue();
      expect(shouldAutoCompleteBiliWebLogin(new Map<string, string>())).assertFalse();
    });

    it('navigationAllowlistAcceptsLoginDomainsAndSubdomains', 0, () => {
      expect(isAllowedBiliLoginNavigation('https://passport.bilibili.com/login')).assertTrue();
      expect(isAllowedBiliLoginNavigation('https://www.bilibili.com/')).assertTrue();
      expect(isAllowedBiliLoginNavigation('https://m.bilibili.com/')).assertTrue();
      expect(isAllowedBiliLoginNavigation('https://bilibili.com')).assertTrue();
      expect(isAllowedBiliLoginNavigation('https://s1.hdslb.com/bfs/x.js')).assertTrue();
      expect(isAllowedBiliLoginNavigation('https://i0.hdslb.com/img.png?w=1')).assertTrue();
      expect(isAllowedBiliLoginNavigation('https://static.biliimg.com/a.png')).assertTrue();
      expect(isAllowedBiliLoginNavigation('https://www.bilibili.com:443/x')).assertTrue();
      expect(isAllowedBiliLoginNavigation('about:blank')).assertTrue();
    });

    it('navigationAllowlistRejectsNonHttpsAndForeignHosts', 0, () => {
      expect(isAllowedBiliLoginNavigation('http://www.bilibili.com/')).assertFalse();
      expect(isAllowedBiliLoginNavigation('https://evil.example.com/bilibili.com')).assertFalse();
      expect(isAllowedBiliLoginNavigation('https://bilibili.com.evil.example.com/')).assertFalse();
      expect(isAllowedBiliLoginNavigation('https://notbilibili.com/')).assertFalse();
      expect(isAllowedBiliLoginNavigation('file:///data/x.html')).assertFalse();
      expect(isAllowedBiliLoginNavigation('')).assertFalse();
      expect(isAllowedBiliLoginNavigation('passport.bilibili.com/login')).assertFalse();
    });

    it('sanitizeUrlForLogDropsQueryAndFragment', 0, () => {
      // 登录跳转链接的 query/fragment 可能携带凭据明文，日志只留 host+path。
      expect(sanitizeUrlForLog('https://passport.bilibili.com/x?token=secret#/h'))
        .assertEqual('https://passport.bilibili.com/x');
      expect(sanitizeUrlForLog('https://music.163.com/#/login'))
        .assertEqual('https://music.163.com/');
      expect(sanitizeUrlForLog('https://www.bilibili.com/')).assertEqual('https://www.bilibili.com/');
      expect(sanitizeUrlForLog('about:blank')).assertEqual('about:blank');
    });
  });
}
