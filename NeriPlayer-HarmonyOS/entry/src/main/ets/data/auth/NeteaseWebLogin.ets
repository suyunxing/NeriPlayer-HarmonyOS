// SPDX-License-Identifier: GPL-3.0

/**
 * Pure helpers for the embedded NetEase web login (ArkWeb opens the official
 * music.163.com login page — the community's stable login path after the
 * 2026 captcha-login risk-control tightening; go-musicfox shipped the same
 * webview approach after its protocol fight, and this app already uses the
 * identical pattern for Bilibili). No platform imports: unit-testable in the
 * local hypium environment.
 */

import { mergeCookieHeaderTexts, sanitizeUrlForLog } from './BiliWebLogin';

export { mergeCookieHeaderTexts, sanitizeUrlForLog };

/** 官方登录页：music.163.com 的 SPA 登录弹层（扫码/短信/邮箱由官方页面自理）。 */
export const NETEASE_WEB_LOGIN_URL: string = 'https://music.163.com/#/login';

/** 完成检测轮询的 Cookie 域（登录凭据 MUSIC_U 落在 .music.163.com）。 */
export const NETEASE_WEB_COOKIE_FETCH_URLS: string[] = ['https://music.163.com/'];

/**
 * 主框架导航只允许网易云域（登录后官方页可能带跳转链接，越界一律拦截）。
 * about:blank 放行（对齐 B 站侧同款白名单）：SPA 页面可能发起空白主框架
 * 导航，拦死会让页面停在上一帧。
 */
export function isAllowedNeteaseLoginNavigation(url: string): boolean {
  const trimmed = url.trim();
  if (trimmed === 'about:blank') {
    return true;
  }
  const marker = '://';
  const start = url.indexOf(marker);
  if (start < 0) {
    return false;
  }
  const scheme = url.substring(0, start).toLowerCase();
  if (scheme !== 'https') {
    return false;
  }
  const rest = url.substring(start + marker.length);
  const slash = rest.indexOf('/');
  const host = (slash >= 0 ? rest.substring(0, slash) : rest).toLowerCase();
  const port = host.lastIndexOf(':');
  const bare = port > 0 ? host.substring(0, port) : host;
  return bare === 'music.163.com' || bare.endsWith('.music.163.com');
}

/**
 * 完成判定：非空 MUSIC_U 即视为已登录（与 NeteaseAuth 的登录凭据键一致；
 * 兜底兜住 httpOnly 之外的会话键变化——校验链 saveInternal 仍会拒绝无
 * MUSIC_U 的快照）。
 */
export function isNeteaseWebLoginComplete(cookies: Map<string, string>): boolean {
  const musicU = cookies.get('MUSIC_U');
  return musicU !== undefined && musicU.length > 0;
}
