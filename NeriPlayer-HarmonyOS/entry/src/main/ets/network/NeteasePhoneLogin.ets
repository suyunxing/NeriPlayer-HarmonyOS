// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

import { util } from '@kit.ArkTS';
import { Logger } from '../app/Logger';
import { Constants } from '../app/Constants';
import { HttpClient } from './HttpClient';
import { NeteaseCrypto } from './NeteaseCrypto';
import { md5Hex } from './BiliWbi';

/**
 * NetEase phone login (backlog §3.3, Android NeteaseClient loginByPhone /
 * sendCaptcha / verifyCaptcha / loginByCaptcha): password login carries the
 * md5 hex of the password; captcha login posts the SMS code straight to the
 * login endpoint, like the Android upstream which has no verify round-trip
 * before login (the login endpoint validates the captcha itself; the verify
 * pre-check this port once performed aborted the whole flow whenever that
 * endpoint answered the risk-control message "网络环境异常" even though the
 * login request itself would have passed).
 *
 * The login endpoints sit behind NetEase risk control (code -460): a bare
 * request with no web session — no __csrf, no NMTID, none of the fingerprint
 * cookies the web client always carries — is rejected with that message even
 * when the SMS was delivered, because the captcha endpoint is lenient while
 * the login endpoint is strict. The Android upstream gets the same context
 * implicitly through its OkHttp CookieJar (persisted os=pc/appver seed +
 * automatic jar injection on every request); this port has a per-host jar
 * that callers opt into, so it builds the web session explicitly
 * (ensureWebSession) before any login request.
 *
 * 2026-10 second round: the fingerprint-only session regressed to -460.
 * Login-family endpoints now also demand the anonymous device credential
 * MUSIC_A (register_anonimous), which the official clients obtain before any
 * login action; QueMusic fixed the identical regression this way on device
 * (2026-10-01) and api-enhanced injects MUSIC_A into every cookie-less
 * weapi request. ensureWebSession therefore registers an anonymous device
 * once per process (ensureAnonymousDevice) so the captcha/login requests
 * carry a trusted-device cookie; failure degrades to the previous behaviour
 * instead of aborting the flow.
 */

const ORIGIN: string = `${Constants.NETEASE_BASE}/`;
// Current web-client login path (/w/), matching the Android upstream eapi
// path and the community NeteaseCloudMusicApi weapi implementation; the
// legacy /weapi/login/cellphone path this port started from predates it.
const LOGIN_PATH: string = '/weapi/w/login/cellphone';
const CAPTCHA_SENT_PATH: string = '/weapi/sms/captcha/sent';
const CAPTCHA_VERIFY_PATH: string = '/weapi/sms/captcha/verify';
const REGISTER_ANON_PATH: string = '/weapi/register/anonimous';
const DESKTOP_UA: string =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36 Edg/149.0.0.0';

