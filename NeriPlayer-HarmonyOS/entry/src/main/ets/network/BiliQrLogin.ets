// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

import { Logger } from '../app/Logger';
import { HttpClient } from './HttpClient';

/**
 * Bilibili QR login client, ported from Android BiliQrLoginClient.kt.
 * Flow: createSession (GET /x/passport-login/web/qrcode/generate) -> render
 * QR of data.url -> poll checkLogin (GET .../poll?qrcode_key=) until the
 * business code in data.code says waiting(86101)/scanned(86090)/confirmed(0)/
 * expired(86038). Cookies accumulate passively from passport Set-Cookie
 * responses (SESSDATA/bili_jct/DedeUserID/buvid3...) and are snapshotted on
 * success — there is no separate buvid seed endpoint in this flow.
 */

export const BILI_QR_CONFIRMED: number = 0;
export const BILI_QR_EXPIRED: number = 86038;
export const BILI_QR_WAITING: number = 86101;
export const BILI_QR_SCANNED: number = 86090;

const QR_ORIGIN: string = 'https://passport.bilibili.com/';
const QR_GENERATE_URL: string = 'https://passport.bilibili.com/x/passport-login/web/qrcode/generate';
const QR_POLL_URL: string = 'https://passport.bilibili.com/x/passport-login/web/qrcode/poll';
const QR_REFERER: string = 'https://passport.bilibili.com/login';
const BILI_WEB_UA: string =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

export class BiliQrSession {
  key: string = '';
  qrContent: string = '';
}

export class BiliQrCheckResult {
  code: number = -1;
  message: string = '';
  cookies: Map<string, string> = new Map();

  get isConfirmed(): boolean {
    return this.code === BILI_QR_CONFIRMED;
  }
}

interface BiliQrEnvelope {
  rootCode: number;
  message: string;
  dataCode: number;
  dataMessage: string;
  qrcodeKey: string;
  url: string;
}

function parseQrEnvelope(text: string, rootCodeFallback: number): BiliQrEnvelope {
  const out: BiliQrEnvelope = {
    rootCode: -1,
    message: '',
    dataCode: rootCodeFallback,
    dataMessage: '',
    qrcodeKey: '',
    url: ''
  };
  try {
    const root = JSON.parse(text) as Record<string, Object>;
    const code = root['code'];
    out.rootCode = code === undefined || code === null ? -1 : Number(code);
    const message = root['message'];
    if (message === undefined || message === null) {
      const msg = root['msg'];
      out.message = msg === undefined || msg === null ? '' : String(msg);
    } else {
      out.message = String(message);
    }
    const dataRaw = root['data'];
    if (dataRaw !== undefined && dataRaw !== null) {
      const data = dataRaw as Record<string, Object>;
      const dataCode = data['code'];
      out.dataCode = dataCode === undefined || dataCode === null ? rootCodeFallback : Number(dataCode);
      const dataMessage = data['message'];
      out.dataMessage = dataMessage === undefined || dataMessage === null ? '' : String(dataMessage);
      const key = data['qrcode_key'];
      out.qrcodeKey = key === undefined || key === null ? '' : String(key).trim();
      const url = data['url'];
      out.url = url === undefined || url === null ? '' : String(url).trim();
    }
  } catch (error) {
    const e = error as Error;
    Logger.warn(`bili qr json parse failed: ${e.message}`);
  }
  return out;
}

export class BiliQrLoginClient {
  private static headers(): Record<string, string> {
    const header: Record<string, string> = {};
    header['Accept'] = 'application/json, text/plain, */*';
    header['Accept-Language'] = 'zh-CN,zh-Hans;q=0.9';
    header['Cache-Control'] = 'no-cache';
    header['Pragma'] = 'no-cache';
    header['Referer'] = QR_REFERER;
    header['User-Agent'] = BILI_WEB_UA;
    return header;
  }

  static async createSession(): Promise<BiliQrSession> {
    const text = await HttpClient.getText(QR_GENERATE_URL, BiliQrLoginClient.headers(), 15000, true);
    const parsed = parseQrEnvelope(text, -1);
    if (parsed.rootCode !== 0 || parsed.qrcodeKey.length === 0 || parsed.url.length === 0) {
      throw new Error(`Failed to create Bilibili QR session, code=${parsed.rootCode} ${parsed.message}`);
    }
    const session = new BiliQrSession();
    session.key = parsed.qrcodeKey;
    session.qrContent = parsed.url;
    Logger.info(`bili qr session created key=${session.key.substring(0, 4)}...${session.key.substring(session.key.length - 4)}`);
    return session;
  }

  static async checkLogin(session: BiliQrSession): Promise<BiliQrCheckResult> {
    const text = await HttpClient.getText(
      `${QR_POLL_URL}?qrcode_key=${encodeURIComponent(session.key)}`,
      BiliQrLoginClient.headers(),
      15000,
      true
    );
    // Top-level code != 0 means a transport/system error (Android throws).
    const parsed = parseQrEnvelope(text, 0);
    if (parsed.rootCode !== 0) {
      throw new Error(`Bilibili QR poll failed, code=${parsed.rootCode} ${parsed.message}`);
    }
    const out = new BiliQrCheckResult();
    out.code = parsed.dataCode;
    out.message = parsed.dataMessage.length > 0 ? parsed.dataMessage : parsed.message;
    if (out.isConfirmed) {
      out.cookies = BiliQrLoginClient.currentCookies();
    }
    return out;
  }

  static currentCookies(): Map<string, string> {
    return HttpClient.getCookiesMap(QR_ORIGIN);
  }
}
