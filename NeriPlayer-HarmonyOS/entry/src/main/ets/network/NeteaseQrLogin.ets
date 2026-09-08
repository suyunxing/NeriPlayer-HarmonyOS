import { Logger } from '../app/Logger';
import { Constants } from '../app/Constants';
import { HttpClient, HttpFormResult } from './HttpClient';
import { NeteaseCrypto } from './NeteaseCrypto';

/**
 * NetEase QR login client, ported from Android NeteaseQrLoginClient.kt.
 * Flow: createSession (weapi /weapi/login/qrcode/unikey) -> render QR of
 * qrContent -> poll checkLogin (/weapi/login/qrcode/client/login) until the
 * response code says expired(800)/waiting(801)/scanned(802)/confirmed(803).
 * On 803 the accumulated Set-Cookie jar is verified through the account
 * endpoint, with the x-refresh-token header as a MUSIC_U fallback.
 */

export const NETEASE_QR_EXPIRED: number = 800;
export const NETEASE_QR_WAITING: number = 801;
export const NETEASE_QR_SCANNED: number = 802;
export const NETEASE_QR_CONFIRMED: number = 803;

const QR_ORIGIN: string = `${Constants.NETEASE_BASE}/`;
const QR_UNIKEY_PATH: string = '/weapi/login/qrcode/unikey';
const QR_CHECK_PATH: string = '/weapi/login/qrcode/client/login';
const ACCOUNT_PATH: string = '/weapi/w/nuser/account/get';
const DESKTOP_UA: string =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36 Edg/149.0.0.0';

export class NeteaseQrSession {
  key: string = '';
  chainId: string = '';
  qrContent: string = '';
}

export class NeteaseQrCheckResult {
  code: number = -1;
  message: string = '';
  cookies: Map<string, string> = new Map();

  get isConfirmed(): boolean {
    return this.code === NETEASE_QR_CONFIRMED;
  }
}

interface QrHttpResponse {
  code: number;
  message: string;
  unikey: string;
  hasAccount: boolean;
}

function parseQrJson(text: string): QrHttpResponse {
  const out: QrHttpResponse = { code: -1, message: '', unikey: '', hasAccount: false };
  try {
    const root = JSON.parse(text) as Record<string, Object>;
    const code = root['code'];
    out.code = code === undefined || code === null ? -1 : Number(code);
    const message = root['message'];
    if (message === undefined || message === null) {
      const msg = root['msg'];
      out.message = msg === undefined || msg === null ? '' : String(msg);
    } else {
      out.message = String(message);
    }
    const unikey = root['unikey'];
    out.unikey = unikey === undefined || unikey === null ? '' : String(unikey).trim();
    const account = root['account'];
    const profile = root['profile'];
    out.hasAccount = (account !== undefined && account !== null) || (profile !== undefined && profile !== null);
  } catch (error) {
    const e = error as Error;
    Logger.warn(`netease qr json parse failed: ${e.message}`);
  }
  return out;
}

function jarCookies(): Map<string, string> {
  return HttpClient.getCookiesMap(QR_ORIGIN);
}

function csrfFromJar(): string {
  const csrf = jarCookies().get('__csrf');
  return csrf === undefined ? '' : csrf;
}

/** Cookie names only (never values) so logs stay credential-free. */
function cookieKeyList(): string {
  const keys = Array.from(jarCookies().keys());
  return keys.length > 0 ? keys.join(',') : '<empty>';
}

/** Response header names only, to verify the stack exposed set-cookie at all. */
function headerNameList(headerText: string): string {
  const names: string[] = [];
  for (const line of headerText.split('\n')) {
    const colon = line.indexOf(':');
    if (colon > 0) {
      names.push(line.substring(0, colon).trim().toLowerCase());
    }
  }
  return names.length > 0 ? names.join(',') : '<empty>';
}

export class NeteaseQrLoginClient {
  private static headers(): Record<string, string> {
    const header: Record<string, string> = {};
    header['Accept'] = '*/*';
    header['Accept-Encoding'] = 'gzip, br';
    header['Accept-Language'] = 'zh-CN,zh-Hans;q=0.9';
    header['Cache-Control'] = 'no-cache';
    header['Pragma'] = 'no-cache';
    header['Referer'] = QR_ORIGIN;
    header['Origin'] = Constants.NETEASE_BASE;
    header['User-Agent'] = DESKTOP_UA;
    header['Host'] = 'music.163.com';
    header['x-os'] = 'web';
    header['x-channelsource'] = 'undefined';
    header['nm-gcore-status'] = '1';
    return header;
  }

  static async createSession(): Promise<NeteaseQrSession> {
    const payload: Record<string, Object> = {};
    payload['type'] = 1;
    payload['noCheckToken'] = true;
    const params = await NeteaseCrypto.weapiParams(payload);
    const result = await HttpClient.postFormDetailed(
      `${Constants.NETEASE_BASE}${QR_UNIKEY_PATH}?csrf_token=${csrfFromJar()}`,
      params,
      15000,
      NeteaseQrLoginClient.headers(),
      true
    );
    const parsed = parseQrJson(result.text);
    if (parsed.code !== 200 || parsed.unikey.length === 0) {
      throw new Error(`Failed to create QR login session, code=${parsed.code} ${parsed.message}`);
    }
    const session = new NeteaseQrSession();
    session.key = parsed.unikey;
    // No yd device token provider on HarmonyOS yet: mirror the Android
    // empty-snapshot fallback ("unknown-<random>" device part, empty token).
    const randomPart = Math.floor(Math.random() * 1000000);
    session.chainId = `v1_unknown-${randomPart}_web_login_${Date.now()}`;
    session.qrContent = `${Constants.NETEASE_BASE}/st/platform/scanlogin`
      + `?codekey=${encodeURIComponent(session.key)}`
      + `&chainId=${encodeURIComponent(session.chainId)}`
      + `&hdw_device=web&hdw_appid=web&hitExp=1`;
    Logger.info(`netease qr session created key=${session.key.substring(0, 4)}...${session.key.substring(session.key.length - 4)}`);
    return session;
  }

