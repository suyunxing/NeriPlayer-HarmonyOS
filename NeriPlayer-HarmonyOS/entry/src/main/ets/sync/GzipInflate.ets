/**
 * Pure-ArkTS gzip (RFC 1952) + DEFLATE (RFC 1951) decompressor.
 *
 * Reads the binary sync backup formats written by Android
 * SyncDataSerializer.compress (java.util.zip.GZIPOutputStream, default level)
 * and the legacy Base64(GZIP(...)) channel. @ohos.zlib is deliberately not
 * used: local hypium unit tests run without @ohos APIs (see M5.2 notes), and a
 * single pure implementation avoids device/test behavior drift.
 *
 * Behavior parity with java.util.zip.GZIPInputStream:
 *   - multi-member streams are concatenated
 *   - CRC32 and ISIZE trailers are verified per member
 *   - trailing all-zero padding after the last member is tolerated
 *   - any structural corruption returns null instead of throwing
 */

const GZIP_MAGIC0: number = 0x1F;
const GZIP_MAGIC1: number = 0x8B;
const GZIP_CM_DEFLATE: number = 8;

const FHCRC_FLAG: number = 0x02;
const FEXTRA_FLAG: number = 0x04;
const FNAME_FLAG: number = 0x08;
const FCOMMENT_FLAG: number = 0x10;

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
const CODE_LENGTH_ORDER: number[] = [
  16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15
];

const FIXED_LITERAL_LENGTHS: number[] = buildFixedLiteralLengths();
const FIXED_DISTANCE_LENGTHS: number[] = new Array<number>(30).fill(5);

function buildFixedLiteralLengths(): number[] {
  const lengths: number[] = [];
  for (let sym = 0; sym < 144; sym++) {
    lengths.push(8);
  }
  for (let sym = 144; sym < 256; sym++) {
    lengths.push(9);
  }
  for (let sym = 256; sym < 280; sym++) {
    lengths.push(7);
  }
  for (let sym = 280; sym < 288; sym++) {
    lengths.push(8);
  }
  return lengths;
}

// ---------------------------------------------------------------------------
// CRC32 (IEEE, reflected) for gzip trailer verification
// ---------------------------------------------------------------------------

let crcTable: number[] | null = null;

function ensureCrcTable(): number[] {
  if (crcTable !== null) {
    return crcTable as number[];
  }
  const table: number[] = new Array<number>(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) {
      c = (c & 1) !== 0 ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
    }
    table[n] = c;
  }
  crcTable = table;
  return table;
}

function crc32Range(bytes: Uint8Array, start: number, end: number): number {
  const table = ensureCrcTable();
  let crc = 0xFFFFFFFF;
  for (let i = start; i < end; i++) {
    crc = table[(crc ^ bytes[i]) & 0xFF] ^ (crc >>> 8);
  }
  return (crc ^ 0xFFFFFFFF) >>> 0;
}

// ---------------------------------------------------------------------------
// Bit-level reader (DEFLATE packs bits LSB-first within each byte)
// ---------------------------------------------------------------------------

class BitReader {
  private readonly bytes: Uint8Array;
  private pos: number;
  private readonly end: number;
  private bitBuf: number = 0;
  private bitCnt: number = 0;

  constructor(bytes: Uint8Array, start: number, end: number) {
    this.bytes = bytes;
    this.pos = start;
    this.end = end;
  }

  /** True when at least n more bits are available (or already buffered). */
  need(n: number): boolean {
    while (this.bitCnt < n) {
      if (this.pos >= this.end) {
        return false;
      }
      this.bitBuf |= this.bytes[this.pos++] << this.bitCnt;
      this.bitCnt += 8;
    }
    return true;
  }

  bits(n: number): number {
    const value = this.bitBuf & ((1 << n) - 1);
    this.bitBuf = this.bitBuf >>> n;
    this.bitCnt -= n;
    return value;
  }

  /** Byte position of the next unconsumed byte after dropping partial bits. */
  consumed(): number {
    return this.pos - (this.bitCnt >> 3);
  }

  /** Drop the partial bits of the current byte, keep whole buffered bytes. */
  alignToByte(): void {
    const drop = this.bitCnt % 8;
    this.bitBuf = this.bitBuf >>> drop;
    this.bitCnt -= drop;
  }

  readByteAligned(): number {
    if (!this.need(8)) {
      return -1;
    }
    return this.bits(8);
  }
}

// ---------------------------------------------------------------------------
// Canonical Huffman decoding (puff-style: counts per length + sorted symbols)
// ---------------------------------------------------------------------------

