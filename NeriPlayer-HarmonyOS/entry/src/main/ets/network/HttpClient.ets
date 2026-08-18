import { http } from '@kit.NetworkKit';
import { Logger } from '../app/Logger';

/**
 * Binary HTTP response used by the download pipeline. Header parsing is kept
 * here so the range/resume logic stays in one place.
 */
export class HttpBinaryResponse {
  statusCode: number;
  body: ArrayBuffer;
  headers: string;

  constructor(statusCode: number = 0, body: ArrayBuffer = new ArrayBuffer(0), headers: string = '') {
    this.statusCode = statusCode;
    this.body = body;
    this.headers = headers;
  }

  header(name: string): string {
    if (name.length === 0 || this.headers.length === 0) {
      return '';
    }
    const pattern = new RegExp(`(?:^|\\r?\\n)${name}:\\s*([^\\r\\n]*)`, 'i');
    const match = pattern.exec(this.headers);
    return match === null ? '' : match[1].trim();
  }

  contentLength(): number {
    const value = this.header('content-length');
    if (value.length === 0) {
      return -1;
    }
    const length = Number(value);
    return Number.isNaN(length) || length < 0 ? -1 : length;
  }

  acceptRanges(): boolean {
    return this.header('accept-ranges').toLowerCase().indexOf('bytes') >= 0;
  }

  contentRangeStart(): number {
    const match = /bytes\s+(\d+)-(\d+)\/(\d+|\*)/i.exec(this.header('content-range'));
    if (match === null) {
      return -1;
    }
    const start = Number(match[1]);
    return Number.isNaN(start) ? -1 : start;
  }

  contentRangeEnd(): number {
    const match = /bytes\s+(\d+)-(\d+)\/(\d+|\*)/i.exec(this.header('content-range'));
    if (match === null) {
      return -1;
    }
    const end = Number(match[2]);
    return Number.isNaN(end) ? -1 : end;
  }

  contentRangeTotal(): number {
    const match = /bytes\s+(\d+)-(\d+)\/(\d+|\*)/i.exec(this.header('content-range'));
    if (match === null || match[3] === '*') {
      return -1;
    }
    const total = Number(match[3]);
    return Number.isNaN(total) || total < 0 ? -1 : total;
  }
}

/**
 * Shared HTTP client (equivalent of the shared OkHttpClient in the Android app).
 */
export class HttpClient {
  static readonly DEFAULT_UA: string =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36';

  // Minimal cookie jar (per host), enough for the NetEase weapi session flow.
  private static cookies: Record<string, string> = {};

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
        expectDataType: http.HttpDataType.STRING
      });
      const code = response.responseCode;
      const text = response.result as string;
      if (useCookies) {
        HttpClient.captureCookies(url, response.header as string);
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

  /**
   * Raw byte GET. Used by DownloadManager with a Range header; unlike getText
   * this returns the status/headers even for 4xx so 416 can finish a download.
   */
  static async getBytes(
    url: string,
    headers: Record<string, string> = {},
    timeoutMs: number = 30000,
    useCookies: boolean = false
  ): Promise<HttpBinaryResponse> {
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
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      });
      const headersText = response.header as string;
      if (useCookies) {
        HttpClient.captureCookies(url, headersText);
      }
      let body = new ArrayBuffer(0);
      if (response.result !== undefined && response.result !== null) {
        body = response.result as ArrayBuffer;
      }
      return new HttpBinaryResponse(response.responseCode, body, headersText);
    } catch (error) {
      const e = error as Error;
      Logger.warn(`HttpClient.getBytes failed: ${e.message}`);
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
        expectDataType: http.HttpDataType.STRING
      });
      const code = response.responseCode;
      const text = response.result as string;
      if (useCookies) {
        HttpClient.captureCookies(url, response.header as string);
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

  static async postJson(url: string, jsonBody: string, timeoutMs: number = 15000): Promise<string> {
    const request = http.createHttp();
    try {
      const header: Record<string, string> = {
        'User-Agent': HttpClient.DEFAULT_UA,
        'Content-Type': 'application/json'
      };
      const response = await request.request(url, {
        method: http.RequestMethod.POST,
        header: header,
        extraData: jsonBody,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs,
        expectDataType: http.HttpDataType.STRING
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
    const setCookiePattern = /set-cookie:\s*([^;\r\n]+)/gi;
    let match = setCookiePattern.exec(responseHeader);
    while (match !== null) {
      const pair = match[1].trim();
      const eq = pair.indexOf('=');
      if (eq > 0) {
        merged[pair.substring(0, eq)] = pair.substring(eq + 1);
      }
      match = setCookiePattern.exec(responseHeader);
    }
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
