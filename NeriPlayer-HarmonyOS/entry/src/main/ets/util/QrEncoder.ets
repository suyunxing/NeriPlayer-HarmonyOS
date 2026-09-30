// SPDX-License-Identifier: GPL-3.0

/**
 * Pure ArkTS QR code encoder (byte mode, error correction level M, versions
 * 1..10, max payload 213 bytes) used to render the NetEase QR login code.
 *
 * Verified byte-for-byte against the segno reference generator (fixture tests
 * in entry/src/test/ets/test/QrEncoder.test.ets): fixed-mask fixtures for
 * versions 1/3/9/10 plus a length x mask sweep. Two reference-specific
 * conventions are replicated so fixtures stay byte-identical:
 * - byte padding appends a full 0x00 codeword when the stream is already
 *   byte-aligned (decoders ignore pad content),
 * - mask evaluation scores the symbol with format/version cells as light.
 */

class EccGroup {
  count: number = 0;
  dataCw: number = 0;
  totalCw: number = 0;

  constructor(count: number, dataCw: number, totalCw: number) {
    this.count = count;
    this.dataCw = dataCw;
    this.totalCw = totalCw;
  }
}

// Error correction level M block structure per version (QR spec table).
const ECC_M: EccGroup[] = [
  new EccGroup(1, 16, 26), // v1
  new EccGroup(1, 28, 44), // v2
  new EccGroup(1, 44, 70), // v3
  new EccGroup(2, 32, 50), // v4
  new EccGroup(2, 43, 67), // v5
  new EccGroup(4, 27, 43), // v6
  new EccGroup(4, 31, 49), // v7
  new EccGroup(2, 38, 60), new EccGroup(2, 39, 61), // v8
  new EccGroup(3, 36, 58), new EccGroup(2, 37, 59), // v9
  new EccGroup(4, 43, 69), new EccGroup(1, 44, 70) // v10
];

const GROUP_START: number[] = [0, 1, 2, 3, 4, 5, 6, 7, 9, 11];
const GROUP_END: number[] = [1, 2, 3, 4, 5, 6, 7, 9, 11, 13];

// Alignment pattern center coordinates per version (version 1 has none).
const ALIGN_CENTERS: string[] = [
  '6,18', '6,22', '6,26', '6,30', '6,34', '6,22,38', '6,24,42', '6,26,46', '6,28,50'
];

const GF_EXP: number[] = [];
const GF_LOG: number[] = [];

function initGfTables(): void {
  for (let i = 0; i < 256; i++) {
    GF_LOG[i] = 0;
  }
  let x = 1;
  for (let i = 0; i < 255; i++) {
    GF_EXP[i] = x;
    GF_LOG[x] = i;
    x <<= 1;
    if ((x & 0x100) !== 0) {
      x ^= 0x11d;
    }
  }
  for (let i = 255; i < 512; i++) {
    GF_EXP[i] = GF_EXP[i - 255];
  }
}

function gmul(a: number, b: number): number {
  if (a === 0 || b === 0) {
    return 0;
  }
  return GF_EXP[GF_LOG[a] + GF_LOG[b]];
}

function rsGenerator(ecLen: number): number[] {
  let poly: number[] = [1];
  for (let i = 0; i < ecLen; i++) {
    const next: number[] = [];
    for (let j = 0; j <= poly.length; j++) {
      next.push(0);
    }
    for (let j = 0; j < poly.length; j++) {
      next[j] ^= poly[j];
      next[j + 1] ^= gmul(poly[j], GF_EXP[i]);
    }
    poly = next;
  }
  return poly;
}

function rsEncode(data: number[], ecLen: number): number[] {
  const gen = rsGenerator(ecLen);
  const res: number[] = [];
  for (let i = 0; i < ecLen; i++) {
    res.push(0);
  }
  for (const b of data) {
    const factor = b ^ res[0];
    for (let i = 0; i < ecLen - 1; i++) {
      res[i] = res[i + 1];
    }
    res[ecLen - 1] = 0;
    if (factor !== 0) {
      for (let i = 0; i < ecLen; i++) {
        res[i] ^= gmul(gen[i + 1], factor);
      }
    }
  }
  return res;
}

