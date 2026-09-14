// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Pure HTTP response-header utilities (no platform imports) so the NetEase
 * weapi cookie flow is unit-testable in the local hypium environment.
 *
 * HarmonyOS @ohos.net.http exposes HttpResponse.header as an Object whose
 * values are strings, except set-cookie which is an array (one entry per
 * Set-Cookie line; some stacks comma-join them instead). Some stacks return
 * the raw header text. All shapes are normalized here so callers can keep
 * working with plain "Key: value" lines.
 */

const RESERVED_COOKIE_ATTR_NAMES: Set<string> = new Set<string>([
  'expires', 'path', 'domain', 'max-age', 'samesite', 'secure', 'httponly',
  'partitioned', 'priority', 'comment', 'version'
]);

export class HttpHeaderParser {
  /**
   * Normalizes any response-header shape (raw text string, or a Record with
   * string / string[] values) into canonical "Key: value" lines joined by
   * CRLF. Array values (e.g. set-cookie) expand into one line per entry.
   */
  static toHeaderText(headerValue: Object | string): string {
    if (typeof headerValue === 'string') {
      return headerValue as string;
    }
    if (headerValue === null || headerValue === undefined) {
      return '';
    }
    const record = headerValue as Record<string, Object>;
    const lines: string[] = [];
    for (const key of Object.keys(record)) {
      const value = record[key];
      if (value === null || value === undefined) {
        continue;
      }
      if (Array.isArray(value)) {
        const items = value as Object[];
        for (const item of items) {
          if (item !== null && item !== undefined) {
            lines.push(`${key}: ${String(item)}`);
          }
        }
      } else {
        lines.push(`${key}: ${String(value)}`);
      }
    }
    return lines.join('\r\n');
  }

  /**
   * Extracts cookie name=value pairs from the set-cookie lines of a header
   * text produced by toHeaderText. Comma-joined values are split; attribute
   * fragments (Expires dates, Path/Domain etc.) are dropped, keeping only the
   * name=value part of each cookie.
   */
  static extractCookiePairs(headerText: string): Map<string, string> {
    const out = new Map<string, string>();
    const lines = headerText.split('\n');
    for (const line of lines) {
      const colon = line.indexOf(':');
      if (colon <= 0) {
        continue;
      }
      const headerName = line.substring(0, colon).trim().toLowerCase();
      if (headerName !== 'set-cookie') {
        continue;
      }
      HttpHeaderParser.mergeLooseFragments(line.substring(colon + 1), out);
    }
    return out;
  }

  /**
   * Parses the dedicated HttpResponse.cookies field. The stacks have shipped
   * it as "; "-joined name=value pairs, as comma-joined full Set-Cookie lines
   * with attributes, and sometimes with attributes mixed in; split on both
   * separators and keep only the name=value head of each fragment.
   */
  static parseLooseCookiePairs(text: string): Map<string, string> {
    const out = new Map<string, string>();
    HttpHeaderParser.mergeLooseFragments(text, out);
    return out;
  }

  private static mergeLooseFragments(raw: string, out: Map<string, string>): void {
    for (const chunk of raw.split(/[,;]/)) {
      const head = chunk.split(';')[0].trim();
      const eq = head.indexOf('=');
      if (eq <= 0) {
        continue;
      }
      const name = head.substring(0, eq).trim();
      const value = head.substring(eq + 1).trim();
      if (name.length === 0 || value.length === 0) {
        continue;
      }
      if (RESERVED_COOKIE_ATTR_NAMES.has(name.toLowerCase())) {
        continue;
      }
      out.set(name, value);
    }
  }
}