class HuffmanTable {
  readonly counts: number[] = new Array<number>(16).fill(0);
  readonly symbols: number[] = [];
}

function buildHuffman(lengths: number[], offset: number, count: number): HuffmanTable {
  const table = new HuffmanTable();
  for (let i = 0; i < count; i++) {
    const len = lengths[offset + i];
    if (len > 0 && len <= 15) {
      table.counts[len]++;
    }
  }
  const offsets: number[] = new Array<number>(16).fill(0);
  let offsetIndex = 0;
  for (let len = 1; len <= 15; len++) {
    offsets[len] = offsetIndex;
    offsetIndex += table.counts[len];
  }
  for (let i = 0; i < count; i++) {
    const len = lengths[offset + i];
    if (len > 0 && len <= 15) {
      table.symbols[offsets[len]++] = i;
    }
  }
  return table;
}

const SYMBOL_INVALID: number = -1;
const SYMBOL_OUT_OF_DATA: number = -2;

function decodeSymbol(reader: BitReader, table: HuffmanTable): number {
  let code = 0;
  let first = 0;
  let index = 0;
  for (let len = 1; len <= 15; len++) {
    if (!reader.need(1)) {
      return SYMBOL_OUT_OF_DATA;
    }
    code |= reader.bits(1);
    const count = table.counts[len];
    if (code - first < count) {
      return table.symbols[index + (code - first)];
    }
    index += count;
    first = (first + count) << 1;
    code <<= 1;
  }
  return SYMBOL_INVALID;
}

// ---------------------------------------------------------------------------
// Growable output buffer with the decompression-size ceiling
// ---------------------------------------------------------------------------

class OutputSink {
  data: Uint8Array;
  length: number = 0;
  private readonly limit: number;

  constructor(limit: number) {
    this.limit = limit;
    this.data = new Uint8Array(Math.min(limit, 64 * 1024));
  }

  ensure(extra: number): boolean {
    if (this.length + extra > this.limit) {
      return false;
    }
    if (this.length + extra > this.data.length) {
      let capacity = this.data.length * 2;
      while (capacity < this.length + extra) {
        capacity *= 2;
      }
      const grown = new Uint8Array(Math.min(capacity, this.limit));
      grown.set(this.data.subarray(0, this.length), 0);
      this.data = grown;
    }
    return true;
  }

  pushByte(value: number): boolean {
    if (!this.ensure(1)) {
      return false;
    }
    this.data[this.length++] = value & 0xFF;
    return true;
  }

  /** LZ77 back-copy; the ranges may overlap like a sliding window copy. */
  copyBack(distance: number, length: number): boolean {
    if (distance > this.length || distance <= 0) {
      return false;
    }
    if (!this.ensure(length)) {
      return false;
    }
    let from = this.length - distance;
    for (let i = 0; i < length; i++) {
      this.data[this.length++] = this.data[from++];
    }
    return true;
  }

  appendRange(bytes: Uint8Array, start: number, end: number): boolean {
    const count = end - start;
    if (count < 0 || !this.ensure(count)) {
      return false;
    }
    for (let i = start; i < end; i++) {
      this.data[this.length++] = bytes[i];
    }
    return true;
  }

  slice(): Uint8Array {
    return this.data.subarray(0, this.length);
  }
}

// ---------------------------------------------------------------------------
// Raw DEFLATE stream (RFC 1951)
// ---------------------------------------------------------------------------

export class InflateResult {
  readonly data: Uint8Array;
  readonly consumed: number;

  constructor(data: Uint8Array, consumed: number) {
    this.data = data;
    this.consumed = consumed;
  }
}

