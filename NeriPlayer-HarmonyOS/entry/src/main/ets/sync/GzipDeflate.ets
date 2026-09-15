// SPDX-License-Identifier: GPL-3.0

/**
 * Pure-ArkTS gzip (RFC 1952) compressor: fixed-Huffman DEFLATE (RFC 1951)
 * with hash-chain LZ77 matching. Write-side counterpart of GzipInflate.ets;
 * kept @ohos-free so the round trip runs in local hypium unit tests.
 *
 * Output is a standards-compliant single-member gzip stream (BFINAL=1,
 * BTYPE=01) that java.util.zip.GZIPInputStream (Android) and every standard
 * inflater read; compression sits in the same band as Java's default level
 * (~20-30% on sync payloads). Cross-checked against the reference inflaters:
 * GzipInflate (own tests) and CPython's gzip module during development.
 */

const LENGTH_BASE: number[] = [
  3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
  35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258
];
const LENGTH_EXTRA: number[] = [
  0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
  3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0
];
const DIST_BASE: number[] = [
  1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
  257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145,
  8193, 12289, 16385, 24577
];
const DIST_EXTRA: number[] = [
  0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
  7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13
];

const WINDOW_SIZE: number = 32768;
const MIN_MATCH: number = 3;
const MAX_MATCH: number = 258;
const MAX_CHAIN: number = 128;

class LzMatch {
  length: number;
  distance: number;

  constructor(length: number, distance: number) {
    this.length = length;
    this.distance = distance;
  }
}

/** LSB-first bit writer; Huffman codes are written MSB-first per RFC 1951. */
class BitWriter {
  bytes: number[] = [];
  private current: number = 0;
  private bitCount: number = 0;

  writeBits(value: number, count: number): void {
    for (let i = 0; i < count; i++) {
      this.current |= ((value >>> i) & 1) << this.bitCount;
      this.bitCount++;
      if (this.bitCount === 8) {
        this.bytes.push(this.current);
        this.current = 0;
        this.bitCount = 0;
      }
    }
  }

  writeCode(code: number, count: number): void {
    for (let i = count - 1; i >= 0; i--) {
      this.current |= ((code >>> i) & 1) << this.bitCount;
      this.bitCount++;
      if (this.bitCount === 8) {
        this.bytes.push(this.current);
        this.current = 0;
        this.bitCount = 0;
      }
    }
  }

  flush(): void {
    if (this.bitCount > 0) {
      this.bytes.push(this.current);
      this.current = 0;
      this.bitCount = 0;
    }
  }
}

/** Fixed literal/length code (RFC 1951 §3.2.6): [code, bitCount]. */
function fixedLiteralCode(symbol: number): number[] {
  if (symbol <= 143) {
    return [0x30 + symbol, 8];
  }
  if (symbol <= 255) {
    return [0x190 + symbol - 144, 9];
  }
  if (symbol <= 279) {
    return [symbol - 256, 7];
  }
  return [0xC0 + symbol - 280, 8];
}

function lengthSymbol(length: number): number {
  for (let symbol = LENGTH_BASE.length - 1; symbol >= 0; symbol--) {
    if (length >= LENGTH_BASE[symbol]) {
      return symbol;
    }
  }
  return 0;
}

function distanceSymbol(distance: number): number {
  for (let symbol = DIST_BASE.length - 1; symbol >= 0; symbol--) {
    if (distance >= DIST_BASE[symbol]) {
      return symbol;
    }
  }
  return 0;
}

function crc32(bytes: Uint8Array): number {
  let c = 0xFFFFFFFF;
  for (let i = 0; i < bytes.length; i++) {
    c = CRC32_TABLE[(c ^ bytes[i]) & 0xFF] ^ (c >>> 8);
  }
  return (c ^ 0xFFFFFFFF) >>> 0;
}

const CRC32_TABLE: Int32Array = buildCrc32Table();

function buildCrc32Table(): Int32Array {
  const table = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) {
      c = (c & 1) !== 0 ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
    }
    table[n] = c;
  }
  return table;
}