export class NeteaseLoginResult {
  code: number = -1;
  message: string = '';
  // register_anonimous returns the MUSIC_A token in the body as well as in
  // Set-Cookie; login endpoints never set it.
  token: string = '';
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

/** Random hex string for session fingerprint ids (not security-sensitive). */
function randomHex(length: number): string {
  const alphabet = '0123456789abcdef';
  let result = '';
  for (let i = 0; i < length; i++) {
    result += alphabet.charAt(Math.floor(Math.random() * alphabet.length));
  }
  return result;
}

function randomAlpha(length: number): string {
  const alphabet = 'abcdefghijklmnopqrstuvwxyz';
  let result = '';
  for (let i = 0; i < length; i++) {
    result += alphabet.charAt(Math.floor(Math.random() * alphabet.length));
  }
  return result;
}

function randomUpperHex(length: number): string {
  const alphabet = '0123456789ABCDEF';
  let result = '';
  for (let i = 0; i < length; i++) {
    result += alphabet.charAt(Math.floor(Math.random() * alphabet.length));
  }
  return result;
}

/**
 * Static fingerprint cookies the web client carries on every request
 * (community osMap "pc" set; appver tracks the current web client version —
 * api-enhanced production value 3.1.17.204416, replacing the 2021-era
 * 8.10.35 that no longer matches a 2026 browser UA). Deterministic so unit
 * tests can pin the exact header.
 */
export function buildWebSessionSeed(nuid: string, wnmcid: string, tsMs: number): string {
  return [
    'os=pc',
    'appver=3.1.17.204416',
    'osver=Microsoft-Windows-10-Professional-build-19045-64bit',
    'channel=netease',
    '__remember_me=true',
    'ntes_kaola_ad=1',
    'WEVNSM=1.0.0',
    `WNMCID=${wnmcid}.${tsMs}.01.0`,
    `_ntes_nuid=${nuid}`,
    `_ntes_nnid=${nuid},${tsMs}`
  ].join('; ');
}

/**
 * NMTID fallback when the homepage never issues one: 32 random hex chars,
 * the shape the community client generates for its own NMTID. Seeded only
 * after the warmup GET failed to deliver one — a pre-seeded NMTID keeps the
 * server from ever issuing its own (api-enhanced PR #243).
 */
export function fallbackNmtid(): string {
  return randomHex(32);
}

/** NetEase client device-id magic string (public knowledge). */
const ID_XOR_KEY: string = '3go8&$8*3*3h0k(2)2';

/**
 * cloudmusic_dll_encode_id: the device digest inside the anonymous-register
 * username — XOR the device id with the magic string, MD5 over the UTF-8
 * bytes, base64 of the raw digest. Known-answer vectors are pinned in
 * NeteasePhoneLoginSeed.test.ets (computed with Node crypto).
 */
export function cloudmusicDllEncodeId(deviceId: string): string {
  let xored = '';
  for (let i = 0; i < deviceId.length; i++) {
    xored += String.fromCharCode(deviceId.charCodeAt(i) ^ ID_XOR_KEY.charCodeAt(i % ID_XOR_KEY.length));
  }
  return hexToBase64(md5Hex(xored));
}

/** register_anonimous username: base64("<deviceId> <dll-encoded-id>"). */
export function buildRegisterUsername(deviceId: string): string {
  const encoder = new util.TextEncoder();
  const raw = `${deviceId} ${cloudmusicDllEncodeId(deviceId)}`;
  return NeteaseCrypto.bytesToBase64(encoder.encodeInto(raw));
}

function hexToBase64(hex: string): string {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = Number.parseInt(hex.substring(i * 2, i * 2 + 2), 16);
  }
  return NeteaseCrypto.bytesToBase64(bytes);
}

// Session fingerprint ids stay stable for the whole process: the jar merge
// (seedCookies) overwrites by name, so regenerating per call would rotate the
// identity between the captcha and the login request. The anonymous device
// id follows the same rule and is registered at most once per process.
let sessionNuid: string = '';
let sessionWnmcid: string = '';
let sessionTsMs: number = 0;
let anonymousDeviceId: string = '';
let anonymousRegisterDone: boolean = false;

async function ensureWebSession(): Promise<void> {
  if (sessionNuid.length === 0) {
    sessionNuid = randomHex(32);
    sessionWnmcid = randomAlpha(6);
    sessionTsMs = Date.now();
    anonymousDeviceId = randomUpperHex(52);
  }
  HttpClient.seedCookies(ORIGIN, buildWebSessionSeed(sessionNuid, sessionWnmcid, sessionTsMs));
  if (HttpClient.getCookiesMap(ORIGIN).has('__csrf')) {
    await ensureAnonymousDevice();
    return;
  }
  // First login action of the process: visit the homepage once so the server
  // issues __csrf/NMTID exactly like a real web session before any
  // risk-controlled endpoint is called.
  try {
    await HttpClient.getText(`${Constants.NETEASE_BASE}/`, headers(), 15000, true);
  } catch (error) {
    const e = error as Error;
    Logger.warn(`netease phone login session warmup failed: ${e.message}`);
  }
  if (!HttpClient.getCookiesMap(ORIGIN).has('NMTID')) {
    HttpClient.seedCookies(ORIGIN, `NMTID=${fallbackNmtid()}`);
  }
  await ensureAnonymousDevice();
}

