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
