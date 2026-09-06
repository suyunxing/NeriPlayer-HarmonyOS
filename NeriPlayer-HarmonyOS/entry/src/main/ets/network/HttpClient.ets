import { connection, http } from '@kit.NetworkKit';
import { Logger } from '../app/Logger';
import { SettingsRepository } from '../data/SettingsRepository';
import { HttpHeaderParser } from './HttpHeaderParser';

export class HttpFormResult {
  text: string = '';
  responseCode: number = 0;
  headerText: string = '';
}

/**
 * Shared HTTP client (equivalent of the shared OkHttpClient in the Android app).
 */
export class HttpClient {
  static readonly DEFAULT_UA: string =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36';

  // Minimal cookie jar (per host), enough for the NetEase weapi session flow.
  private static cookies: Record<string, string> = {};
  private static appliedAppProxyKey: string | null = null;

  /**
   * Synchronizes the persisted proxy with the process-wide NetworkKit proxy.
   * Media components such as AVPlayer do not see per-request `usingProxy`, but
   * can use the application-level default proxy configured by NetworkKit.
   */
  static applyConfiguredProxy(): void {
    const host = SettingsRepository.getString(SettingsRepository.KEY_PROXY_HOST, '').trim();
    const port = SettingsRepository.getNumber(SettingsRepository.KEY_PROXY_PORT, 0);
    const valid = host.length > 0 && port > 0 && port <= 65535;
    const key = valid ? `${host}:${port}` : '';
    if (HttpClient.appliedAppProxyKey === key) {
      return;
    }
    try {
      const proxy: connection.HttpProxy = {
        host: valid ? host : '',
        port: valid ? port : 0,
        exclusionList: []
      };
      connection.setAppHttpProxy(proxy);
      HttpClient.appliedAppProxyKey = key;
    } catch (error) {
      const e = error as Error;
      Logger.warn(`HttpClient.applyConfiguredProxy failed: ${e.message}`);
    }
  }

  /**
   * Explicit proxy from np.proxy_host/np.proxy_port (set on the debug page).
   * undefined = direct connection, identical to not passing usingProxy at all.
   */
  static usingProxyValue(): boolean | http.HttpProxy | undefined {
    const host = SettingsRepository.getString(SettingsRepository.KEY_PROXY_HOST, '').trim();
    const port = SettingsRepository.getNumber(SettingsRepository.KEY_PROXY_PORT, 0);
    HttpClient.applyConfiguredProxy();
    if (host.length === 0 || port <= 0 || port > 65535) {
      return undefined;
    }
    const proxy: http.HttpProxy = { host: host, port: port, exclusionList: [] };
    return proxy;
  }

