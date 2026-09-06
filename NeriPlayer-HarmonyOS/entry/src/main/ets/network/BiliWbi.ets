import { utf8Encode } from '../util/QrEncoder';

/**
 * Bilibili WBI request signing, ported from Android BiliClient.kt
 * (MIXIN_INDEX / ensureValidMixin / signWbiUrl) and the public
 * bilibili-API-collect wbi.md algorithm (backup mirrors, 2026-01 archive).
 *
 * Pure logic: the MD5 here is a self-contained implementation (RFC 1321) so
 * fixtures are byte-verified in the local hypium environment without device
 * crypto APIs.
 */

/** Wbi mixin index table (64 entries, MIXIN_KEY_ENC_TAB). */
export const WBI_MIXIN_INDEX: number[] = [
  46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
  27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
  37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4,
  22, 25, 54, 21, 56, 62, 6, 63, 57, 20, 34, 52, 59, 11, 36, 44
];

const MD5_S: number[] = [
  7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
  5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
  4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
  6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
];

const MD5_K: number[] = (() => {
  const table: number[] = [];
  for (let i = 0; i < 64; i++) {
    table[i] = Math.floor(Math.abs(Math.sin(i + 1)) * 4294967296);
  }
  return table;
})();

function byteToHex(value: number): string {
  return (value < 16 ? '0' : '') + value.toString(16);
}

/** MD5 over the UTF-8 bytes of the input, lowercase hex (RFC 1321). */
export function md5Hex(input: string): string {
  const msg: number[] = utf8Encode(input);
  const bitLen = msg.length * 8;
  msg.push(0x80);
  while (msg.length % 64 !== 56) {
    msg.push(0);
  }
  // 64-bit little-endian bit length.
  const hi = Math.floor(bitLen / 4294967296);
  msg.push(bitLen & 0xFF, (bitLen >>> 8) & 0xFF, (bitLen >>> 16) & 0xFF, (bitLen >>> 24) & 0xFF);
  msg.push(hi & 0xFF, (hi >>> 8) & 0xFF, (hi >>> 16) & 0xFF, (hi >>> 24) & 0xFF);

  let a0 = 0x67452301;
  let b0 = 0xefcdab89;
  let c0 = 0x98badcfe;
  let d0 = 0x10325476;
  for (let chunk = 0; chunk < msg.length; chunk += 64) {
    const m: number[] = [];
    for (let i = 0; i < 16; i++) {
      const o = chunk + i * 4;
      m[i] = (msg[o]) | (msg[o + 1] << 8) | (msg[o + 2] << 16) | (msg[o + 3] << 24);
    }
    let a = a0;
    let b = b0;
    let c = c0;
    let d = d0;
    for (let i = 0; i < 64; i++) {
      let f: number;
      let g: number;
      if (i < 16) {
        f = (b & c) | (~b & d);
        g = i;
      } else if (i < 32) {
        f = (d & b) | (~d & c);
        g = (5 * i + 1) % 16;
      } else if (i < 48) {
        f = b ^ c ^ d;
        g = (3 * i + 5) % 16;
      } else {
        f = c ^ (b | ~d);
        g = (7 * i) % 16;
      }
      f = (f + a + MD5_K[i] + m[g]) | 0;
      a = d;
      d = c;
      c = b;
      b = (b + ((f << MD5_S[i]) | (f >>> (32 - MD5_S[i])))) | 0;
    }
    a0 = (a0 + a) | 0;
    b0 = (b0 + b) | 0;
    c0 = (c0 + c) | 0;
    d0 = (d0 + d) | 0;
  }
  const words = [a0, b0, c0, d0];
  let out = '';
  for (const word of words) {
    for (let i = 0; i < 4; i++) {
      out += byteToHex((word >>> (i * 8)) & 0xFF);
    }
  }
  return out;
}

/** Extracts the wbi key from a //host/path/<key>.png URL (filename without extension). */
export function wbiKeyFromUrl(url: string): string {
  const slash = url.lastIndexOf('/');
  const file = slash >= 0 ? url.substring(slash + 1) : url;
  const dot = file.indexOf('.');
  return dot >= 0 ? file.substring(0, dot) : file;
}

/** Derives the 32-char mixin key from the nav img/sub keys (ensureValidMixin). */
export function mixinKeyFrom(imgKey: string, subKey: string): string {
  const raw = imgKey + subKey;
  let mixed = '';
  for (const idx of WBI_MIXIN_INDEX) {
    if (idx < raw.length) {
      mixed += raw[idx];
    }
  }
  return mixed.length >= 32 ? mixed.substring(0, 32) : mixed;
}

/** Strips "!'()*" from a parameter value before signing (filterValue). */
export function wbiFilterValue(value: string): string {
  return value.replace(/[!'()*]/g, '');
}

/**
 * Builds the signed query string: params sorted by key (URL-encoded), plus
 * wts, plus w_rid = md5(query + mixinKey). The final string can be appended
 * to a base URL directly (signWbiUrl).
 */
export function buildWbiSignedQuery(
  params: Map<string, string>,
  mixinKey: string,
  wtsSeconds: number
): string {
  // wts joins the parameter map before sorting (Android: params["wts"]=wts;
  // toSortedMap()) so the md5 input ordering matches the official algorithm.
  const all = new Map<string, string>();
  params.forEach((value: string, key: string) => {
    all.set(key, value);
  });
  all.set('wts', `${wtsSeconds}`);
  const sortedKeys: string[] = [];
  all.forEach((_value: string, key: string) => {
    sortedKeys.push(key);
  });
  sortedKeys.sort();
  const encoded: string[] = [];
  for (const key of sortedKeys) {
    const v = all.get(key) ?? '';
    encoded.push(`${encodeURIComponent(key)}=${encodeURIComponent(wbiFilterValue(v))}`);
  }
  const query = encoded.join('&');
  const wRid = md5Hex(query + mixinKey);
  return `${query}&w_rid=${wRid}`;
}
