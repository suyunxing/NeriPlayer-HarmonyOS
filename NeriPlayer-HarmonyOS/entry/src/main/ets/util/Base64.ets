/**
 * Minimal RFC 4648 base64 encoder (standard alphabet + '=' padding).
 *
 * Only encode is implemented for now: the GitHub Git Data API blob endpoint
 * expects {"content": <base64>, "encoding": "base64"} payloads, while every
 * decode path in the sync pipeline already has its own strict decoder
 * (decodeLegacyBase64Text in SyncDataJsonCodec). Pure ArkTS so the local
 * hypium environment can execute it.
 */

const ALPHABET: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

export function encodeBase64(bytes: Uint8Array): string {
  let out = '';
  const length = bytes.length;
  let i = 0;
  while (i + 2 < length) {
    const n = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
    out += ALPHABET.charAt((n >> 18) & 0x3f);
    out += ALPHABET.charAt((n >> 12) & 0x3f);
    out += ALPHABET.charAt((n >> 6) & 0x3f);
    out += ALPHABET.charAt(n & 0x3f);
    i += 3;
  }
  const remaining = length - i;
  if (remaining === 1) {
    const n = bytes[i] << 16;
    out += ALPHABET.charAt((n >> 18) & 0x3f);
    out += ALPHABET.charAt((n >> 12) & 0x3f);
    out += '==';
  } else if (remaining === 2) {
    const n = (bytes[i] << 16) | (bytes[i + 1] << 8);
    out += ALPHABET.charAt((n >> 18) & 0x3f);
    out += ALPHABET.charAt((n >> 12) & 0x3f);
    out += ALPHABET.charAt((n >> 6) & 0x3f);
    out += '=';
  }
  return out;
}

/**
 * Strict standard-alphabet base64 decoder: returns null when the input is not
 * well-formed base64 (bad character, broken padding, non-multiple-of-4 length)
 * instead of throwing, so callers can treat it as a format probe.
 */
export function decodeBase64(value: string): Uint8Array | null {
  let compact = '';
  for (const ch of value) {
    if (ch !== ' ' && ch !== '\n' && ch !== '\r' && ch !== '\t') {
      compact += ch;
    }
  }
  if (compact.length === 0 || compact.length % 4 !== 0) {
    return null;
  }
  const out: number[] = [];
  let buffer = 0;
  let bits = 0;
  for (let i = 0; i < compact.length; i++) {
    const ch = compact.charAt(i);
    if (ch === '=') {
      // Padding is only legal in the final group's last two slots.
      const tail = compact.length - i;
      if (tail > 2) {
        return null;
      }
      break;
    }
    const digit = ALPHABET.indexOf(ch);
    if (digit < 0) {
      return null;
    }
    buffer = (buffer << 6) | digit;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      out.push((buffer >> bits) & 0xff);
    }
  }
  return new Uint8Array(out);
}

/** Decodes UTF-8 bytes into a string; invalid sequences become U+FFFD. */
export function utf8Decode(bytes: Uint8Array): string {
  let out = '';
  let i = 0;
  while (i < bytes.length) {
    const b0 = bytes[i];
    if (b0 < 0x80) {
      out += String.fromCharCode(b0);
      i += 1;
    } else if ((b0 & 0xE0) === 0xC0 && i + 1 < bytes.length) {
      out += String.fromCharCode(((b0 & 0x1F) << 6) | (bytes[i + 1] & 0x3F));
      i += 2;
    } else if ((b0 & 0xF0) === 0xE0 && i + 2 < bytes.length) {
      out += String.fromCharCode(((b0 & 0x0F) << 12) | ((bytes[i + 1] & 0x3F) << 6) | (bytes[i + 2] & 0x3F));
      i += 3;
    } else if ((b0 & 0xF8) === 0xF0 && i + 3 < bytes.length) {
      // Four-byte sequences map to a UTF-16 surrogate pair.
      const codePoint = ((b0 & 0x07) << 18) | ((bytes[i + 1] & 0x3F) << 12)
        | ((bytes[i + 2] & 0x3F) << 6) | (bytes[i + 3] & 0x3F);
      out += String.fromCharCode(0xD800 + ((codePoint - 0x10000) >> 10));
      out += String.fromCharCode(0xDC00 + ((codePoint - 0x10000) & 0x3FF));
      i += 4;
    } else {
      out += '\uFFFD';
      i += 1;
    }
  }
  return out;
}