  static async getText(
    url: string,
    headers: Record<string, string> = {},
    timeoutMs: number = 15000,
    useCookies: boolean = false
  ): Promise<string> {
    const request = http.createHttp();
    try {
      const header: Record<string, string> = { 'User-Agent': HttpClient.DEFAULT_UA };
      for (const key of Object.keys(headers)) {
        header[key] = headers[key];
      }
      if (useCookies) {
        HttpClient.applyCookieHeader(url, header);
      }
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        header: header,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs,
        expectDataType: http.HttpDataType.STRING,
        usingProxy: HttpClient.usingProxyValue()
      });
      const code = response.responseCode;
      const text = response.result as string;
      if (useCookies) {
        HttpClient.captureCookies(url, HttpHeaderParser.toHeaderText(response.header));
      }
      if (code < 200 || code >= 300) {
        throw new Error(`HTTP ${code} for GET ${url}`);
      }
      return text;
    } catch (error) {
      const e = error as Error;
      Logger.warn(`HttpClient.getText failed: ${e.message}`);
      throw e;
    } finally {
      request.destroy();
    }
  }

  static async postForm(
    url: string,
    form: Record<string, string>,
    timeoutMs: number = 15000,
    extraHeaders: Record<string, string> = {},
    useCookies: boolean = false
  ): Promise<string> {
    const request = http.createHttp();
    try {
      const header: Record<string, string> = {
        'User-Agent': HttpClient.DEFAULT_UA,
        'Content-Type': 'application/x-www-form-urlencoded'
      };
      for (const key of Object.keys(extraHeaders)) {
        header[key] = extraHeaders[key];
      }
      if (useCookies) {
        HttpClient.applyCookieHeader(url, header);
      }
      const response = await request.request(url, {
        method: http.RequestMethod.POST,
        header: header,
        extraData: HttpClient.encodeForm(form),
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs,
        expectDataType: http.HttpDataType.STRING,
        usingProxy: HttpClient.usingProxyValue()
      });
      const code = response.responseCode;
      const text = response.result as string;
      if (useCookies) {
        HttpClient.captureCookies(url, HttpHeaderParser.toHeaderText(response.header));
      }
      if (code < 200 || code >= 300) {
        throw new Error(`HTTP ${code} for POST ${url}`);
      }
      return text;
    } catch (error) {
      const e = error as Error;
      Logger.warn(`HttpClient.postForm failed: ${e.message}`);
      throw e;
    } finally {
      request.destroy();
    }
  }

  static async postJson(
    url: string,
    jsonBody: string,
    timeoutMs: number = 15000,
    extraHeaders: Record<string, string> = {}
  ): Promise<string> {
    const request = http.createHttp();
    try {
      const header: Record<string, string> = {
        'User-Agent': HttpClient.DEFAULT_UA,
        'Content-Type': 'application/json'
      };
      for (const key of Object.keys(extraHeaders)) {
        header[key] = extraHeaders[key];
      }
      const response = await request.request(url, {
        method: http.RequestMethod.POST,
        header: header,
        extraData: jsonBody,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs,
        expectDataType: http.HttpDataType.STRING,
        usingProxy: HttpClient.usingProxyValue()
      });
      const code = response.responseCode;
      const text = response.result as string;
      if (code < 200 || code >= 300) {
        throw new Error(`HTTP ${code} for POST ${url}`);
      }
      return text;
    } catch (error) {
      const e = error as Error;
      Logger.warn(`HttpClient.postJson failed: ${e.message}`);
      throw e;
    } finally {
      request.destroy();
    }
  }

  /**
   * POST form returning body text AND the raw response header text (callers
   * need specific headers such as NetEase x-refresh-token during QR login).
   */
  static async postFormDetailed(
    url: string,
    form: Record<string, string>,
    timeoutMs: number = 15000,
    extraHeaders: Record<string, string> = {},
    useCookies: boolean = false
  ): Promise<HttpFormResult> {
    const request = http.createHttp();
    try {
      const header: Record<string, string> = {
        'User-Agent': HttpClient.DEFAULT_UA,
        'Content-Type': 'application/x-www-form-urlencoded'
      };
      for (const key of Object.keys(extraHeaders)) {
        header[key] = extraHeaders[key];
      }
      if (useCookies) {
        HttpClient.applyCookieHeader(url, header);
      }
      const response = await request.request(url, {
        method: http.RequestMethod.POST,
        header: header,
        extraData: HttpClient.encodeForm(form),
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs,
        expectDataType: http.HttpDataType.STRING,
        usingProxy: HttpClient.usingProxyValue()
      });
      const code = response.responseCode;
      const text = response.result as string;
      // HarmonyOS returns response.header as an Object (set-cookie is an
      // array); normalize to "Key: value" lines so header consumers (cookie
      // capture, NetEase x-refresh-token lookup) can parse it uniformly.
      const headerText = HttpHeaderParser.toHeaderText(response.header);
      if (useCookies) {
        HttpClient.captureCookies(url, headerText);
      }
      if (code < 200 || code >= 300) {
        throw new Error(`HTTP ${code} for POST ${url}`);
      }
      const result = new HttpFormResult();
      result.text = text;
      result.responseCode = code;
      result.headerText = headerText;
      return result;
    } catch (error) {
      const e = error as Error;
      Logger.warn(`HttpClient.postFormDetailed failed: ${e.message}`);
      throw e;
    } finally {
      request.destroy();
    }
  }

  private static encodeForm(form: Record<string, string>): string {
    const parts: string[] = [];
    for (const key of Object.keys(form)) {
      parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(form[key])}`);
    }
    return parts.join('&');
  }

  static getCookies(url: string): string {
    const host = HttpClient.hostOf(url);
    return HttpClient.cookies[host] ?? '';
  }

  /** Cookie jar of this URL's host as a name->value map. */
  static getCookiesMap(url: string): Map<string, string> {
    const out = new Map<string, string>();
    const header = HttpClient.getCookies(url);
    if (header.length === 0) {
      return out;
    }
    for (const pair of header.split(';')) {
      const trimmed = pair.trim();
      const eq = trimmed.indexOf('=');
      if (eq > 0) {
        out.set(trimmed.substring(0, eq), trimmed.substring(eq + 1));
      }
    }
    return out;
  }

  /** Removes a single cookie by name from the jar entry of this URL's host. */
  static removeCookie(url: string, name: string): void {
    const host = HttpClient.hostOf(url);
    const existing = HttpClient.cookies[host] ?? '';
    if (existing.length === 0) {
      return;
    }
    const merged: Record<string, string> = {};
    for (const pair of existing.split(';')) {
      const trimmed = pair.trim();
      const eq = trimmed.indexOf('=');
      if (eq > 0 && trimmed.substring(0, eq) !== name) {
        merged[trimmed.substring(0, eq)] = trimmed.substring(eq + 1);
      }
    }
    const parts: string[] = [];
    for (const key of Object.keys(merged)) {
      parts.push(`${key}=${merged[key]}`);
    }
    HttpClient.cookies[host] = parts.join('; ');
  }

  /** Clears the whole jar entry for this URL's host (logout). */
  static clearCookies(url: string): void {
    HttpClient.cookies[HttpClient.hostOf(url)] = '';
  }

  static seedCookies(url: string, cookieHeader: string): void {
    const host = HttpClient.hostOf(url);
    const existing = HttpClient.cookies[host] ?? '';
    const merged: Record<string, string> = {};
    if (existing.length > 0) {
      for (const pair of existing.split(';')) {
        const trimmed = pair.trim();
        const eq = trimmed.indexOf('=');
        if (eq > 0) {
          merged[trimmed.substring(0, eq)] = trimmed.substring(eq + 1);
        }
      }
    }
    if (cookieHeader.length > 0) {
      for (const pair of cookieHeader.split(';')) {
        const trimmed = pair.trim();
        const eq = trimmed.indexOf('=');
        if (eq > 0) {
          merged[trimmed.substring(0, eq)] = trimmed.substring(eq + 1);
        }
      }
    }
    const parts: string[] = [];
    for (const key of Object.keys(merged)) {
      parts.push(`${key}=${merged[key]}`);
    }
    HttpClient.cookies[host] = parts.join('; ');
  }

  private static applyCookieHeader(url: string, header: Record<string, string>): void {
    const host = HttpClient.hostOf(url);
    const cookie = HttpClient.cookies[host] ?? '';
    if (cookie.length > 0 && header['Cookie'] === undefined) {
      header['Cookie'] = cookie;
    }
  }

  private static captureCookies(url: string, responseHeader: string): void {
    const host = HttpClient.hostOf(url);
    const existing = HttpClient.cookies[host] ?? '';
    const merged: Record<string, string> = {};
    if (existing.length > 0) {
      for (const pair of existing.split(';')) {
        const trimmed = pair.trim();
        const eq = trimmed.indexOf('=');
        if (eq > 0) {
          merged[trimmed.substring(0, eq)] = trimmed.substring(eq + 1);
        }
      }
    }
    HttpHeaderParser.extractCookiePairs(responseHeader)
      .forEach((value: string, key: string) => {
        merged[key] = value;
      });
    const parts: string[] = [];
    for (const key of Object.keys(merged)) {
      parts.push(`${key}=${merged[key]}`);
    }
    HttpClient.cookies[host] = parts.join('; ');
  }

  private static hostOf(url: string): string {
    const start = url.indexOf('://');
    const rest = start >= 0 ? url.substring(start + 3) : url;
    const slash = rest.indexOf('/');
    const hostPort = slash >= 0 ? rest.substring(0, slash) : rest;
    const colon = hostPort.lastIndexOf(':');
    if (colon > 0 && hostPort.indexOf(']') < 0 && hostPort.substring(colon + 1).match(/^\d+$/) !== null) {
      return hostPort.substring(0, colon);
    }
    return hostPort;
  }
}
