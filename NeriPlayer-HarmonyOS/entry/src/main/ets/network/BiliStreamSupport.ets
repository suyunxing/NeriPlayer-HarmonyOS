// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Pure helpers for Bilibili media stream URLs: host recognition, CDN
 * preference and the HTTP headers CDN fetches must carry. Kept free of Kit
 * imports so the logic stays unit-testable on the host. Mirrors the Android
 * app's BiliAudioSelector scoring and ConditionalHttpDataSourceFactory
 * header injection.
 */
export class BiliStreamSupport {
  // Desktop web UA required alongside Referer by Bilibili CDN endpoints
  // (same constant the Android app sends for stream fetches).
  static readonly BILI_WEB_UA: string =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  static isBiliStreamUrl(url: string): boolean {
    const host = BiliStreamSupport.hostOfUrl(url);
    return host.indexOf('bilivideo.') >= 0 || host.endsWith('.mountaintoys.cn');
  }

  /**
   * Headers a Bilibili CDN fetch must carry: Referer + desktop UA + the
   * caller-supplied cookie header (login bundle or anonymous buvid).
   * Returns null when the url is not a Bilibili media host, so generic
   * callers pass no extra headers.
   */
  static buildStreamHeaders(url: string, cookieHeader: string): Record<string, string> | null {
    if (!BiliStreamSupport.isBiliStreamUrl(url)) {
      return null;
    }
    const headers: Record<string, string> = {
      'Referer': 'https://www.bilibili.com',
      'User-Agent': BiliStreamSupport.BILI_WEB_UA
    };
    if (cookieHeader.length > 0) {
      headers['Cookie'] = cookieHeader;
    }
    return headers;
  }

  /** Picks the highest-preference candidate as https ('' for no candidates). */
  static pickBestStreamUrl(candidates: string[]): string {
    let best = '';
    let bestScore = -1;
    for (const candidate of candidates) {
      const normalized = candidate.startsWith('http://')
        ? `https://${candidate.substring(7)}`
        : candidate;
      const score = BiliStreamSupport.scoreStreamUrl(normalized);
      if (score > bestScore) {
        best = normalized;
        bestScore = score;
      }
    }
    return best;
  }

  // Bilibili CDN host preference (Android BiliAudioSelector scoring): upos
  // mirrors first, other bilivideo hosts next, legacy mountaintoys last.
  private static scoreStreamUrl(url: string): number {
    const host = BiliStreamSupport.hostOfUrl(url);
    if (host.startsWith('upos-') && host.indexOf('bilivideo.') >= 0) {
      return 3;
    }
    if (host.indexOf('bilivideo.') >= 0) {
      return 2;
    }
    if (host.endsWith('.mountaintoys.cn')) {
      return 1;
    }
    return 0;
  }

  private static hostOfUrl(url: string): string {
    const start = url.indexOf('://');
    const rest = start >= 0 ? url.substring(start + 3) : url;
    const slash = rest.indexOf('/');
    let host = slash >= 0 ? rest.substring(0, slash) : rest;
    // Bilibili CDN urls may carry an explicit port (mountaintoys mirrors
    // use :4483); host matching must ignore it.
    const colon = host.lastIndexOf(':');
    if (colon > 0 && host.substring(colon + 1).match(/^\d+$/) !== null) {
      host = host.substring(0, colon);
    }
    return host;
  }
}
