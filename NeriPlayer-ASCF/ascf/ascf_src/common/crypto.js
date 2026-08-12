/**
 * 网易云 weapi 签名所需的纯 JS 加密：
 *   - AES-128-CBC (PKCS7) 两次加密
 *   - RSA-1024 PKCS#1 v1.5 加密随机 key
 * 移植自 NeriPlayer-HarmonyOS/entry/.../network/NeteaseCrypto.ets。
 */

const PRESET_KEY = '0CoJUm6Qyw8W8jud';
const IV = '0102030405060708';
const PUBLIC_MODULUS_HEX =
  '00e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7b725152b3ab17a876aea8a5aa76d2e417629ec4ee341f56135fccf695280104e0312ecbda92557c93870114af6c9d05c4f7f0c3685b7a46bee255932575cce10b424d813cfe4875d3e82047b97ddef52741d546b8e289dc6935b3ece0462db0a22b8e7';
const PUBLIC_EXPONENT_HEX = '010001';

// ---------------------------------------------------------------------------
// Base64
// ---------------------------------------------------------------------------

const B64_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

function bytesToBase64(bytes) {
  let result = '';
  let i;
  for (i = 0; i + 2 < bytes.length; i += 3) {
    const n = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
    result += B64_CHARS[(n >>> 18) & 63];
    result += B64_CHARS[(n >>> 12) & 63];
    result += B64_CHARS[(n >>> 6) & 63];
    result += B64_CHARS[n & 63];
  }
  const remaining = bytes.length - i;
  if (remaining === 1) {
    const n = bytes[i] << 16;
    result += B64_CHARS[(n >>> 18) & 63];
    result += B64_CHARS[(n >>> 12) & 63];
    result += '==';
  } else if (remaining === 2) {
    const n = (bytes[i] << 16) | (bytes[i + 1] << 8);
    result += B64_CHARS[(n >>> 18) & 63];
    result += B64_CHARS[(n >>> 12) & 63];
    result += B64_CHARS[(n >>> 6) & 63];
    result += '=';
  }
  return result;
}

// ---------------------------------------------------------------------------
// AES-128
// ---------------------------------------------------------------------------

const SBOX = [
  0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
  0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
  0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
  0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
  0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
  0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
  0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
  0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
  0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
  0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
  0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
  0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
  0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
  0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
  0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
  0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16,
];

const RCON = [0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36];

function xtime(a) {
  return ((a << 1) ^ (((a >>> 7) & 1) * 0x1b)) & 0xff;
}

function keyExpansion(keyBytes) {
  const w = new Uint8Array(176);
  for (let i = 0; i < 16; i++) {
    w[i] = keyBytes[i];
  }
  let rconIndex = 1;
  for (let i = 4; i < 44; i++) {
    let temp = [
      w[(i - 1) * 4],
      w[(i - 1) * 4 + 1],
      w[(i - 1) * 4 + 2],
      w[(i - 1) * 4 + 3],
    ];
    if (i % 4 === 0) {
      temp = [temp[1], temp[2], temp[3], temp[0]];
      temp[0] = SBOX[temp[0]];
      temp[1] = SBOX[temp[1]];
      temp[2] = SBOX[temp[2]];
      temp[3] = SBOX[temp[3]];
      temp[0] ^= RCON[rconIndex];
      rconIndex++;
    }
    for (let j = 0; j < 4; j++) {
      w[i * 4 + j] = w[(i - 4) * 4 + j] ^ temp[j];
    }
  }
  return w;
}

function addRoundKey(state, w, round) {
  const offset = round * 16;
  for (let c = 0; c < 4; c++) {
    for (let r = 0; r < 4; r++) {
      state[c * 4 + r] ^= w[offset + c * 4 + r];
    }
  }
}

function subBytes(state) {
  for (let i = 0; i < 16; i++) {
    state[i] = SBOX[state[i]];
  }
}

function shiftRows(state) {
  const temp = new Uint8Array(16);
  for (let r = 0; r < 4; r++) {
    for (let c = 0; c < 4; c++) {
      temp[c * 4 + r] = state[((c + r) % 4) * 4 + r];
    }
  }
  for (let i = 0; i < 16; i++) {
    state[i] = temp[i];
  }
}

function mixColumns(state) {
  for (let c = 0; c < 4; c++) {
    const base = c * 4;
    const a0 = state[base];
    const a1 = state[base + 1];
    const a2 = state[base + 2];
    const a3 = state[base + 3];
    state[base] = xtime(a0) ^ (xtime(a1) ^ a1) ^ a2 ^ a3;
    state[base + 1] = a0 ^ xtime(a1) ^ (xtime(a2) ^ a2) ^ a3;
    state[base + 2] = a0 ^ a1 ^ xtime(a2) ^ (xtime(a3) ^ a3);
    state[base + 3] = (xtime(a0) ^ a0) ^ a1 ^ a2 ^ xtime(a3);
  }
}