  static async checkLogin(session: NeteaseQrSession): Promise<NeteaseQrCheckResult> {
    const result = await NeteaseQrLoginClient.postCheck(session);
    const parsed = parseQrJson(result.text);
    const out = new NeteaseQrCheckResult();
    out.code = parsed.code;
    out.message = parsed.message;
    if (parsed.code === NETEASE_QR_CONFIRMED) {
      const refreshToken = NeteaseQrLoginClient.readRefreshToken(result.headerText);
      Logger.info(`netease qr confirmed: headers=${headerNameList(result.headerText)} jarKeys=${cookieKeyList()} refreshToken=${refreshToken.length > 0 ? 'present' : 'absent'}`);
      if (!NeteaseQrLoginClient.jarHasLoginCookie()) {
        // MUSIC_U arrives on the 803 response only via Set-Cookie; when the
        // stack dropped it (header shape or cookies field gap) polling the
        // same key again still answers 803 and re-delivers the cookies.
        Logger.warn('netease qr confirmed without MUSIC_U, re-polling once for cookie re-delivery');
        try {
          const retry = await NeteaseQrLoginClient.postCheck(session);
          Logger.info(`netease qr re-poll: code=${parseQrJson(retry.text).code} jarKeys=${cookieKeyList()}`);
        } catch (error) {
          const e = error as Error;
          Logger.warn(`netease qr re-poll failed: ${e.message}`);
        }
      }
      out.cookies = await NeteaseQrLoginClient.verifyConfirmedLogin(refreshToken);
      if (out.cookies.size === 0) {
        out.cookies = jarCookies();
      }
    }
    return out;
  }

  private static async postCheck(session: NeteaseQrSession): Promise<HttpFormResult> {
    const payload: Record<string, Object> = {};
    payload['type'] = 1;
    payload['noCheckToken'] = true;
    payload['key'] = session.key;
    payload['ydDeviceToken'] = '';
    const params = await NeteaseCrypto.weapiParams(payload);
    const extraHeaders: Record<string, string> = NeteaseQrLoginClient.headers();
    extraHeaders['x-loginmethod'] = 'QrCode';
    extraHeaders['x-login-chain-id'] = session.chainId;
    return HttpClient.postFormDetailed(
      `${Constants.NETEASE_BASE}${QR_CHECK_PATH}?csrf_token=${csrfFromJar()}`,
      params,
      15000,
      extraHeaders,
      true
    );
  }

  private static jarHasLoginCookie(): boolean {
    const musicU = jarCookies().get('MUSIC_U');
    return musicU !== undefined && musicU.length > 0;
  }

  static currentCookies(): Map<string, string> {
    return jarCookies();
  }

  private static readRefreshToken(headerText: string): string {
    const match = /x-refresh-token:\s*([^\r\n;]+)/i.exec(headerText);
    return match !== null ? match[1].trim() : '';
  }

  private static async verifyAccount(): Promise<Map<string, string>> {
    const csrf = csrfFromJar();
    const payload: Record<string, Object> = {};
    if (csrf.length > 0) {
      payload['csrf_token'] = csrf;
    }
    const params = await NeteaseCrypto.weapiParams(payload);
    try {
      const result = await HttpClient.postFormDetailed(
        `${Constants.NETEASE_BASE}${ACCOUNT_PATH}?csrf_token=${encodeURIComponent(csrf)}`,
        params,
        15000,
        NeteaseQrLoginClient.headers(),
        true
      );
      const parsed = parseQrJson(result.text);
      if (parsed.code === 200 && parsed.hasAccount) {
        return jarCookies();
      }
    } catch (error) {
      const e = error as Error;
      Logger.warn(`netease qr verify account failed: ${e.message}`);
    }
    return new Map<string, string>();
  }

  private static async verifyConfirmedLogin(refreshToken: string): Promise<Map<string, string>> {
    const direct = await NeteaseQrLoginClient.verifyAccount();
    if (direct.size > 0) {
      return direct;
    }
    const hasMusicU = jarCookies().get('MUSIC_U');
    if (refreshToken.length === 0 || (hasMusicU !== undefined && hasMusicU.length > 0)) {
      return new Map<string, string>();
    }
    // Fallback: seed MUSIC_U from the x-refresh-token header and retry once.
    HttpClient.seedCookies(QR_ORIGIN, `MUSIC_U=${refreshToken}`);
    const refreshed = await NeteaseQrLoginClient.verifyAccount();
    if (refreshed.size > 0) {
      return refreshed;
    }
    HttpClient.removeCookie(QR_ORIGIN, 'MUSIC_U');
    return new Map<string, string>();
  }
}