/** Hash-chain LZ77: literals and matches, greedy longest-match strategy. */
function lz77Tokenize(data: Uint8Array): Array<number | LzMatch> {
  const items: Array<number | LzMatch> = [];
  if (data.length < MIN_MATCH) {
    for (let i = 0; i < data.length; i++) {
      items.push(data[i]);
    }
    return items;
  }
  const head = new Int32Array(65536).fill(-1);
  const prev = new Int32Array(data.length).fill(-1);
  const hashAt = (i: number): number =>
    (((data[i] << 10) ^ (data[i + 1] << 5) ^ data[i + 2]) & 0xFFFF);
  let pos = 0;
  while (pos < data.length) {
    let bestLength = 0;
    let bestDistance = 0;
    if (pos + MIN_MATCH <= data.length) {
      const hash = hashAt(pos);
      let candidate = head[hash];
      let chain = 0;
      const limit = pos > WINDOW_SIZE ? pos - WINDOW_SIZE : 0;
      const maxLen = Math.min(MAX_MATCH, data.length - pos);
      while (candidate >= limit && candidate >= 0 && candidate < pos && chain < MAX_CHAIN) {
        let length = 0;
        while (length < maxLen && data[candidate + length] === data[pos + length]) {
          length++;
        }
        if (length > bestLength) {
          bestLength = length;
          bestDistance = pos - candidate;
          if (length >= MAX_MATCH) {
            break;
          }
        }
        candidate = prev[candidate];
        chain++;
      }
    }
    if (bestLength >= MIN_MATCH) {
      items.push(new LzMatch(bestLength, bestDistance));
      const end = Math.min(pos + bestLength, data.length - 2);
      const step = bestLength > 64 ? 32 : 1;
      for (let j = pos; j < end; j += step) {
        const h = hashAt(j);
        prev[j] = head[h];
        head[h] = j;
      }
      pos += bestLength;
    } else {
      items.push(data[pos]);
      if (pos + 2 < data.length) {
        const h = hashAt(pos);
        prev[pos] = head[h];
        head[h] = pos;
      }
      pos++;
    }
  }
  return items;
}

function deflateFixed(data: Uint8Array): Uint8Array {
  const writer = new BitWriter();
  writer.writeBits(1, 1); // BFINAL
  writer.writeBits(1, 2); // BTYPE=01 (fixed Huffman)
  for (const item of lz77Tokenize(data)) {
    if (item instanceof LzMatch) {
      const ls = lengthSymbol(item.length);
      const lengthCode = fixedLiteralCode(257 + ls);
      writer.writeCode(lengthCode[0], lengthCode[1]);
      writer.writeBits(item.length - LENGTH_BASE[ls], LENGTH_EXTRA[ls]);
      const ds = distanceSymbol(item.distance);
      writer.writeCode(ds, 5);
      writer.writeBits(item.distance - DIST_BASE[ds], DIST_EXTRA[ds]);
    } else {
      const literalCode = fixedLiteralCode(item);
      writer.writeCode(literalCode[0], literalCode[1]);
    }
  }
  const endCode = fixedLiteralCode(256);
  writer.writeCode(endCode[0], endCode[1]);
  writer.flush();
  return Uint8Array.from(writer.bytes);
}

/** gzip(data): single member, no name/extra fields, OS=255 (unknown). */
export function gzipCompress(data: Uint8Array): Uint8Array {
  const body = deflateFixed(data);
  const out = new Uint8Array(10 + body.length + 8);
  out[0] = 0x1F;
  out[1] = 0x8B;
  out[2] = 8; // CM = deflate
  out[3] = 0; // FLG
  out[4] = 0;
  out[5] = 0;
  out[6] = 0;
  out[7] = 0; // MTIME = 0 (Android GZIPOutputStream also writes 0)
  out[8] = 0; // XFL
  out[9] = 255; // OS = unknown
  out.set(body, 10);
  const crc = crc32(data);
  const size = data.length >>> 0;
  const tail = out.length - 8;
  out[tail] = crc & 0xFF;
  out[tail + 1] = (crc >>> 8) & 0xFF;
  out[tail + 2] = (crc >>> 16) & 0xFF;
  out[tail + 3] = (crc >>> 24) & 0xFF;
  out[tail + 4] = size & 0xFF;
  out[tail + 5] = (size >>> 8) & 0xFF;
  out[tail + 6] = (size >>> 16) & 0xFF;
  out[tail + 7] = (size >>> 24) & 0xFF;
  return out;
}