/**
 * Login-family endpoints reject cookie-less devices with -460 since the
 * 2026-09/10 risk-control tightening; the fix (QueMusic 2026-10-01,
 * api-enhanced, open-orpheus) is to register an anonymous device first and
 * let every later request carry the MUSIC_A credential. One attempt per
 * process — a rejected registration must not block the login flow (it
 * degrades to the fingerprint-only session) and hammering the register
 * endpoint would itself accumulate risk score.
 */
async function ensureAnonymousDevice(): Promise<void> {
  if (anonymousRegisterDone) {
    return;
  }
  anonymousRegisterDone = true;
  const jar = HttpClient.getCookiesMap(ORIGIN);
  if (jar.has('MUSIC_A') || jar.has('MUSIC_U')) {
    return;
  }
  const payload: Record<string, Object> = {};
  payload['username'] = buildRegisterUsername(anonymousDeviceId);
  const result = await postWeapi(REGISTER_ANON_PATH, payload);
  if (result.code === 200) {
    // The Set-Cookie of a 200 normally lands MUSIC_A straight in the jar
    // (postWeapi posts with cookies on); the body token covers netstacks
    // that drop that header — the same two-source extraction QueMusic does.
    if (result.token.length > 0 && !HttpClient.getCookiesMap(ORIGIN).has('MUSIC_A')) {
      HttpClient.seedCookies(ORIGIN, `MUSIC_A=${result.token}`);
    }
  } else {
    Logger.warn(`netease anonymous device register rejected: code=${result.code} ${result.message}`);
  }
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
    const token = root['token'];
    out.token = token === undefined || token === null ? '' : String(token);
  } catch (error) {
    const e = error as Error;
    Logger.warn(`netease phone login json parse failed: ${e.message}`);
  }
  return out;
}

export class NeteasePhoneLoginClient {
  /** Sends the SMS captcha (Android sendCaptcha; `cellphone`+`ctcode`). */
  static async sendCaptcha(phone: string, ctcode: number = 86): Promise<NeteaseLoginResult> {
    await ensureWebSession();
    const payload: Record<string, Object> = {};
    payload['cellphone'] = phone;
    payload['ctcode'] = `${ctcode}`;
    // Login-channel secret the current community payload carries since
    // 2026-07 (api-enhanced captcha_sent); the server accepts requests
    // without it, but parity with the maintained implementation is free.
    payload['secrete'] = 'music_middleuser_pclogin';
    return postWeapi(CAPTCHA_SENT_PATH, payload);
  }

  /** Verifies the SMS code without logging in (Android verifyCaptcha). */
  static async verifyCaptcha(phone: string, captcha: string, ctcode: number = 86): Promise<NeteaseLoginResult> {
    await ensureWebSession();
    const payload: Record<string, Object> = {};
    payload['cellphone'] = phone;
    payload['captcha'] = captcha;
    payload['ctcode'] = `${ctcode}`;
    return postWeapi(CAPTCHA_VERIFY_PATH, payload);
  }

  /** SMS-captcha login (Android loginByCaptcha: a single login POST). */
  static async loginByCaptcha(phone: string, captcha: string, ctcode: number = 86): Promise<NeteaseLoginResult> {
    await ensureWebSession();
    const payload: Record<string, Object> = {};
    payload['phone'] = phone;
    payload['countrycode'] = `${ctcode}`;
    payload['remember'] = 'true';
    payload['type'] = '1';
    // The web client posts https=true for mainland numbers as part of the
    // standard login payload (community login_cellphone implementation).
    payload['https'] = 'true';
    payload['captcha'] = captcha;
    return NeteasePhoneLoginClient.finishLogin(await postWeapi(LOGIN_PATH, payload));
  }

  /** Password login (Android loginByPhone): the password travels as md5 hex. */
  static async loginByPassword(phone: string, password: string, ctcode: number = 86): Promise<NeteaseLoginResult> {
    await ensureWebSession();
    const payload: Record<string, Object> = {};
    payload['phone'] = phone;
    payload['countrycode'] = `${ctcode}`;
    payload['remember'] = 'true';
    payload['type'] = '1';
    payload['https'] = 'true';
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
