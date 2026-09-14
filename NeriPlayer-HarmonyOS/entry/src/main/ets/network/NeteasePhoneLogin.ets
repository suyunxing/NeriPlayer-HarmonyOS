// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

import { Logger } from '../app/Logger';
import { Constants } from '../app/Constants';
import { HttpClient } from './HttpClient';
import { NeteaseCrypto } from './NeteaseCrypto';
import { md5Hex } from './BiliWbi';

/**
 * NetEase phone login (backlog §3.3, Android NeteaseClient loginByPhone /
 * sendCaptcha / verifyCaptcha / loginByCaptcha): password login carries the
 * md5 hex of the password, captcha login verifies the SMS code first and then
 * logs in with it. Login responses deliver MUSIC_U through Set-Cookie, so the
 * shared jar (useCookies=true) accumulates the session exactly like the QR
 * flow the repository already trusts.
 */

const ORIGIN: string = `${Constants.NETEASE_BASE}/`;
const LOGIN_PATH: string = '/weapi/login/cellphone';
const CAPTCHA_SENT_PATH: string = '/weapi/sms/captcha/sent';
const CAPTCHA_VERIFY_PATH: string = '/weapi/sms/captcha/verify';
const DESKTOP_UA: string =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36 Edg/149.0.0.0';

export class NeteaseLoginResult {
  code: number = -1;
  message: string = '';
  cookies: Map<string, string> = new Map<string, string>();

  get ok(): boolean {
    return this.code === 200;
  }
}

function headers(): Record<string, string> {
  const header: Record<string, string> = {};
  header['Accept'] = '*/*';
  header['Accept-Language'] = 'zh-CN,zh-Hans;q=0.9';
  header['Referer'] = ORIGIN;
  header['Origin'] = Constants.NETEASE_BASE;
  header['User-Agent'] = DESKTOP_UA;
  header['Host'] = 'music.163.com';
  return header;
}

function csrfFromJar(): string {
  const csrf = HttpClient.getCookiesMap(ORIGIN).get('__csrf');
  return csrf === undefined ? '' : csrf;
}

async function postWeapi(path: string, payload: Record<string, Object>): Promise<NeteaseLoginResult> {
  const params = await NeteaseCrypto.weapiParams(payload);
  const result = await HttpClient.postFormDetailed(
    `${Constants.NETEASE_BASE}${path}?csrf_token=${csrfFromJar()}`,
    params,
    15000,
    headers(),
    true
  );
  const out = new NeteaseLoginResult();
  try {
    const root = JSON.parse(result.text) as Record<string, Object>;
    out.code = root['code'] === undefined || root['code'] === null ? -1 : Number(root['code']);
    const message = root['message'] ?? root['msg'] ?? '';
    out.message = String(message);
  } catch (error) {
    const e = error as Error;
    Logger.warn(`netease phone login json parse failed: ${e.message}`);
  }
  return out;
}

export class NeteasePhoneLoginClient {
  /** Sends the SMS captcha (Android sendCaptcha; `cellphone`+`ctcode`). */
  static async sendCaptcha(phone: string, ctcode: number = 86): Promise<NeteaseLoginResult> {
    const payload: Record<string, Object> = {};
    payload['cellphone'] = phone;
    payload['ctcode'] = `${ctcode}`;
    return postWeapi(CAPTCHA_SENT_PATH, payload);
  }

  /** Verifies the SMS code without logging in (Android verifyCaptcha). */
  static async verifyCaptcha(phone: string, captcha: string, ctcode: number = 86): Promise<NeteaseLoginResult> {
    const payload: Record<string, Object> = {};
    payload['cellphone'] = phone;
    payload['captcha'] = captcha;
    payload['ctcode'] = `${ctcode}`;
    return postWeapi(CAPTCHA_VERIFY_PATH, payload);
  }

  /** SMS-captcha login (Android loginByCaptcha): verify first, then login. */
  static async loginByCaptcha(phone: string, captcha: string, ctcode: number = 86): Promise<NeteaseLoginResult> {
    const verified = await NeteasePhoneLoginClient.verifyCaptcha(phone, captcha, ctcode);
    if (!verified.ok) {
      return verified;
    }
    const payload: Record<string, Object> = {};
    payload['phone'] = phone;
    payload['countrycode'] = `${ctcode}`;
    payload['remember'] = 'true';
    payload['type'] = '1';
    payload['captcha'] = captcha;
    return NeteasePhoneLoginClient.finishLogin(await postWeapi(LOGIN_PATH, payload));
  }

  /** Password login (Android loginByPhone): the password travels as md5 hex. */
  static async loginByPassword(phone: string, password: string, ctcode: number = 86): Promise<NeteaseLoginResult> {
    const payload: Record<string, Object> = {};
    payload['phone'] = phone;
    payload['countrycode'] = `${ctcode}`;
    payload['remember'] = 'true';
    payload['type'] = '1';
    payload['password'] = md5Hex(password);
    return NeteasePhoneLoginClient.finishLogin(await postWeapi(LOGIN_PATH, payload));
  }

  private static finishLogin(result: NeteaseLoginResult): NeteaseLoginResult {
    if (result.ok) {
      result.cookies = HttpClient.getCookiesMap(ORIGIN);
    }
    return result;
  }
}