function encryptBlock(input, w) {
  const state = new Uint8Array(16);
  for (let i = 0; i < 16; i++) {
    state[i] = input[i];
  }
  addRoundKey(state, w, 0);
  for (let round = 1; round < 10; round++) {
    subBytes(state);
    shiftRows(state);
    mixColumns(state);
    addRoundKey(state, w, round);
  }
  subBytes(state);
  shiftRows(state);
  addRoundKey(state, w, 10);
  return state;
}

function pkcs7Pad(data) {
  const padding = 16 - (data.length % 16);
  const out = new Uint8Array(data.length + padding);
  out.set(data, 0);
  for (let i = 0; i < padding; i++) {
    out[data.length + i] = padding;
  }
  return out;
}

function aesCbcEncrypt(text, keyText) {
  const encoder = new TextEncoder();
  const key = keyExpansion(encoder.encode(keyText));
  const padded = pkcs7Pad(encoder.encode(text));
  // 注意：weapi 的 IV 是字符串 "0102030405060708" 的 16 个 ASCII 字节，
  // 与网易云官方 JS 实现（Buffer.from('0102030405060708')）保持一致。
  const iv = encoder.encode(IV);
  const ciphertext = new Uint8Array(padded.length);
  const prev = new Uint8Array(16);
  prev.set(iv, 0);
  for (let offset = 0; offset < padded.length; offset += 16) {
    const block = padded.subarray(offset, offset + 16);
    for (let i = 0; i < 16; i++) {
      block[i] ^= prev[i];
    }
    const encrypted = encryptBlock(block, key);
    ciphertext.set(encrypted, offset);
    prev.set(encrypted, 0);
  }
  return bytesToBase64(ciphertext);
}

// ---------------------------------------------------------------------------
// RSA-1024 PKCS#1 v1.5
// ---------------------------------------------------------------------------

function modPow(base, exponent, modulus) {
  let result = 1n;
  let b = base % modulus;
  let e = exponent;
  while (e > 0n) {
    if (e & 1n) {
      result = (result * b) % modulus;
    }
    b = (b * b) % modulus;
    e >>= 1n;
  }
  return result;
}

function hexToBytes(hex) {
  const clean = hex.length % 2 === 0 ? hex : '0' + hex;
  const bytes = new Uint8Array(clean.length / 2);
  for (let i = 0; i < clean.length; i += 2) {
    bytes[i / 2] = parseInt(clean.substring(i, i + 2), 16);
  }
  return bytes;
}

function bytesToHex(bytes) {
  let hex = '';
  for (let i = 0; i < bytes.length; i++) {
    hex += bytes[i].toString(16).padStart(2, '0');
  }
  return hex;
}

function randomBytes(length) {
  const bytes = new Uint8Array(length);
  let usedCrypto = false;
  try {
    if (typeof has !== 'undefined' && typeof has.getRandomValues === 'function') {
      const filled = has.getRandomValues(new ArrayBuffer(length));
      if (filled && filled.byteLength === length) {
        bytes.set(new Uint8Array(filled), 0);
        usedCrypto = true;
      }
    }
  } catch (e) {
    usedCrypto = false;
  }
  if (!usedCrypto) {
    for (let i = 0; i < length; i++) {
      bytes[i] = Math.floor(Math.random() * 256);
    }
  }
  return bytes;
}

function rsaPkcs1Encrypt(messageBytes) {
  const n = BigInt('0x' + PUBLIC_MODULUS_HEX);
  const e = BigInt('0x' + PUBLIC_EXPONENT_HEX);
  const k = 128;
  const em = new Uint8Array(k);
  em[0] = 0x00;
  em[1] = 0x02;
  const psLength = k - messageBytes.length - 3;
  const ps = randomBytes(psLength);
  for (let i = 0; i < psLength; i++) {
    em[2 + i] = ps[i] === 0 ? 1 : ps[i];
  }
  em[k - messageBytes.length - 1] = 0x00;
  em.set(messageBytes, k - messageBytes.length);

  let m = 0n;
  for (let i = 0; i < k; i++) {
    m = (m << 8n) | BigInt(em[i]);
  }
  const c = modPow(m, e, n);
  const cipherBytes = new Uint8Array(k);
  let value = c;
  for (let i = k - 1; i >= 0; i--) {
    cipherBytes[i] = Number(value & 0xffn);
    value >>= 8n;
  }
  return bytesToBase64(cipherBytes);
}

// ---------------------------------------------------------------------------
// weapi 入口
// ---------------------------------------------------------------------------

function randomKey(length) {
  const alphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  let result = '';
  for (let i = 0; i < length; i++) {
    result += alphabet.charAt(Math.floor(Math.random() * alphabet.length));
  }
  return result;
}

function weapiParams(params) {
  const text = JSON.stringify(params);
  const randomKeyValue = randomKey(16);
  const first = aesCbcEncrypt(text, PRESET_KEY);
  const second = aesCbcEncrypt(first, randomKeyValue);
  const encSecKey = rsaPkcs1Encrypt(hexToBytes(bytesToHex(new TextEncoder().encode(randomKeyValue))));
  return { params: second, encSecKey: encSecKey };
}

module.exports = {
  weapiParams,
  aesCbcEncrypt,
  rsaPkcs1Encrypt,
  bytesToHex,
  hexToBytes,
  bytesToBase64,
};