function inflateCodes(
  reader: BitReader,
  literalTable: HuffmanTable,
  distanceTable: HuffmanTable,
  sink: OutputSink
): boolean {
  while (true) {
    const symbol = decodeSymbol(reader, literalTable);
    if (symbol === SYMBOL_OUT_OF_DATA || symbol === SYMBOL_INVALID) {
      return false;
    }
    if (symbol < 256) {
      if (!sink.pushByte(symbol)) {
        return false;
      }
      continue;
    }
    if (symbol === 256) {
      return true;
    }
    const lengthIndex = symbol - 257;
    if (lengthIndex >= LENGTH_BASE.length) {
      return false;
    }
    let length = LENGTH_BASE[lengthIndex];
    const lengthExtra = LENGTH_EXTRA[lengthIndex];
    if (lengthExtra > 0) {
      if (!reader.need(lengthExtra)) {
        return false;
      }
      length += reader.bits(lengthExtra);
    }
    const distanceSymbol = decodeSymbol(reader, distanceTable);
    if (distanceSymbol === SYMBOL_OUT_OF_DATA || distanceSymbol === SYMBOL_INVALID) {
      return false;
    }
    if (distanceSymbol >= DIST_BASE.length) {
      return false;
    }
    let distance = DIST_BASE[distanceSymbol];
    const distanceExtra = DIST_EXTRA[distanceSymbol];
    if (distanceExtra > 0) {
      if (!reader.need(distanceExtra)) {
        return false;
      }
      distance += reader.bits(distanceExtra);
    }
    if (!sink.copyBack(distance, length)) {
      return false;
    }
  }
}

/** Literal/length + distance tables of one dynamic block. */
class DynamicTables {
  readonly literalTable: HuffmanTable;
  readonly distanceTable: HuffmanTable;

  constructor(literalTable: HuffmanTable, distanceTable: HuffmanTable) {
    this.literalTable = literalTable;
    this.distanceTable = distanceTable;
  }
}

function inflateDynamicHeader(reader: BitReader, lengths: number[]): DynamicTables | null {
  if (!reader.need(14)) {
    return null;
  }
  const literalCount = reader.bits(5) + 257;
  const distanceCount = reader.bits(5) + 1;
  const codeLengthCount = reader.bits(4) + 4;
  if (literalCount > 286 || distanceCount > 30) {
    return null;
  }
  const codeLengthLengths: number[] = new Array<number>(19).fill(0);
  for (let i = 0; i < codeLengthCount; i++) {
    if (!reader.need(3)) {
      return null;
    }
    codeLengthLengths[CODE_LENGTH_ORDER[i]] = reader.bits(3);
  }
  const codeLengthTable = buildHuffman(codeLengthLengths, 0, 19);
  let filled = 0;
  while (filled < literalCount + distanceCount) {
    const symbol = decodeSymbol(reader, codeLengthTable);
    if (symbol === SYMBOL_OUT_OF_DATA || symbol === SYMBOL_INVALID) {
      return null;
    }
    if (symbol < 16) {
      lengths[filled++] = symbol;
      continue;
    }
    let repeat = 0;
    let value = 0;
    if (symbol === 16) {
      if (filled === 0) {
        return null;
      }
      value = lengths[filled - 1];
      if (!reader.need(2)) {
        return null;
      }
      repeat = 3 + reader.bits(2);
    } else if (symbol === 17) {
      if (!reader.need(3)) {
        return null;
      }
      repeat = 3 + reader.bits(3);
    } else {
      if (!reader.need(7)) {
        return null;
      }
      repeat = 11 + reader.bits(7);
    }
    if (filled + repeat > literalCount + distanceCount) {
      return null;
    }
    while (repeat-- > 0) {
      lengths[filled++] = value;
    }
  }
  if (lengths[literalCount - 1] === 0) {
    // The literal/length code must contain at least one end-of-block code.
    return null;
  }
  return new DynamicTables(
    buildHuffman(lengths, 0, literalCount),
    buildHuffman(lengths, literalCount, distanceCount)
  );
}

/** Inflates one raw DEFLATE stream; returns null on any corruption. */
export function inflateRaw(input: Uint8Array, start: number, maxOutputBytes: number): InflateResult | null {
  const reader = new BitReader(input, start, input.length);
  const sink = new OutputSink(maxOutputBytes);
  const lengths: number[] = new Array<number>(320).fill(0);
  const fixedLiteralTable = buildHuffman(FIXED_LITERAL_LENGTHS, 0, 288);
  const fixedDistanceTable = buildHuffman(FIXED_DISTANCE_LENGTHS, 0, 30);

  let finalBlock = false;
  while (!finalBlock) {
    if (!reader.need(3)) {
      return null;
    }
    finalBlock = reader.bits(1) !== 0;
    const blockType = reader.bits(2);
    if (blockType === 0) {
      reader.alignToByte();
      const lenLow = reader.readByteAligned();
      const lenHigh = reader.readByteAligned();
      const nlenLow = reader.readByteAligned();
      const nlenHigh = reader.readByteAligned();
      if (lenLow < 0 || lenHigh < 0 || nlenLow < 0 || nlenHigh < 0) {
        return null;
      }
      const storedLength = lenLow | (lenHigh << 8);
      const storedComplement = nlenLow | (nlenHigh << 8);
      if ((storedLength ^ 0xFFFF) !== storedComplement) {
        return null;
      }
      for (let i = 0; i < storedLength; i++) {
        const b = reader.readByteAligned();
        if (b < 0 || !sink.pushByte(b)) {
          return null;
        }
      }
    } else if (blockType === 1) {
      if (!inflateCodes(reader, fixedLiteralTable, fixedDistanceTable, sink)) {
        return null;
      }
    } else if (blockType === 2) {
      const tables = inflateDynamicHeader(reader, lengths);
      if (tables === null) {
        return null;
      }
      if (!inflateCodes(reader, tables.literalTable, tables.distanceTable, sink)) {
        return null;
      }
    } else {
      return null;
    }
  }
  reader.alignToByte();
  return new InflateResult(sink.slice(), reader.consumed() - start);
}

