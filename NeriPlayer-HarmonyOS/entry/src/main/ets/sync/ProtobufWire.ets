// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Protobuf wire-format reading primitives for the sync binary channel.
 *
 * kotlinx.serialization.protobuf 1.11.0 semantics (verified against the
 * Android SyncDataSerializer usage — see PORTING_EXECUTION_PLAN.md M5.2b):
 *   - int32/int64/bool/enum all use unsigned varints (no zigzag); negative
 *     64-bit values occupy 10 bytes as two's-complement varints
 *   - repeated fields are never packed in this schema (each element gets its
 *     own tag), and unknown field numbers are skipped silently
 *   - a known field number with a mismatched wire type is a decode failure —
 *     this is what makes the legacy schema fallback trigger on old backups
 *     (legacy SyncSong tag 8 is a varint addedAt, current tag 8 is a string
 *     mediaUri)
 *
 * int64 fidelity: ids are read as BigInt so values beyond 2^53 survive; call
 * sites convert through int64NumberValue()/idFieldText() helpers that mirror
 * the JSON codec's exact-number / decimal-text split.
 */

export const WIRE_VARINT: number = 0;
export const WIRE_FIXED64: number = 1;
export const WIRE_LEN: number = 2;
export const WIRE_START_GROUP: number = 3;
export const WIRE_END_GROUP: number = 4;
export const WIRE_FIXED32: number = 5;

const VARINT_MAX_BYTES: number = 10;
const SAFE_INTEGER_LIMIT: bigint = 9007199254740991n; // 2^53 - 1
const TWO_63: bigint = 1n << 63n;
const TWO_64: bigint = 1n << 64n;
const TWO_31: number = 2147483648;

/** Two's-complement interpretation of an unsigned 64-bit varint. */
export function toSignedInt64(value: bigint): bigint {
  return value >= TWO_63 ? value - TWO_64 : value;
}

/** Number view of a signed int64 (lossy beyond 2^53, like Kotlin's `.toDouble()`). */
export function int64NumberValue(value: bigint): number {
  return Number(toSignedInt64(value));
}

/** Wire-fidelity decimal text for ids beyond 2^53; '' when the number is exact. */
export function idFieldText(value: bigint): string {
  const signed = toSignedInt64(value);
  const magnitude = signed < 0n ? -signed : signed;
  return magnitude > SAFE_INTEGER_LIMIT ? signed.toString() : '';
}

/** Low 32 bits of a varint sign-extended, matching Kotlin's `.toInt()`. */
export function int32FromVarint(value: bigint): number {
  const low = Number(value & 0xFFFFFFFFn);
  return low >= TWO_31 ? low - 4294967296 : low;
}

export class ProtoReader {
  private readonly bytes: Uint8Array;
  private pos: number;
  private readonly end: number;

  constructor(bytes: Uint8Array, start: number, end: number) {
    this.bytes = bytes;
    this.pos = start;
    this.end = end;
  }

  static over(bytes: Uint8Array): ProtoReader {
    return new ProtoReader(bytes, 0, bytes.length);
  }

  atEnd(): boolean {
    return this.pos >= this.end;
  }

  /**
   * Reads the next field key. Returns (fieldNumber << 3) | wireType, or -1 on
   * malformed input (field number 0 / truncated varint / over-long tag).
   */
  readTag(): number {
    const raw = this.readVarint();
    if (raw === null) {
      return -1;
    }
    if (raw > 0xFFFFFFFFn) {
      return -1;
    }
    const tag = Number(raw);
    if ((tag >>> 3) === 0) {
      return -1;
    }
    return tag;
  }

  /** Unsigned varint as BigInt; null when truncated or longer than 10 bytes. */
  readVarint(): bigint | null {
    let result = 0n;
    for (let i = 0; i < VARINT_MAX_BYTES; i++) {
      if (this.pos >= this.end) {
        return null;
      }
      const b = this.bytes[this.pos++];
      result |= BigInt(b & 0x7F) << BigInt(i * 7);
      if ((b & 0x80) === 0) {
        return result;
      }
    }
    return null;
  }