export function utf8Encode(text: string): number[] {
  const out: number[] = [];
  for (let i = 0; i < text.length; i++) {
    const cp = text.charCodeAt(i);
    if (cp < 0x80) {
      out.push(cp);
    } else if (cp < 0x800) {
      out.push(0xc0 | (cp >> 6), 0x80 | (cp & 0x3f));
    } else if (cp >= 0xd800 && cp <= 0xdbff && i + 1 < text.length) {
      // surrogate pair
      const lo = text.charCodeAt(i + 1);
      const code = 0x10000 + ((cp - 0xd800) << 10) + (lo - 0xdc00);
      i++;
      out.push(0xf0 | (code >> 18), 0x80 | ((code >> 12) & 0x3f), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
    } else {
      out.push(0xe0 | (cp >> 12), 0x80 | ((cp >> 6) & 0x3f), 0x80 | (cp & 0x3f));
    }
  }
  return out;
}

function groupsFor(version: number): EccGroup[] {
  const groups: EccGroup[] = [];
  for (let i = GROUP_START[version - 1]; i < GROUP_END[version - 1]; i++) {
    groups.push(ECC_M[i]);
  }
  return groups;
}

function dataCodewords(version: number): number {
  let total = 0;
  for (const g of groupsFor(version)) {
    total += g.count * g.dataCw;
  }
  return total;
}

export function selectVersion(byteLen: number, maxVersion: number): number {
  for (let v = 1; v <= maxVersion; v++) {
    const ccBits = v <= 9 ? 8 : 16;
    if (4 + ccBits + byteLen * 8 <= dataCodewords(v) * 8) {
      return v;
    }
  }
  return -1;
}

function buildCodewords(bytes: number[], version: number): number[] {
  const totalData = dataCodewords(version);
  const capacityBits = totalData * 8;
  const bits: number[] = [];
  const push = (value: number, n: number): void => {
    for (let i = n - 1; i >= 0; i--) {
      bits.push((value >> i) & 1);
    }
  };
  push(4, 4); // byte mode
  push(bytes.length, version <= 9 ? 8 : 16);
  for (const b of bytes) {
    push(b, 8);
  }
  const term = Math.min(4, capacityBits - bits.length);
  for (let i = 0; i < term; i++) {
    bits.push(0);
  }
  // Byte-boundary padding: always appends 8-(len%8) zero bits (a full 0x00
  // byte when already aligned) to stay byte-identical with the reference.
  const padBits = 8 - (bits.length % 8);
  for (let i = 0; i < padBits; i++) {
    bits.push(0);
  }
  const data: number[] = [];
  for (let i = 0; i + 8 <= bits.length; i += 8) {
    let b = 0;
    for (let j = 0; j < 8; j++) {
      b = (b << 1) | bits[i + j];
    }
    data.push(b);
  }
  let padToggle = true;
  while (data.length < totalData) {
    data.push(padToggle ? 0xec : 0x11);
    padToggle = !padToggle;
  }
  const dataBlocks: number[][] = [];
  const eccBlocks: number[][] = [];
  let off = 0;
  for (const g of groupsFor(version)) {
    for (let i = 0; i < g.count; i++) {
      const block: number[] = [];
      for (let j = 0; j < g.dataCw; j++) {
        block.push(data[off + j]);
      }
      off += g.dataCw;
      dataBlocks.push(block);
      eccBlocks.push(rsEncode(block, g.totalCw - g.dataCw));
    }
  }
  let maxData = 0;
  let maxEcc = 0;
  for (const b of dataBlocks) {
    maxData = Math.max(maxData, b.length);
  }
  for (const b of eccBlocks) {
    maxEcc = Math.max(maxEcc, b.length);
  }
  const out: number[] = [];
  for (let i = 0; i < maxData; i++) {
    for (const b of dataBlocks) {
      if (i < b.length) {
        out.push(b[i]);
      }
    }
  }
  for (let i = 0; i < maxEcc; i++) {
    for (const b of eccBlocks) {
      if (i < b.length) {
        out.push(b[i]);
      }
    }
  }
  return out;
}

function highestBit(v: number): number {
  let h = -1;
  while (v > 0) {
    v >>>= 1;
    h++;
  }
  return h;
}

// Format info: 5-bit data (M level = 0) + BCH(15,5), masked with 0x5412.
function bchFormat(data: number): number {
  const gen = 0x537;
  const genTop = 10;
  const d = data << 10;
  let rem = d;
  if (highestBit(d) >= genTop) {
    while (highestBit(rem) >= genTop) {
      rem ^= gen << (highestBit(rem) - genTop);
    }
  }
  return ((data << 10) | rem) ^ 0x5412;
}

// Version info (v >= 7): 6-bit version + BCH(18,6).
function bchVersion(v: number): number {
  const gen = 0x1f25;
  const genTop = 12;
  const d = v << 12;
  let rem = d;
  if (highestBit(d) >= genTop) {
    while (highestBit(rem) >= genTop) {
      rem ^= gen << (highestBit(rem) - genTop);
    }
  }
  return (v << 12) | rem;
}

type MaskFn = (i: number, j: number) => boolean;

function maskFn(mask: number): MaskFn {
  switch (mask) {
    case 0:
      return (i: number, j: number): boolean => (i + j) % 2 === 0;
    case 1:
      return (i: number, j: number): boolean => i % 2 === 0;
    case 2:
      return (i: number, j: number): boolean => j % 3 === 0;
    case 3:
      return (i: number, j: number): boolean => (i + j) % 3 === 0;
    case 4:
      return (i: number, j: number): boolean => (Math.floor(i / 2) + Math.floor(j / 3)) % 2 === 0;
    case 5:
      return (i: number, j: number): boolean => ((i * j) % 2) + ((i * j) % 3) === 0;
    case 6:
      return (i: number, j: number): boolean => (((i * j) % 2) + ((i * j) % 3)) % 2 === 0;
    default:
      return (i: number, j: number): boolean => (((i * j) % 3) + ((i + j) % 2)) % 2 === 0;
  }
}

export class QrMatrix {
  readonly size: number;
  private readonly cells: boolean[];

  constructor(size: number) {
    this.size = size;
    this.cells = [];
    for (let i = 0; i < size * size; i++) {
      this.cells.push(false);
    }
  }

  isDark(row: number, col: number): boolean {
    return this.cells[row * this.size + col];
  }

  set(row: number, col: number, dark: boolean): void {
    this.cells[row * this.size + col] = dark;
  }

  // Compact row encoding ('1' = dark) for fixture tests and debugging.
  rowString(row: number): string {
    let out = '';
    for (let j = 0; j < this.size; j++) {
      out += this.isDark(row, j) ? '1' : '0';
    }
    return out;
  }
}

// buildMatrix works on a nullable cell grid internally; null marks a cell not
// yet claimed by a function pattern.
class WorkGrid {
  readonly count: number;
  readonly values: (boolean | null)[];

  constructor(count: number) {
    this.count = count;
    this.values = [];
    for (let i = 0; i < count * count; i++) {
      this.values.push(null);
    }
  }

  get(row: number, col: number): boolean | null {
    return this.values[row * this.count + col];
  }

  set(row: number, col: number, value: boolean | null): void {
    this.values[row * this.count + col] = value;
  }
}

function buildMatrix(version: number, codewords: number[], mask: number): QrMatrix {
  const count = 17 + 4 * version;
  const g = new WorkGrid(count);

  const setFinder = (row: number, col: number): void => {
    for (let r = -1; r <= 7; r++) {
      for (let c = -1; c <= 7; c++) {
        const rr = row + r;
        const cc = col + c;
        if (rr < 0 || count <= rr || cc < 0 || count <= cc) {
          continue;
        }
        const inRing = r >= 0 && r <= 6 && (c === 0 || c === 6);
        const inRing2 = c >= 0 && c <= 6 && (r === 0 || r === 6);
        const inCore = r >= 2 && r <= 4 && c >= 2 && c <= 4;
        g.set(rr, cc, inRing || inRing2 || inCore);
      }
    }
  };
  setFinder(0, 0);
  setFinder(count - 7, 0);
  setFinder(0, count - 7);

  // Alignment patterns (version 1 has none; skip the three finder corners).
  if (version >= 2) {
    const parts = ALIGN_CENTERS[version - 2].split(',');
    const pos: number[] = [];
    for (const p of parts) {
      pos.push(Number(p));
    }
    const last = pos[pos.length - 1];
    for (const r of pos) {
      for (const c of pos) {
        if ((r === 6 && c === 6) || (r === 6 && c === last) || (r === last && c === 6)) {
          continue;
        }
        for (let dr = -2; dr <= 2; dr++) {
          for (let dc = -2; dc <= 2; dc++) {
            g.set(r + dr, c + dc, Math.max(Math.abs(dr), Math.abs(dc)) !== 1);
          }
        }
      }
    }
  }

  // Timing patterns.
  for (let i = 8; i < count - 8; i++) {
    if (g.get(i, 6) === null) {
      g.set(i, 6, i % 2 === 0);
    }
    if (g.get(6, i) === null) {
      g.set(6, i, i % 2 === 0);
    }
  }

  // Version info (v >= 7).
  if (version >= 7) {
    const vbits = bchVersion(version);
    for (let i = 0; i < 18; i++) {
      const mod = ((vbits >> i) & 1) === 1;
      g.set(Math.floor(i / 3), i % 3 + count - 8 - 3, mod);
      g.set(i % 3 + count - 8 - 3, Math.floor(i / 3), mod);
    }
  }

  // Format info (written before data placement so those cells are reserved).
  const bits = bchFormat(mask); // M level = 0 -> data = (0 << 3) | mask
  for (let i = 0; i < 15; i++) {
    const mod = ((bits >> i) & 1) === 1;
    if (i < 6) {
      g.set(i, 8, mod);
    } else if (i < 8) {
      g.set(i + 1, 8, mod);
    } else {
      g.set(count - 15 + i, 8, mod);
    }
  }
  for (let i = 0; i < 15; i++) {
    const mod = ((bits >> i) & 1) === 1;
    if (i < 8) {
      g.set(8, count - i - 1, mod);
    } else if (i < 9) {
      g.set(8, 15 - i - 1 + 1, mod);
    } else {
      g.set(8, 15 - i - 1, mod);
    }
  }
  g.set(count - 8, 8, true); // dark module

  // Data placement (zigzag from bottom-right, skipping function cells).
  const fn = maskFn(mask);
  let inc = -1;
  let row = count - 1;
  let bitIndex = 7;
  let byteIndex = 0;
  for (let col = count - 1; col > 0; col -= 2) {
    if (col === 6) {
      col -= 1;
    }
    for (;;) {
      for (let c = 0; c < 2; c++) {
        if (g.get(row, col - c) === null) {
          let dark = false;
          if (byteIndex < codewords.length) {
            dark = ((codewords[byteIndex] >>> bitIndex) & 1) === 1;
          }
          if (fn(row, col - c)) {
            dark = !dark;
          }
          g.set(row, col - c, dark);
          bitIndex--;
          if (bitIndex === -1) {
            byteIndex++;
            bitIndex = 7;
          }
        }
      }
      row += inc;
      if (row < 0 || count <= row) {
        row -= inc;
        inc = -inc;
        break;
      }
    }
  }

  const result = new QrMatrix(count);
  for (let i = 0; i < count; i++) {
    for (let j = 0; j < count; j++) {
      const v = g.get(i, j);
      result.set(i, j, v === true);
    }
  }
  return result;
}

function penalty(m: QrMatrix): number {
  const count = m.size;
  let score = 0;
  // N1: runs of same color >= 5 in rows and columns.
  for (let i = 0; i < count; i++) {
    let runRow = 1;
    let runCol = 1;
    for (let j = 1; j < count; j++) {
      if (m.isDark(i, j) === m.isDark(i, j - 1)) {
        runRow++;
      } else {
        if (runRow >= 5) {
          score += runRow - 2;
        }
        runRow = 1;
      }
      if (m.isDark(j, i) === m.isDark(j - 1, i)) {
        runCol++;
      } else {
        if (runCol >= 5) {
          score += runCol - 2;
        }
        runCol = 1;
      }
    }
    if (runRow >= 5) {
      score += runRow - 2;
    }
    if (runCol >= 5) {
      score += runCol - 2;
    }
  }
  // N2: 2x2 blocks of same color.
  for (let i = 0; i < count - 1; i++) {
    for (let j = 0; j < count - 1; j++) {
      if (m.isDark(i, j) === m.isDark(i, j + 1) && m.isDark(i, j) === m.isDark(i + 1, j)
        && m.isDark(i, j) === m.isDark(i + 1, j + 1)) {
        score += 3;
      }
    }
  }
  // N3: 1011101 preceded/followed by 4 light modules (boundary counts as light).
  const n3Count = (seq: boolean[]): number => {
    let cnt = 0;
    const findFrom = (from: number): number => {
      for (let s = from; s + 7 <= seq.length; s++) {
        let match = true;
        const pat = [true, false, true, true, true, false, true];
        for (let k = 0; k < 7; k++) {
          if (seq[s + k] !== pat[k]) {
            match = false;
            break;
          }
        }
        if (match) {
          return s;
        }
      }
      return -1;
    };
    let idx = findFrom(0);
    while (idx !== -1) {
      let offset = idx + 7;
      let leftLight = idx === 0;
      if (idx > 0) {
        leftLight = true;
        for (let k = Math.max(0, idx - 4); k < idx; k++) {
          if (seq[k]) {
            leftLight = false;
            break;
          }
        }
      }
      let rightLight = idx === seq.length - 7;
      if (!rightLight) {
        rightLight = true;
        for (let k = idx + 7; k < Math.min(seq.length, idx + 11); k++) {
          if (seq[k]) {
            rightLight = false;
            break;
          }
        }
      }
      if (idx === 0 || idx === seq.length - 7 || leftLight || rightLight) {
        cnt += 40;
      } else {
        offset = idx + 4;
      }
      idx = findFrom(offset);
    }
    return cnt;
  };
  for (let i = 0; i < count; i++) {
    const row: boolean[] = [];
    const col: boolean[] = [];
    for (let j = 0; j < count; j++) {
      row.push(m.isDark(i, j));
      col.push(m.isDark(j, i));
    }
    score += n3Count(row);
    score += n3Count(col);
  }
  // N4: dark module proportion deviation.
  let dark = 0;
  for (let i = 0; i < count; i++) {
    for (let j = 0; j < count; j++) {
      if (m.isDark(i, j)) {
        dark++;
      }
    }
  }
  const percent = (dark * 100) / (count * count);
  score += 10 * Math.floor(Math.abs(percent - 50) / 5);
  return score;
}

// Mask evaluation runs on the symbol with format/version cells as light.
function zeroFormatAndVersion(m: QrMatrix, version: number): void {
  const count = m.size;
  for (let i = 0; i < 15; i++) {
    if (i < 6) {
      m.set(i, 8, false);
    } else if (i < 8) {
      m.set(i + 1, 8, false);
    } else {
      m.set(count - 15 + i, 8, false);
    }
  }
  for (let i = 0; i < 15; i++) {
    if (i < 8) {
      m.set(8, count - i - 1, false);
    } else if (i < 9) {
      m.set(8, 15 - i - 1 + 1, false);
    } else {
      m.set(8, 15 - i - 1, false);
    }
  }
  m.set(count - 8, 8, false);
  if (version >= 7) {
    for (let i = 0; i < 18; i++) {
      m.set(Math.floor(i / 3), i % 3 + count - 8 - 3, false);
      m.set(i % 3 + count - 8 - 3, Math.floor(i / 3), false);
    }
  }
}

initGfTables();

export class QrEncodeResult {
  readonly version: number;
  readonly mask: number;
  readonly matrix: QrMatrix;

  constructor(version: number, mask: number, matrix: QrMatrix) {
    this.version = version;
    this.mask = mask;
    this.matrix = matrix;
  }
}

export function encodeQr(text: string, forcedMask: number = -1): QrEncodeResult {
  const bytes = utf8Encode(text);
  const version = selectVersion(bytes.length, 10);
  if (version < 0) {
    throw new Error(`QR payload too large for version 10 (max 213 bytes, got ${bytes.length})`);
  }
  const codewords = buildCodewords(bytes, version);
  let mask = forcedMask;
  if (mask < 0 || mask > 7) {
    let best = Infinity;
    mask = 0;
    for (let k = 0; k < 8; k++) {
      const m = buildMatrix(version, codewords, k);
      zeroFormatAndVersion(m, version);
      const s = penalty(m);
      if (s < best) {
        best = s;
        mask = k;
      }
    }
  }
  return new QrEncodeResult(version, mask, buildMatrix(version, codewords, mask));
}
