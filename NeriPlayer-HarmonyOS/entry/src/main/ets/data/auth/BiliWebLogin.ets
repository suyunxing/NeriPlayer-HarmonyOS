// SPDX-License-Identifier: GPL-3.0

/**
 * Pure helpers for the embedded Bilibili web login (ArkWeb opens the official
 * passport page, mirroring Android data/auth/web/WebLoginCompletionHeuristics.kt
 * and BiliWebLoginActivity's navigation allowlist). No platform imports:
 * unit-testable in the local hypium environment.
 */

import {
  BiliAuthBundle,
  BiliAuthHealthState,
  evaluateBiliAuthHealth
} from './BiliAuth';

/** 官方登录页地址（与 Android 上游 BiliWebLoginActivity.LOGIN_URL 一致）。 */
export const BILI_WEB_LOGIN_URL: string = 'https://passport.bilibili.com/login';

/** 主框架导航只允许登录相关域（对齐上游 ALLOWED_LOGIN_DOMAINS）。 */
const BILI_LOGIN_ALLOWED_DOMAINS: string[] = ['bilibili.com', 'hdslb.com', 'biliimg.com'];

/**
 * 完成检测依次抓取的 URL。合并时后面的域覆盖前面的同名键：passport 放在
 * 最后，登录动作直接落在 passport host 上的 Cookie 优先级最高。
 */
export const BILI_WEB_COOKIE_FETCH_URLS: string[] = [
  'https://bilibili.com',
  'https://www.bilibili.com',
  'https://m.bilibili.com',
  'https://passport.bilibili.com'
];

/**
 * Merges WebView cookie header texts ("k=v; k2=v2") fetched for several
 * domains. Later texts win on key conflicts; blank values are dropped so an
 * expiring overwrite is never mistaken for a login cookie.
 */
export function mergeCookieHeaderTexts(texts: string[]): Map<string, string> {
  const out = new Map<string, string>();
  if (texts === undefined || texts === null) {
    return out;
  }
  for (const text of texts) {
    if (text === undefined || text === null || text.length === 0) {
      continue;
    }
    const pairs = text.split(';');
    for (const pair of pairs) {
      const eq = pair.indexOf('=');
      if (eq <= 0) {
        continue;
      }
      const key = pair.substring(0, eq).trim();
      const value = pair.substring(eq + 1).trim();
      if (key.length === 0 || value.length === 0) {
        continue;
      }
      out.set(key, value);
    }
  }
  return out;
}

/**
 * Completion heuristic (mirrors Android shouldAutoCompleteBiliWebLogin): the
 * observed cookie set counts as logged in when the synthesized bundle's auth
 * health is not Missing — i.e. a non-blank SESSDATA is present. Login success
 * pages are unstable across redesigns, so real credential keys decide.
 */
export function shouldAutoCompleteBiliWebLogin(cookies: Map<string, string>): boolean {
  if (cookies === undefined || cookies === null) {
    return false;
  }
  const bundle = new BiliAuthBundle();
  bundle.cookies = cookies;
  const health = evaluateBiliAuthHealth(bundle, 2);
  return health.state !== BiliAuthHealthState.MISSING;
}

/**
 * Main-frame navigation allowlist for the embedded login page: https on the
 * login domains (exact host or any subdomain), plus about:blank. Everything
 * else is blocked in onLoadIntercept (mirrors upstream isAllowedLoginUri).
 */
export function isAllowedBiliLoginNavigation(url: string): boolean {
  if (url === undefined || url === null) {
    return false;
  }
  const trimmed = url.trim();
  if (trimmed === 'about:blank') {
    return true;
  }
  const schemeEnd = trimmed.indexOf('://');
  if (schemeEnd <= 0) {
    return false;
  }
  const scheme = trimmed.substring(0, schemeEnd).toLowerCase();
  if (scheme !== 'https') {
    return false;
  }
  const rest = trimmed.substring(schemeEnd + 3);
  const host = rest.substring(0, hostEnd(rest)).toLowerCase();
  for (const domain of BILI_LOGIN_ALLOWED_DOMAINS) {
    if (host === domain || host.endsWith(`.${domain}`)) {
      return true;
    }
  }
  return false;
}

function hostEnd(rest: string): number {
  let end = rest.length;
  const stops: string[] = ['/', ':', '?', '#'];
  for (const stop of stops) {
    const at = rest.indexOf(stop);
    if (at >= 0 && at < end) {
      end = at;
    }
  }
  return end;
}