// ---------------------------------------------------------------------------
// gzip container (RFC 1952)
// ---------------------------------------------------------------------------

function readU32Le(bytes: Uint8Array, offset: number): number {
  return (bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24)) >>> 0;
}

function parseGzipHeader(input: Uint8Array, start: number): number | null {
  let pos = start;
  if (pos + 10 > input.length) {
    return null;
  }
  if (input[pos] !== GZIP_MAGIC0 || input[pos + 1] !== GZIP_MAGIC1) {
    return null;
  }
  if (input[pos + 2] !== GZIP_CM_DEFLATE) {
    return null;
  }
  const flags = input[pos + 3];
  if ((flags & 0xE0) !== 0) {
    return null; // reserved bits must be zero
  }
  pos += 10; // magic(2) + CM + FLG + MTIME(4) + XFL + OS
  if ((flags & FEXTRA_FLAG) !== 0) {
    if (pos + 2 > input.length) {
      return null;
    }
    pos += 2 + (input[pos] | (input[pos + 1] << 8));
  }
  if ((flags & (FNAME_FLAG | FCOMMENT_FLAG)) !== 0) {
    const hasName = (flags & FNAME_FLAG) !== 0;
    const hasComment = (flags & FCOMMENT_FLAG) !== 0;
    for (let field = 0; field < (hasName ? 1 : 0) + (hasComment ? 1 : 0); field++) {
      while (pos < input.length && input[pos] !== 0) {
        pos++;
      }
      if (pos >= input.length) {
        return null;
      }
      pos++; // consume the NUL terminator
    }
  }
  if ((flags & FHCRC_FLAG) !== 0) {
    pos += 2; // header CRC16 present but not verified, like GZIPInputStream
  }
  if (pos > input.length) {
    return null;
  }
  return pos;
}

function trailingBytesAreZero(input: Uint8Array, start: number): boolean {
  for (let i = start; i < input.length; i++) {
    if (input[i] !== 0) {
      return false;
    }
  }
  return true;
}

/**
 * Decompresses a full gzip stream. Mirrors GZIPInputStream semantics: members
 * are concatenated, each trailer is verified, trailing zero padding is
 * tolerated, and anything else corrupted returns null.
 */
export function gunzip(input: Uint8Array, maxOutputBytes: number): Uint8Array | null {
  const sink = new OutputSink(maxOutputBytes);
  let pos = 0;
  while (true) {
    const dataStart = parseGzipHeader(input, pos);
    if (dataStart === null) {
      if (pos > 0 && trailingBytesAreZero(input, pos)) {
        break;
      }
      return null;
    }
    const inflated = inflateRaw(input, dataStart, maxOutputBytes);
    if (inflated === null) {
      return null;
    }
    const trailer = dataStart + inflated.consumed;
    if (trailer + 8 > input.length) {
      return null;
    }
    const expectedCrc = readU32Le(input, trailer);
    const expectedSize = readU32Le(input, trailer + 4);
    const memberStart = sink.length;
    if (!sink.appendRange(inflated.data, 0, inflated.data.length)) {
      return null;
    }
    if (crc32Range(inflated.data, 0, inflated.data.length) !== expectedCrc) {
      return null;
    }
    if ((sink.length - memberStart) !== expectedSize) {
      return null;
    }
    pos = trailer + 8;
    if (pos === input.length) {
      break;
    }
    if (pos + 2 <= input.length && input[pos] === GZIP_MAGIC0 && input[pos + 1] === GZIP_MAGIC1) {
      continue;
    }
    if (trailingBytesAreZero(input, pos)) {
      break;
    }
    return null;
  }
  return sink.slice();
}