  /** Length-delimited payload as a zero-copy view range [start, end). */
  readLengthRange(): ProtoReader | null {
    const length = this.readVarint();
    if (length === null || length > BigInt(this.end - this.pos)) {
      return null;
    }
    const count = Number(length);
    const reader = new ProtoReader(this.bytes, this.pos, this.pos + count);
    this.pos += count;
    return reader;
  }

  readString(): string | null {
    const range = this.readLengthRange();
    if (range === null) {
      return null;
    }
    return utf8DecodeRange(this.bytes, range.startOffset(), range.endOffset());
  }

  /** Decodes this reader's whole remaining range as one UTF-8 string. */
  payloadAsString(): string {
    return utf8DecodeRange(this.bytes, this.pos, this.end);
  }

  /** Skips a field payload of the given wire type; false on malformed input. */
  skip(wireType: number): boolean {
    if (wireType === WIRE_VARINT) {
      return this.readVarint() !== null;
    }
    if (wireType === WIRE_FIXED64) {
      if (this.end - this.pos < 8) {
        return false;
      }
      this.pos += 8;
      return true;
    }
    if (wireType === WIRE_FIXED32) {
      if (this.end - this.pos < 4) {
        return false;
      }
      this.pos += 4;
      return true;
    }
    if (wireType === WIRE_LEN) {
      return this.readLengthRange() !== null;
    }
    if (wireType === WIRE_START_GROUP) {
      // Groups are not produced by this schema; consume until the matching
      // END_GROUP in a lenient way (kotlinx would never emit nested groups).
      while (true) {
        const tag = this.readTag();
        if (tag === -1) {
          return false;
        }
        const nestedType = tag & 0x07;
        if (nestedType === WIRE_END_GROUP) {
          return true;
        }
        if (!this.skip(nestedType)) {
          return false;
        }
      }
    }
    return false; // END_GROUP without START_GROUP, or unknown wire type
  }

  startOffset(): number {
    return this.pos;
  }

  endOffset(): number {
    return this.end;
  }
}

// ---------------------------------------------------------------------------
// UTF-8 decoding over a byte range (replacement chars for invalid sequences,
// matching Kotlin's String(bytes, Charsets.UTF_8) tolerance)
// ---------------------------------------------------------------------------

function utf8DecodeRange(bytes: Uint8Array, start: number, end: number): string {
  let out = '';
  let i = start;
  while (i < end) {
    const b0 = bytes[i];
    if (b0 < 0x80) {
      out += String.fromCharCode(b0);
      i += 1;
    } else if (b0 < 0xC0) {
      out += '\uFFFD'; // stray continuation byte
      i += 1;
    } else if (b0 < 0xE0) {
      if (i + 1 < end && isContinuation(bytes[i + 1])) {
        out += String.fromCharCode(((b0 & 0x1F) << 6) | (bytes[i + 1] & 0x3F));
        i += 2;
      } else {
        out += '\uFFFD';
        i += 1;
      }
    } else if (b0 < 0xF0) {
      if (i + 2 < end && isContinuation(bytes[i + 1]) && isContinuation(bytes[i + 2])) {
        out += String.fromCharCode(((b0 & 0x0F) << 12) | ((bytes[i + 1] & 0x3F) << 6) | (bytes[i + 2] & 0x3F));
        i += 3;
      } else {
        out += '\uFFFD';
        i += 1;
      }
    } else {
      if (i + 3 < end && isContinuation(bytes[i + 1]) && isContinuation(bytes[i + 2]) && isContinuation(bytes[i + 3])) {
        const cp = ((b0 & 0x07) << 18) | ((bytes[i + 1] & 0x3F) << 12) |
          ((bytes[i + 2] & 0x3F) << 6) | (bytes[i + 3] & 0x3F);
        const offset = cp - 0x10000;
        out += String.fromCharCode(0xD800 + (offset >> 10), 0xDC00 + (offset & 0x3FF));
        i += 4;
      } else {
        out += '\uFFFD';
        i += 1;
      }
    }
  }
  return out;
}

function isContinuation(b: number): boolean {
  return (b & 0xC0) === 0x80;
}
