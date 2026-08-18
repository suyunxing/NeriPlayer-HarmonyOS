/**
 * Port of data/sync/github/SyncDataSerializer.kt (JSON branch) plus the
 * read-both format sniffing.
 *
 * kotlinx JSON semantics reproduced here by hand:
 *   encodeDefaults=true   → every non-null field is written, even when equal
 *                           to its default (0 / false / "" / []).
 *   explicitNulls=false   → null-valued nullable fields are omitted.
 *   ignoreUnknownKeys     → unknown object keys are skipped on read.
 *   coerceInputValues     → invalid enum values fall back to the default.
 *
 * Int64 fidelity: Android ids (YTM/Bilibili SHA-256 ids) exceed JS number
 * precision. The hand-written parser keeps such integer literals as their
 * original decimal text (JsonValue string) and the model stores it in the
 * syncIdText wire-fidelity fields, so stable keys and re-serialization stay
 * byte-identical with the Android endpoint.
 */
import {
  SyncData,
  SyncPlaylist,
  SyncSong,
  SyncRecentPlay,
  SyncRecentPlayDeletion,
  SyncPlaylistSongDeletion,
  SyncFavoritePlaylist,
  SyncLogEntry,
  SyncAction,
  SyncCausalToken,
  SyncTrackStat,
  SyncPlaybackStatBucket,
  SyncPlaybackCounterShard,
  normalizedSyncCausalTokens
} from './SyncModels';

export const MAX_JSON_BYTES: number = 8 * 1024 * 1024;
export const MAX_COMPRESSED_BYTES: number = 12 * 1024 * 1024;
export const MAX_DECOMPRESSED_BYTES: number = 16 * 1024 * 1024;

export const RAW_BINARY_FILE_NAME: string = 'backup-raw.bin';
export const LEGACY_BINARY_FILE_NAME: string = 'backup.bin';
export const JSON_FILE_NAME: string = 'backup.json';

export function getSyncFileName(useDataSaver: boolean): string {
  return useDataSaver ? RAW_BINARY_FILE_NAME : JSON_FILE_NAME;
}

export function getReadFallbackFileNames(useDataSaver: boolean): string[] {
  return useDataSaver
    ? [LEGACY_BINARY_FILE_NAME, JSON_FILE_NAME]
    : [RAW_BINARY_FILE_NAME, LEGACY_BINARY_FILE_NAME];
}

export function isBinarySyncFileName(fileName: string): boolean {
  return fileName.endsWith('.bin');
}

const SAFE_INTEGER_LIMIT: bigint = 9007199254740991n; // 2^53 - 1

// ---------------------------------------------------------------------------
// UTF-8 codec (pure ArkTS so unit tests run without @ohos.util)
// ---------------------------------------------------------------------------

export function utf8Decode(bytes: Uint8Array): string {
  let out = '';
  let i = 0;
  while (i < bytes.length) {
    const b0 = bytes[i];
    if (b0 < 0x80) {
      out += String.fromCharCode(b0);
      i += 1;
    } else if (b0 < 0xE0) {
      const cp = ((b0 & 0x1F) << 6) | (bytes[i + 1] & 0x3F);
      out += String.fromCharCode(cp);
      i += 2;
    } else if (b0 < 0xF0) {
      const cp = ((b0 & 0x0F) << 12) | ((bytes[i + 1] & 0x3F) << 6) | (bytes[i + 2] & 0x3F);
      out += String.fromCharCode(cp);
      i += 3;
    } else {
      const cp = ((b0 & 0x07) << 18) | ((bytes[i + 1] & 0x3F) << 12) |
        ((bytes[i + 2] & 0x3F) << 6) | (bytes[i + 3] & 0x3F);
      // Encode as a UTF-16 surrogate pair.
      const offset = cp - 0x10000;
      out += String.fromCharCode(0xD800 + (offset >> 10), 0xDC00 + (offset & 0x3FF));
      i += 4;
    }
  }
  return out;
}

export function utf8EncodeText(text: string): Uint8Array {
  const bytes: number[] = [];
  for (let i = 0; i < text.length; i++) {
    const code = text.charCodeAt(i);
    if (code < 0x80) {
      bytes.push(code);
    } else if (code < 0x800) {
      bytes.push(0xC0 | (code >> 6), 0x80 | (code & 0x3F));
    } else if (code >= 0xD800 && code <= 0xDBFF && i + 1 < text.length) {
      const low = text.charCodeAt(i + 1);
      const cp = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00);
      bytes.push(
        0xF0 | (cp >> 18),
        0x80 | ((cp >> 12) & 0x3F),
        0x80 | ((cp >> 6) & 0x3F),
        0x80 | (cp & 0x3F)
      );
      i++;
    } else {
      bytes.push(0xE0 | (code >> 12), 0x80 | ((code >> 6) & 0x3F), 0x80 | (code & 0x3F));
    }
  }
  return new Uint8Array(bytes);
}

// ---------------------------------------------------------------------------
// Hand-written JSON parser (integer literals beyond 2^53 kept as text)
// ---------------------------------------------------------------------------

export type JsonValue = null | boolean | number | string | JsonValue[] | Map<string, JsonValue>;

const MAX_JSON_DEPTH: number = 200;

class JsonParser {
  private readonly text: string;
  private pos: number = 0;

  constructor(text: string) {
    this.text = text;
  }

  parseDocument(): JsonValue | null {
    this.skipWhitespace();
    if (this.pos >= this.text.length) {
      return null;
    }
    const value = this.parseValue(0);
    if (value === undefined) {
      return null;
    }
    this.skipWhitespace();
    if (this.pos !== this.text.length) {
      return null;
    }
    return value;
  }

  private skipWhitespace(): void {
    while (this.pos < this.text.length) {
      const ch = this.text.charAt(this.pos);
      if (ch === ' ' || ch === '\t' || ch === '\n' || ch === '\r') {
        this.pos++;
      } else {
        break;
      }
    }
  }

  private parseValue(depth: number): JsonValue | undefined {
    if (depth > MAX_JSON_DEPTH) {
      return undefined;
    }
    this.skipWhitespace();
    if (this.pos >= this.text.length) {
      return undefined;
    }
    const ch = this.text.charAt(this.pos);
    if (ch === '{') {
      return this.parseObject(depth);
    }
    if (ch === '[') {
      return this.parseArray(depth);
    }
    if (ch === '"') {
      return this.parseString();
    }
    if (ch === 't') {
      return this.parseKeyword('true', true);
    }
    if (ch === 'f') {
      return this.parseKeyword('false', false);
    }
    if (ch === 'n') {
      return this.parseKeyword('null', null);
    }
    if (ch === '-' || (ch >= '0' && ch <= '9')) {
      return this.parseNumber();
    }
    return undefined;
  }

  private parseKeyword(keyword: string, value: JsonValue): JsonValue | undefined {
    if (this.text.startsWith(keyword, this.pos)) {
      this.pos += keyword.length;
      return value;
    }
    return undefined;
  }

  private parseObject(depth: number): Map<string, JsonValue> | undefined {
    this.pos++; // consume '{'
    const map = new Map<string, JsonValue>();
    this.skipWhitespace();
    if (this.pos < this.text.length && this.text.charAt(this.pos) === '}') {
      this.pos++;
      return map;
    }
    while (this.pos < this.text.length) {
      this.skipWhitespace();
      if (this.text.charAt(this.pos) !== '"') {
        return undefined;
      }
      const key = this.parseString();
      if (key === undefined) {
        return undefined;
      }
      this.skipWhitespace();
      if (this.text.charAt(this.pos) !== ':') {
        return undefined;
      }
      this.pos++;
      const value = this.parseValue(depth + 1);
      if (value === undefined) {
        return undefined;
      }
      map.set(key, value);
      this.skipWhitespace();
      const next = this.text.charAt(this.pos);
      if (next === ',') {
        this.pos++;
        continue;
      }
      if (next === '}') {
        this.pos++;
        return map;
      }
      return undefined;
    }
    return undefined;
  }

  private parseArray(depth: number): JsonValue[] | undefined {
    this.pos++; // consume '['
    const list: JsonValue[] = [];
    this.skipWhitespace();
    if (this.pos < this.text.length && this.text.charAt(this.pos) === ']') {
      this.pos++;
      return list;
    }
    while (this.pos < this.text.length) {
      const value = this.parseValue(depth + 1);
      if (value === undefined) {
        return undefined;
      }
      list.push(value);
      this.skipWhitespace();
      const next = this.text.charAt(this.pos);
      if (next === ',') {
        this.pos++;
        continue;
      }
      if (next === ']') {
        this.pos++;
        return list;
      }
      return undefined;
    }
    return undefined;
  }

  private parseString(): string | undefined {
    this.pos++; // consume '"'
    let out = '';
    while (this.pos < this.text.length) {
      const ch = this.text.charAt(this.pos);
      if (ch === '"') {
        this.pos++;
        return out;
      }
      if (ch === '\\') {
        this.pos++;
        if (this.pos >= this.text.length) {
          return undefined;
        }
        const esc = this.text.charAt(this.pos);
        if (esc === 'u') {
          if (this.pos + 4 >= this.text.length) {
            return undefined;
          }
          const hex = this.text.substring(this.pos + 1, this.pos + 5);
          const code = parseInt(hex, 16);
          if (Number.isNaN(code)) {
            return undefined;
          }
          out += String.fromCharCode(code);
          this.pos += 5;
        } else {
          switch (esc) {
            case '"':
              out += '"';
              break;
            case '\\':
              out += '\\';
              break;
            case '/':
              out += '/';
              break;
            case 'b':
              out += '\b';
              break;
            case 'f':
              out += '\f';
              break;
            case 'n':
              out += '\n';
              break;
            case 'r':
              out += '\r';
              break;
            case 't':
              out += '\t';
              break;
            default:
              return undefined;
          }
          this.pos++;
        }
      } else {
        out += ch;
        this.pos++;
      }
    }
    return undefined;
  }

  private parseNumber(): number | string | undefined {
    const start = this.pos;
    if (this.text.charAt(this.pos) === '-') {
      this.pos++;
    }
    while (this.pos < this.text.length) {
      const ch = this.text.charAt(this.pos);
      if (ch >= '0' && ch <= '9') {
        this.pos++;
      } else {
        break;
      }
    }
    let isInteger = true;
    if (this.text.charAt(this.pos) === '.') {
      isInteger = false;
      this.pos++;
      while (this.pos < this.text.length) {
        const ch = this.text.charAt(this.pos);
        if (ch >= '0' && ch <= '9') {
          this.pos++;
        } else {
          break;
        }
      }
    }
    const expCh = this.text.charAt(this.pos);
    if (expCh === 'e' || expCh === 'E') {
      isInteger = false;
      this.pos++;
      const signCh = this.text.charAt(this.pos);
      if (signCh === '+' || signCh === '-') {
        this.pos++;
      }
      while (this.pos < this.text.length) {
        const ch = this.text.charAt(this.pos);
        if (ch >= '0' && ch <= '9') {
          this.pos++;
        } else {
          break;
        }
      }
    }
    const token = this.text.substring(start, this.pos);
    if (token.length === 0 || token === '-') {
      return undefined;
    }
    if (isInteger) {
      const magnitude = BigInt(token);
      if (magnitude > SAFE_INTEGER_LIMIT || magnitude < -SAFE_INTEGER_LIMIT) {
        return token;
      }
    }
    const value = Number(token);
    return Number.isFinite(value) ? value : undefined;
  }
}

export function parseJsonText(text: string): JsonValue | null {
  return new JsonParser(text).parseDocument();
}

// ---------------------------------------------------------------------------
// Field readers (typed accessors with kotlinx-like tolerance)
// ---------------------------------------------------------------------------

function asObject(node: JsonValue | undefined): Map<string, JsonValue> | null {
  if (node instanceof Map) {
    return node;
  }
  return null;
}

function asArray(node: JsonValue | undefined): JsonValue[] | null {
  if (node instanceof Array) {
    return node;
  }
  return null;
}

function readStringField(obj: Map<string, JsonValue>, key: string, defaultValue: string): string {
  const node = obj.get(key);
  if (typeof node === 'string') {
    return node;
  }
  if (typeof node === 'number') {
    return `${node}`;
  }
  return defaultValue;
}

function readStringOrNullField(obj: Map<string, JsonValue>, key: string): string | null {
  const node = obj.get(key);
  if (typeof node === 'string') {
    return node;
  }
  if (typeof node === 'number') {
    return `${node}`;
  }
  return null;
}

function readNumberField(obj: Map<string, JsonValue>, key: string, defaultValue: number): number {
  const node = obj.get(key);
  if (typeof node === 'number') {
    return node;
  }
  if (typeof node === 'string') {
    const value = Number(node);
    if (Number.isFinite(value)) {
      return value;
    }
  }
  return defaultValue;
}

function readNumberOrNullField(obj: Map<string, JsonValue>, key: string): number | null {
  const node = obj.get(key);
  if (typeof node === 'number') {
    return node;
  }
  if (typeof node === 'string') {
    const value = Number(node);
    if (Number.isFinite(value)) {
      return value;
    }
  }
  return null;
}

/**
 * kotlinx parity: a present-but-non-array collection field is a hard decode
 * failure (returns null), a missing one defaults to [].
 */
function readArrayField(obj: Map<string, JsonValue>, key: string): JsonValue[] | null {
  const node = obj.get(key);
  if (node === undefined || node === null) {
    return [];
  }
  if (node instanceof Array) {
    return node;
  }
  return null;
}

function readBooleanField(obj: Map<string, JsonValue>, key: string, defaultValue: boolean): boolean {
  const node = obj.get(key);
  if (typeof node === 'boolean') {
    return node;
  }
  return defaultValue;
}

/** Approximate numeric id for a possibly out-of-range integer literal. */
function readIdNumberField(obj: Map<string, JsonValue>, key: string, defaultValue: number): number {
  const node = obj.get(key);
  if (typeof node === 'number') {
    return node;
  }
  if (typeof node === 'string') {
    const value = Number(node);
    return Number.isFinite(value) ? value : defaultValue;
  }
  return defaultValue;
}

/** Original decimal text for out-of-range ids; '' when the id is exact. */
function readIdTextField(obj: Map<string, JsonValue>, key: string): string {
  const node = obj.get(key);
  if (typeof node === 'string') {
    return node;
  }
  return '';
}

// ---------------------------------------------------------------------------
// Writer (encodeDefaults=true, explicitNulls=false)
// ---------------------------------------------------------------------------

class JsonWriter {
  private parts: string[] = [];

  raw(value: string): void {
    this.parts.push(value);
  }

  key(name: string): void {
    this.parts.push(`${escapeJsonString(name)}:`);
  }

  stringValue(value: string): void {
    this.parts.push(escapeJsonString(value));
  }

  numberValue(value: number): void {
    this.parts.push(`${value}`);
  }

  booleanValue(value: boolean): void {
    this.parts.push(value ? 'true' : 'false');
  }

  nullValue(): void {
    this.parts.push('null');
  }

  build(): string {
    return this.parts.join('');
  }
}

export function escapeJsonString(value: string): string {
  let out = '"';
  for (let i = 0; i < value.length; i++) {
    const code = value.charCodeAt(i);
    if (code === 0x22) {
      out += '\\"';
    } else if (code === 0x5C) {
      out += '\\\\';
    } else if (code === 0x08) {
      out += '\\b';
    } else if (code === 0x0C) {
      out += '\\f';
    } else if (code === 0x0A) {
      out += '\\n';
    } else if (code === 0x0D) {
      out += '\\r';
    } else if (code === 0x09) {
      out += '\\t';
    } else if (code < 0x20) {
      out += `\\u${code.toString(16).padStart(4, '0')}`;
    } else {
      out += value.charAt(i);
    }
  }
  return `${out}"`;
}

function field(writer: JsonWriter, name: string, write: (w: JsonWriter) => void, first: boolean): boolean {
  if (!first) {
    writer.raw(',');
  }
  writer.key(name);
  write(writer);
  return false;
}

// ---------------------------------------------------------------------------
// Model writers
// ---------------------------------------------------------------------------

function writeIdValue(writer: JsonWriter, id: number, idText: string): void {
  if (idText.length > 0) {
    writer.stringValue(idText);
  } else {
    writer.numberValue(id);
  }
}

function writeCausalToken(writer: JsonWriter, token: SyncCausalToken): void {
  writer.raw('{');
  let first = true;
  first = field(writer, 'deviceId', (w: JsonWriter): void => {
    w.stringValue(token.deviceId);
  }, first);
  first = field(writer, 'counter', (w: JsonWriter): void => {
    w.numberValue(token.counter);
  }, first);
  writer.raw('}');
}

function writeTokenArray(writer: JsonWriter, tokens: SyncCausalToken[]): void {
  writer.raw('[');
  for (let i = 0; i < tokens.length; i++) {
    if (i > 0) {
      writer.raw(',');
    }
    writeCausalToken(writer, tokens[i]);
  }
  writer.raw(']');
}

function writeSyncSong(writer: JsonWriter, song: SyncSong): void {
  writer.raw('{');
  let first = true;
  first = field(writer, 'id', (w: JsonWriter): void => {
    writeIdValue(w, song.id, song.syncIdText);
  }, first);
  first = field(writer, 'name', (w: JsonWriter): void => {
    w.stringValue(song.name);
  }, first);
  first = field(writer, 'artist', (w: JsonWriter): void => {
    w.stringValue(song.artist);
  }, first);
  first = field(writer, 'album', (w: JsonWriter): void => {
    w.stringValue(song.album);
  }, first);
  first = field(writer, 'albumId', (w: JsonWriter): void => {
    w.numberValue(song.albumId);
  }, first);
  first = field(writer, 'durationMs', (w: JsonWriter): void => {
    w.numberValue(song.durationMs);
  }, first);
  if (song.coverUrl !== null) {
    first = field(writer, 'coverUrl', (w: JsonWriter): void => {
      w.stringValue(song.coverUrl as string);
    }, first);
  }
  if (song.mediaUri !== null) {
    first = field(writer, 'mediaUri', (w: JsonWriter): void => {
      w.stringValue(song.mediaUri as string);
    }, first);
  }
  first = field(writer, 'addedAt', (w: JsonWriter): void => {
    w.numberValue(song.addedAt);
  }, first);
  if (song.matchedLyric !== null) {
    first = field(writer, 'matchedLyric', (w: JsonWriter): void => {
      w.stringValue(song.matchedLyric as string);
    }, first);
  }
  if (song.matchedTranslatedLyric !== null) {
    first = field(writer, 'matchedTranslatedLyric', (w: JsonWriter): void => {
      w.stringValue(song.matchedTranslatedLyric as string);
    }, first);
  }
  if (song.matchedLyricSource !== null) {
    first = field(writer, 'matchedLyricSource', (w: JsonWriter): void => {
      w.stringValue(song.matchedLyricSource as string);
    }, first);
  }
  if (song.matchedSongId !== null) {
    first = field(writer, 'matchedSongId', (w: JsonWriter): void => {
      w.stringValue(song.matchedSongId as string);
    }, first);
  }
  first = field(writer, 'userLyricOffsetMs', (w: JsonWriter): void => {
    w.numberValue(song.userLyricOffsetMs);
  }, first);
  if (song.customCoverUrl !== null) {
    first = field(writer, 'customCoverUrl', (w: JsonWriter): void => {
      w.stringValue(song.customCoverUrl as string);
    }, first);
  }
  if (song.customName !== null) {
    first = field(writer, 'customName', (w: JsonWriter): void => {
      w.stringValue(song.customName as string);
    }, first);
  }
  if (song.customArtist !== null) {
    first = field(writer, 'customArtist', (w: JsonWriter): void => {
      w.stringValue(song.customArtist as string);
    }, first);
  }
  if (song.originalName !== null) {
    first = field(writer, 'originalName', (w: JsonWriter): void => {
      w.stringValue(song.originalName as string);
    }, first);
  }
  if (song.originalArtist !== null) {
    first = field(writer, 'originalArtist', (w: JsonWriter): void => {
      w.stringValue(song.originalArtist as string);
    }, first);
  }
  if (song.originalCoverUrl !== null) {
    first = field(writer, 'originalCoverUrl', (w: JsonWriter): void => {
      w.stringValue(song.originalCoverUrl as string);
    }, first);
  }
  if (song.originalLyric !== null) {
    first = field(writer, 'originalLyric', (w: JsonWriter): void => {
      w.stringValue(song.originalLyric as string);
    }, first);
  }
  if (song.originalTranslatedLyric !== null) {
    first = field(writer, 'originalTranslatedLyric', (w: JsonWriter): void => {
      w.stringValue(song.originalTranslatedLyric as string);
    }, first);
  }
  if (song.channelId !== null) {
    first = field(writer, 'channelId', (w: JsonWriter): void => {
      w.stringValue(song.channelId as string);
    }, first);
  }
  if (song.audioId !== null) {
    first = field(writer, 'audioId', (w: JsonWriter): void => {
      w.stringValue(song.audioId as string);
    }, first);
  }
  if (song.subAudioId !== null) {
    first = field(writer, 'subAudioId', (w: JsonWriter): void => {
      w.stringValue(song.subAudioId as string);
    }, first);
  }
  if (song.playlistContextId !== null) {
    first = field(writer, 'playlistContextId', (w: JsonWriter): void => {
      w.stringValue(song.playlistContextId as string);
    }, first);
  }
  first = field(writer, 'syncMembershipTokens', (w: JsonWriter): void => {
    writeTokenArray(w, song.syncMembershipTokens);
  }, first);
  first = field(writer, 'syncMetadataVersion', (w: JsonWriter): void => {
    w.numberValue(song.syncMetadataVersion);
  }, first);
  if (song.legacyAddedAt !== null) {
    first = field(writer, 'legacyAddedAt', (w: JsonWriter): void => {
      w.numberValue(song.legacyAddedAt as number);
    }, first);
  }
  writer.raw('}');
}

function writeSyncPlaylist(writer: JsonWriter, playlist: SyncPlaylist): void {
  writer.raw('{');
  let first = true;
  first = field(writer, 'id', (w: JsonWriter): void => {
    w.numberValue(playlist.id);
  }, first);
  first = field(writer, 'name', (w: JsonWriter): void => {
    w.stringValue(playlist.name);
  }, first);
  first = field(writer, 'songs', (w: JsonWriter): void => {
    w.raw('[');
    for (let i = 0; i < playlist.songs.length; i++) {
      if (i > 0) {
        w.raw(',');
      }
      writeSyncSong(w, playlist.songs[i]);
    }
    w.raw(']');
  }, first);
  first = field(writer, 'createdAt', (w: JsonWriter): void => {
    w.numberValue(playlist.createdAt);
  }, first);
  first = field(writer, 'modifiedAt', (w: JsonWriter): void => {
    w.numberValue(playlist.modifiedAt);
  }, first);
  first = field(writer, 'isDeleted', (w: JsonWriter): void => {
    w.booleanValue(playlist.isDeleted);
  }, first);
  first = field(writer, 'songOrderVersion', (w: JsonWriter): void => {
    w.numberValue(playlist.songOrderVersion);
  }, first);
  writer.raw('}');
}

function writeRecentPlay(writer: JsonWriter, entry: SyncRecentPlay): void {
  writer.raw('{');
  let first = true;
  first = field(writer, 'songId', (w: JsonWriter): void => {
    writeIdValue(w, entry.songId, '');
  }, first);
  first = field(writer, 'song', (w: JsonWriter): void => {
    writeSyncSong(w, entry.song);
  }, first);
  first = field(writer, 'playedAt', (w: JsonWriter): void => {
    w.numberValue(entry.playedAt);
  }, first);
  first = field(writer, 'deviceId', (w: JsonWriter): void => {
    w.stringValue(entry.deviceId);
  }, first);
  first = field(writer, 'resumePositionMs', (w: JsonWriter): void => {
    w.numberValue(entry.resumePositionMs);
  }, first);
  writer.raw('}');
}

function writeRecentPlayDeletion(writer: JsonWriter, deletion: SyncRecentPlayDeletion): void {
  writer.raw('{');
  let first = true;
  first = field(writer, 'songId', (w: JsonWriter): void => {
    writeIdValue(w, deletion.songId, deletion.syncSongIdText);
  }, first);
  first = field(writer, 'album', (w: JsonWriter): void => {
    w.stringValue(deletion.album);
  }, first);
  if (deletion.mediaUri !== null) {
    first = field(writer, 'mediaUri', (w: JsonWriter): void => {
      w.stringValue(deletion.mediaUri as string);
    }, first);
  }
  first = field(writer, 'deletedAt', (w: JsonWriter): void => {
    w.numberValue(deletion.deletedAt);
  }, first);
  first = field(writer, 'deviceId', (w: JsonWriter): void => {
    w.stringValue(deletion.deviceId);
  }, first);
  writer.raw('}');
}

function writePlaylistSongDeletion(writer: JsonWriter, deletion: SyncPlaylistSongDeletion): void {
  writer.raw('{');
  let first = true;
  first = field(writer, 'playlistId', (w: JsonWriter): void => {
    w.numberValue(deletion.playlistId);
  }, first);
  first = field(writer, 'songId', (w: JsonWriter): void => {
    writeIdValue(w, deletion.songId, deletion.syncSongIdText);
  }, first);
  first = field(writer, 'album', (w: JsonWriter): void => {
    w.stringValue(deletion.album);
  }, first);
  if (deletion.mediaUri !== null) {
    first = field(writer, 'mediaUri', (w: JsonWriter): void => {
      w.stringValue(deletion.mediaUri as string);
    }, first);
  }
  first = field(writer, 'deletedAt', (w: JsonWriter): void => {
    w.numberValue(deletion.deletedAt);
  }, first);
  first = field(writer, 'deviceId', (w: JsonWriter): void => {
    w.stringValue(deletion.deviceId);
  }, first);
  first = field(writer, 'removedMembershipTokens', (w: JsonWriter): void => {
    writeTokenArray(w, deletion.removedMembershipTokens);
  }, first);
  writer.raw('}');
}

function writeFavoritePlaylist(writer: JsonWriter, favorite: SyncFavoritePlaylist): void {
  writer.raw('{');
  let first = true;
  first = field(writer, 'id', (w: JsonWriter): void => {
    w.numberValue(favorite.id);
  }, first);
  first = field(writer, 'name', (w: JsonWriter): void => {
    w.stringValue(favorite.name);
  }, first);
  if (favorite.coverUrl !== null) {
    first = field(writer, 'coverUrl', (w: JsonWriter): void => {
      w.stringValue(favorite.coverUrl as string);
    }, first);
  }
  first = field(writer, 'trackCount', (w: JsonWriter): void => {
    w.numberValue(favorite.trackCount);
  }, first);
  first = field(writer, 'source', (w: JsonWriter): void => {
    w.stringValue(favorite.source);
  }, first);
  first = field(writer, 'songs', (w: JsonWriter): void => {
    w.raw('[');
    for (let i = 0; i < favorite.songs.length; i++) {
      if (i > 0) {
        w.raw(',');
      }
      writeSyncSong(w, favorite.songs[i]);
    }
    w.raw(']');
  }, first);
  first = field(writer, 'addedTime', (w: JsonWriter): void => {
    w.numberValue(favorite.addedTime);
  }, first);
  first = field(writer, 'modifiedAt', (w: JsonWriter): void => {
    w.numberValue(favorite.modifiedAt);
  }, first);
  first = field(writer, 'isDeleted', (w: JsonWriter): void => {
    w.booleanValue(favorite.isDeleted);
  }, first);
  first = field(writer, 'sortOrder', (w: JsonWriter): void => {
    w.numberValue(favorite.sortOrder);
  }, first);
  if (favorite.browseId !== null) {
    first = field(writer, 'browseId', (w: JsonWriter): void => {
      w.stringValue(favorite.browseId as string);
    }, first);
  }
  if (favorite.playlistId !== null) {
    first = field(writer, 'playlistId', (w: JsonWriter): void => {
      w.stringValue(favorite.playlistId as string);
    }, first);
  }
  if (favorite.subtitle !== null) {
    first = field(writer, 'subtitle', (w: JsonWriter): void => {
      w.stringValue(favorite.subtitle as string);
    }, first);
  }
  writer.raw('}');
}

function syncActionName(action: SyncAction): string {
  // kotlinx JSON serializes enums by name.
  switch (action) {
    case SyncAction.DELETE_PLAYLIST:
      return 'DELETE_PLAYLIST';
    case SyncAction.RENAME_PLAYLIST:
      return 'RENAME_PLAYLIST';
    case SyncAction.ADD_SONG:
      return 'ADD_SONG';
    case SyncAction.REMOVE_SONG:
      return 'REMOVE_SONG';
    case SyncAction.REORDER_SONGS:
      return 'REORDER_SONGS';
    case SyncAction.PLAY_SONG:
      return 'PLAY_SONG';
    case SyncAction.CREATE_PLAYLIST:
    default:
      return 'CREATE_PLAYLIST';
  }
}

function parseSyncActionName(name: string): SyncAction {
  switch (name) {
    case 'DELETE_PLAYLIST':
      return SyncAction.DELETE_PLAYLIST;
    case 'RENAME_PLAYLIST':
      return SyncAction.RENAME_PLAYLIST;
    case 'ADD_SONG':
      return SyncAction.ADD_SONG;
    case 'REMOVE_SONG':
      return SyncAction.REMOVE_SONG;
    case 'REORDER_SONGS':
      return SyncAction.REORDER_SONGS;
    case 'PLAY_SONG':
      return SyncAction.PLAY_SONG;
    default:
      return SyncAction.CREATE_PLAYLIST;
  }
}

function writeLogEntry(writer: JsonWriter, entry: SyncLogEntry): void {
  writer.raw('{');
  let first = true;
  first = field(writer, 'timestamp', (w: JsonWriter): void => {
    w.numberValue(entry.timestamp);
  }, first);
  first = field(writer, 'deviceId', (w: JsonWriter): void => {
    w.stringValue(entry.deviceId);
  }, first);
  first = field(writer, 'action', (w: JsonWriter): void => {
    w.stringValue(syncActionName(entry.action));
  }, first);
  if (entry.playlistId !== null) {
    first = field(writer, 'playlistId', (w: JsonWriter): void => {
      w.numberValue(entry.playlistId as number);
    }, first);
  }
  if (entry.songId !== null) {
    first = field(writer, 'songId', (w: JsonWriter): void => {
      w.numberValue(entry.songId as number);
    }, first);
  }
  if (entry.details !== null) {
    first = field(writer, 'details', (w: JsonWriter): void => {
      w.stringValue(entry.details as string);
    }, first);
  }
  writer.raw('}');
}

function writeCounterShard(writer: JsonWriter, shard: SyncPlaybackCounterShard): void {
  writer.raw('{');
  let first = true;
  first = field(writer, 'deviceId', (w: JsonWriter): void => {
    w.stringValue(shard.deviceId);
  }, first);
  first = field(writer, 'epochStartedAt', (w: JsonWriter): void => {
    w.numberValue(shard.epochStartedAt);
  }, first);
  first = field(writer, 'totalListenMs', (w: JsonWriter): void => {
    w.numberValue(shard.totalListenMs);
  }, first);
  first = field(writer, 'playCount', (w: JsonWriter): void => {
    w.numberValue(shard.playCount);
  }, first);
  first = field(writer, 'firstPlayedAt', (w: JsonWriter): void => {
    w.numberValue(shard.firstPlayedAt);
  }, first);
  first = field(writer, 'lastPlayedAt', (w: JsonWriter): void => {
    w.numberValue(shard.lastPlayedAt);
  }, first);
  writer.raw('}');
}

function writeTrackStat(writer: JsonWriter, stat: SyncTrackStat): void {
  writer.raw('{');
  let first = true;
  first = field(writer, 'identityKey', (w: JsonWriter): void => {
    w.stringValue(stat.identityKey);
  }, first);
  first = field(writer, 'name', (w: JsonWriter): void => {
    w.stringValue(stat.name);
  }, first);
  first = field(writer, 'artist', (w: JsonWriter): void => {
    w.stringValue(stat.artist);
  }, first);
  first = field(writer, 'album', (w: JsonWriter): void => {
    w.stringValue(stat.album);
  }, first);
  first = field(writer, 'totalListenMs', (w: JsonWriter): void => {
    w.numberValue(stat.totalListenMs);
  }, first);
  first = field(writer, 'playCount', (w: JsonWriter): void => {
    w.numberValue(stat.playCount);
  }, first);
  first = field(writer, 'lastPlayedAt', (w: JsonWriter): void => {
    w.numberValue(stat.lastPlayedAt);
  }, first);
  first = field(writer, 'firstPlayedAt', (w: JsonWriter): void => {
    w.numberValue(stat.firstPlayedAt);
  }, first);
  if (stat.coverUrl !== null) {
    first = field(writer, 'coverUrl', (w: JsonWriter): void => {
      w.stringValue(stat.coverUrl as string);
    }, first);
  }
  first = field(writer, 'durationMs', (w: JsonWriter): void => {
    w.numberValue(stat.durationMs);
  }, first);
  if (stat.mediaUri !== null) {
    first = field(writer, 'mediaUri', (w: JsonWriter): void => {
      w.stringValue(stat.mediaUri as string);
    }, first);
  }
  first = field(writer, 'id', (w: JsonWriter): void => {
    w.numberValue(stat.id);
  }, first);
  first = field(writer, 'albumId', (w: JsonWriter): void => {
    w.numberValue(stat.albumId);
  }, first);
  first = field(writer, 'counterBaseListenMs', (w: JsonWriter): void => {
    w.numberValue(stat.counterBaseListenMs);
  }, first);
  first = field(writer, 'counterBasePlayCount', (w: JsonWriter): void => {
    w.numberValue(stat.counterBasePlayCount);
  }, first);
  first = field(writer, 'counterShards', (w: JsonWriter): void => {
    w.raw('[');
    for (let i = 0; i < stat.counterShards.length; i++) {
      if (i > 0) {
        w.raw(',');
      }
      writeCounterShard(w, stat.counterShards[i]);
    }
    w.raw(']');
  }, first);
  writer.raw('}');
}

function writePlaybackStatBucket(writer: JsonWriter, bucket: SyncPlaybackStatBucket): void {
  writer.raw('{');
  let first = true;
  first = field(writer, 'dayStartAt', (w: JsonWriter): void => {
    w.numberValue(bucket.dayStartAt);
  }, first);
  first = field(writer, 'identityKey', (w: JsonWriter): void => {
    w.stringValue(bucket.identityKey);
  }, first);
  first = field(writer, 'name', (w: JsonWriter): void => {
    w.stringValue(bucket.name);
  }, first);
  first = field(writer, 'artist', (w: JsonWriter): void => {
    w.stringValue(bucket.artist);
  }, first);
  first = field(writer, 'album', (w: JsonWriter): void => {
    w.stringValue(bucket.album);
  }, first);
  first = field(writer, 'totalListenMs', (w: JsonWriter): void => {
    w.numberValue(bucket.totalListenMs);
  }, first);
  first = field(writer, 'playCount', (w: JsonWriter): void => {
    w.numberValue(bucket.playCount);
  }, first);
  first = field(writer, 'lastPlayedAt', (w: JsonWriter): void => {
    w.numberValue(bucket.lastPlayedAt);
  }, first);
  first = field(writer, 'firstPlayedAt', (w: JsonWriter): void => {
    w.numberValue(bucket.firstPlayedAt);
  }, first);
  if (bucket.coverUrl !== null) {
    first = field(writer, 'coverUrl', (w: JsonWriter): void => {
      w.stringValue(bucket.coverUrl as string);
    }, first);
  }
  first = field(writer, 'durationMs', (w: JsonWriter): void => {
    w.numberValue(bucket.durationMs);
  }, first);
  if (bucket.mediaUri !== null) {
    first = field(writer, 'mediaUri', (w: JsonWriter): void => {
      w.stringValue(bucket.mediaUri as string);
    }, first);
  }
  first = field(writer, 'id', (w: JsonWriter): void => {
    w.numberValue(bucket.id);
  }, first);
  first = field(writer, 'albumId', (w: JsonWriter): void => {
    w.numberValue(bucket.albumId);
  }, first);
  first = field(writer, 'counterBaseListenMs', (w: JsonWriter): void => {
    w.numberValue(bucket.counterBaseListenMs);
  }, first);
  first = field(writer, 'counterBasePlayCount', (w: JsonWriter): void => {
    w.numberValue(bucket.counterBasePlayCount);
  }, first);
  first = field(writer, 'counterShards', (w: JsonWriter): void => {
    w.raw('[');
    for (let i = 0; i < bucket.counterShards.length; i++) {
      if (i > 0) {
        w.raw(',');
      }
      writeCounterShard(w, bucket.counterShards[i]);
    }
    w.raw(']');
  }, first);
  writer.raw('}');
}

/** Serializes to JSON text with kotlinx semantics (defaults written, nulls omitted). */
export function syncDataToJsonText(data: SyncData): string {
  const writer = new JsonWriter();
  writer.raw('{');
  let first = true;
  first = field(writer, 'version', (w: JsonWriter): void => {
    w.stringValue(data.version);
  }, first);
  first = field(writer, 'deviceId', (w: JsonWriter): void => {
    w.stringValue(data.deviceId);
  }, first);
  first = field(writer, 'deviceName', (w: JsonWriter): void => {
    w.stringValue(data.deviceName);
  }, first);
  first = field(writer, 'lastModified', (w: JsonWriter): void => {
    w.numberValue(data.lastModified);
  }, first);
  first = field(writer, 'playlists', (w: JsonWriter): void => {
    w.raw('[');
    for (let i = 0; i < data.playlists.length; i++) {
      if (i > 0) {
        w.raw(',');
      }
      writeSyncPlaylist(w, data.playlists[i]);
    }
    w.raw(']');
  }, first);
  first = field(writer, 'favoritePlaylists', (w: JsonWriter): void => {
    w.raw('[');
    for (let i = 0; i < data.favoritePlaylists.length; i++) {
      if (i > 0) {
        w.raw(',');
      }
      writeFavoritePlaylist(w, data.favoritePlaylists[i]);
    }
    w.raw(']');
  }, first);
  first = field(writer, 'recentPlays', (w: JsonWriter): void => {
    w.raw('[');
    for (let i = 0; i < data.recentPlays.length; i++) {
      if (i > 0) {
        w.raw(',');
      }
      writeRecentPlay(w, data.recentPlays[i]);
    }
    w.raw(']');
  }, first);
  first = field(writer, 'syncLog', (w: JsonWriter): void => {
    w.raw('[');
    for (let i = 0; i < data.syncLog.length; i++) {
      if (i > 0) {
        w.raw(',');
      }
      writeLogEntry(w, data.syncLog[i]);
    }
    w.raw(']');
  }, first);
  first = field(writer, 'recentPlayDeletions', (w: JsonWriter): void => {
    w.raw('[');
    for (let i = 0; i < data.recentPlayDeletions.length; i++) {
      if (i > 0) {
        w.raw(',');
      }
      writeRecentPlayDeletion(w, data.recentPlayDeletions[i]);
    }
    w.raw(']');
  }, first);
  first = field(writer, 'playbackStats', (w: JsonWriter): void => {
    w.raw('[');
    for (let i = 0; i < data.playbackStats.length; i++) {
      if (i > 0) {
        w.raw(',');
      }
      writeTrackStat(w, data.playbackStats[i]);
    }
    w.raw(']');
  }, first);
  first = field(writer, 'playbackStatsClearedAt', (w: JsonWriter): void => {
    w.numberValue(data.playbackStatsClearedAt);
  }, first);
  first = field(writer, 'playbackStatBuckets', (w: JsonWriter): void => {
    w.raw('[');
    for (let i = 0; i < data.playbackStatBuckets.length; i++) {
      if (i > 0) {
        w.raw(',');
      }
      writePlaybackStatBucket(w, data.playbackStatBuckets[i]);
    }
    w.raw(']');
  }, first);
  first = field(writer, 'playlistSongDeletions', (w: JsonWriter): void => {
    w.raw('[');
    for (let i = 0; i < data.playlistSongDeletions.length; i++) {
      if (i > 0) {
        w.raw(',');
      }
      writePlaylistSongDeletion(w, data.playlistSongDeletions[i]);
    }
    w.raw(']');
  }, first);
  writer.raw('}');
  return writer.build();
}

// ---------------------------------------------------------------------------
// Model readers
// ---------------------------------------------------------------------------

function readCausalTokens(node: JsonValue | undefined): SyncCausalToken[] {
  const list = asArray(node);
  if (list === null) {
    return [];
  }
  const tokens: SyncCausalToken[] = [];
  for (const item of list) {
    const obj = asObject(item);
    if (obj === null) {
      continue;
    }
    tokens.push(new SyncCausalToken(
      readStringField(obj, 'deviceId', ''),
      readNumberField(obj, 'counter', 0)
    ));
  }
  return normalizedSyncCausalTokens(tokens);
}

function readCounterShards(node: JsonValue | undefined): SyncPlaybackCounterShard[] {
  const list = asArray(node);
  if (list === null) {
    return [];
  }
  const shards: SyncPlaybackCounterShard[] = [];
  for (const item of list) {
    const obj = asObject(item);
    if (obj === null) {
      continue;
    }
    shards.push(new SyncPlaybackCounterShard(
      readStringField(obj, 'deviceId', ''),
      readNumberField(obj, 'epochStartedAt', 0),
      readNumberField(obj, 'totalListenMs', 0),
      readNumberField(obj, 'playCount', 0),
      readNumberField(obj, 'firstPlayedAt', 0),
      readNumberField(obj, 'lastPlayedAt', 0)
    ));
  }
  return shards;
}

function readSyncSong(node: JsonValue | undefined): SyncSong {
  const obj = asObject(node);
  if (obj === null) {
    return new SyncSong();
  }
  return new SyncSong(
    readIdNumberField(obj, 'id', 0),
    readStringField(obj, 'name', ''),
    readStringField(obj, 'artist', ''),
    readStringField(obj, 'album', ''),
    readNumberField(obj, 'albumId', 0),
    readNumberField(obj, 'durationMs', 0),
    readStringOrNullField(obj, 'coverUrl'),
    readStringOrNullField(obj, 'mediaUri'),
    readNumberField(obj, 'addedAt', 0),
    readStringOrNullField(obj, 'matchedLyric'),
    readStringOrNullField(obj, 'matchedTranslatedLyric'),
    readStringOrNullField(obj, 'matchedLyricSource'),
    readStringOrNullField(obj, 'matchedSongId'),
    readNumberField(obj, 'userLyricOffsetMs', 0),
    readStringOrNullField(obj, 'customCoverUrl'),
    readStringOrNullField(obj, 'customName'),
    readStringOrNullField(obj, 'customArtist'),
    readStringOrNullField(obj, 'originalName'),
    readStringOrNullField(obj, 'originalArtist'),
    readStringOrNullField(obj, 'originalCoverUrl'),
    readStringOrNullField(obj, 'originalLyric'),
    readStringOrNullField(obj, 'originalTranslatedLyric'),
    readStringOrNullField(obj, 'channelId'),
    readStringOrNullField(obj, 'audioId'),
    readStringOrNullField(obj, 'subAudioId'),
    readStringOrNullField(obj, 'playlistContextId'),
    readCausalTokens(obj.get('syncMembershipTokens')),
    readNumberField(obj, 'syncMetadataVersion', 0),
    readNumberOrNullField(obj, 'legacyAddedAt'),
    readIdTextField(obj, 'id')
  );
}

function readSyncPlaylist(node: JsonValue | undefined): SyncPlaylist | null {
  const obj = asObject(node);
  if (obj === null) {
    return null;
  }
  const songNodes = readArrayField(obj, 'songs');
  if (songNodes === null) {
    return null;
  }
  const songs: SyncSong[] = [];
  for (const item of songNodes) {
    songs.push(readSyncSong(item));
  }
  return new SyncPlaylist(
    readNumberField(obj, 'id', 0),
    readStringField(obj, 'name', ''),
    songs,
    readNumberField(obj, 'createdAt', 0),
    readNumberField(obj, 'modifiedAt', 0),
    readBooleanField(obj, 'isDeleted', false),
    readNumberField(obj, 'songOrderVersion', 0)
  );
}

function readSyncData(root: JsonValue | null): SyncData | null {
  const obj = asObject(root);
  if (obj === null) {
    return null;
  }
  const playlistNodes = readArrayField(obj, 'playlists');
  if (playlistNodes === null) {
    return null;
  }
  const playlists: SyncPlaylist[] = [];
  for (const item of playlistNodes) {
    const playlist = readSyncPlaylist(item);
    if (playlist === null) {
      return null;
    }
    playlists.push(playlist);
  }
  const favoriteNodes = readArrayField(obj, 'favoritePlaylists');
  if (favoriteNodes === null) {
    return null;
  }
  const favorites: SyncFavoritePlaylist[] = [];
  for (const item of favoriteNodes) {
    const favObj = asObject(item);
    if (favObj === null) {
      continue;
    }
    const songNodes = readArrayField(favObj, 'songs');
    if (songNodes === null) {
      return null;
    }
    const songs: SyncSong[] = [];
    for (const songItem of songNodes) {
      songs.push(readSyncSong(songItem));
    }
    favorites.push(new SyncFavoritePlaylist(
      readNumberField(favObj, 'id', 0),
      readStringField(favObj, 'name', ''),
      readStringOrNullField(favObj, 'coverUrl'),
      readNumberField(favObj, 'trackCount', 0),
      readStringField(favObj, 'source', ''),
      songs,
      readNumberField(favObj, 'addedTime', 0),
      readNumberField(favObj, 'modifiedAt', 0),
      readBooleanField(favObj, 'isDeleted', false),
      readNumberField(favObj, 'sortOrder', 0),
      readStringOrNullField(favObj, 'browseId'),
      readStringOrNullField(favObj, 'playlistId'),
      readStringOrNullField(favObj, 'subtitle')
    ));
  }
  const recentNodes = readArrayField(obj, 'recentPlays');
  if (recentNodes === null) {
    return null;
  }
  const recentPlays: SyncRecentPlay[] = [];
  for (const item of recentNodes) {
    const entryObj = asObject(item);
    if (entryObj === null) {
      continue;
    }
    recentPlays.push(new SyncRecentPlay(
      readNumberField(entryObj, 'songId', 0),
      readSyncSong(entryObj.get('song')),
      readNumberField(entryObj, 'playedAt', 0),
      readStringField(entryObj, 'deviceId', ''),
      readNumberField(entryObj, 'resumePositionMs', 0)
    ));
  }
  const logNodes = readArrayField(obj, 'syncLog');
  if (logNodes === null) {
    return null;
  }
  const syncLog: SyncLogEntry[] = [];
  for (const item of logNodes) {
    const logObj = asObject(item);
    if (logObj === null) {
      continue;
    }
    syncLog.push(new SyncLogEntry(
      readNumberField(logObj, 'timestamp', 0),
      readStringField(logObj, 'deviceId', ''),
      parseSyncActionName(readStringField(logObj, 'action', 'CREATE_PLAYLIST')),
      readNumberOrNullField(logObj, 'playlistId'),
      readNumberOrNullField(logObj, 'songId'),
      readStringOrNullField(logObj, 'details')
    ));
  }
  const recentDeletionNodes = readArrayField(obj, 'recentPlayDeletions');
  if (recentDeletionNodes === null) {
    return null;
  }
  const recentPlayDeletions: SyncRecentPlayDeletion[] = [];
  for (const item of recentDeletionNodes) {
    const delObj = asObject(item);
    if (delObj === null) {
      continue;
    }
    recentPlayDeletions.push(new SyncRecentPlayDeletion(
      readIdNumberField(delObj, 'songId', 0),
      readStringField(delObj, 'album', ''),
      readStringOrNullField(delObj, 'mediaUri'),
      readNumberField(delObj, 'deletedAt', 0),
      readStringField(delObj, 'deviceId', ''),
      readIdTextField(delObj, 'songId')
    ));
  }
  const statNodes = readArrayField(obj, 'playbackStats');
  if (statNodes === null) {
    return null;
  }
  const playbackStats: SyncTrackStat[] = [];
  for (const item of statNodes) {
    const statObj = asObject(item);
    if (statObj === null) {
      continue;
    }
    playbackStats.push(new SyncTrackStat(
      readStringField(statObj, 'identityKey', ''),
      readStringField(statObj, 'name', ''),
      readStringField(statObj, 'artist', ''),
      readStringField(statObj, 'album', ''),
      readNumberField(statObj, 'totalListenMs', 0),
      readNumberField(statObj, 'playCount', 0),
      readNumberField(statObj, 'lastPlayedAt', 0),
      readNumberField(statObj, 'firstPlayedAt', 0),
      readStringOrNullField(statObj, 'coverUrl'),
      readNumberField(statObj, 'durationMs', 0),
      readStringOrNullField(statObj, 'mediaUri'),
      readNumberField(statObj, 'id', 0),
      readNumberField(statObj, 'albumId', 0),
      readNumberField(statObj, 'counterBaseListenMs', 0),
      readNumberField(statObj, 'counterBasePlayCount', 0),
      readCounterShards(statObj.get('counterShards'))
    ));
  }
  const bucketNodes = readArrayField(obj, 'playbackStatBuckets');
  if (bucketNodes === null) {
    return null;
  }
  const buckets: SyncPlaybackStatBucket[] = [];
  for (const item of bucketNodes) {
    const bucketObj = asObject(item);
    if (bucketObj === null) {
      continue;
    }
    buckets.push(new SyncPlaybackStatBucket(
      readNumberField(bucketObj, 'dayStartAt', 0),
      readStringField(bucketObj, 'identityKey', ''),
      readStringField(bucketObj, 'name', ''),
      readStringField(bucketObj, 'artist', ''),
      readStringField(bucketObj, 'album', ''),
      readNumberField(bucketObj, 'totalListenMs', 0),
      readNumberField(bucketObj, 'playCount', 0),
      readNumberField(bucketObj, 'lastPlayedAt', 0),
      readNumberField(bucketObj, 'firstPlayedAt', 0),
      readStringOrNullField(bucketObj, 'coverUrl'),
      readNumberField(bucketObj, 'durationMs', 0),
      readStringOrNullField(bucketObj, 'mediaUri'),
      readNumberField(bucketObj, 'id', 0),
      readNumberField(bucketObj, 'albumId', 0),
      readNumberField(bucketObj, 'counterBaseListenMs', 0),
      readNumberField(bucketObj, 'counterBasePlayCount', 0),
      readCounterShards(bucketObj.get('counterShards'))
    ));
  }
  const playlistDeletionNodes = readArrayField(obj, 'playlistSongDeletions');
  if (playlistDeletionNodes === null) {
    return null;
  }
  const playlistSongDeletions: SyncPlaylistSongDeletion[] = [];
  for (const item of playlistDeletionNodes) {
    const delObj = asObject(item);
    if (delObj === null) {
      continue;
    }
    playlistSongDeletions.push(new SyncPlaylistSongDeletion(
      readNumberField(delObj, 'playlistId', 0),
      readIdNumberField(delObj, 'songId', 0),
      readStringField(delObj, 'album', ''),
      readStringOrNullField(delObj, 'mediaUri'),
      readNumberField(delObj, 'deletedAt', 0),
      readStringField(delObj, 'deviceId', ''),
      readCausalTokens(delObj.get('removedMembershipTokens')),
      readIdTextField(delObj, 'songId')
    ));
  }
  return new SyncData(
    readStringField(obj, 'version', '2.0'),
    readStringField(obj, 'deviceId', ''),
    readStringField(obj, 'deviceName', ''),
    readNumberField(obj, 'lastModified', 0),
    playlists,
    favorites,
    recentPlays,
    syncLog,
    recentPlayDeletions,
    playbackStats,
    readNumberField(obj, 'playbackStatsClearedAt', 0),
    buckets,
    playlistSongDeletions
  );
}

/** Deserializes JSON text; returns null on malformed input (never throws). */
export function syncDataFromJsonText(text: string): SyncData | null {
  const stripped = text.length > 0 && text.charCodeAt(0) === 0xFEFF
    ? text.substring(1)
    : text;
  const root = parseJsonText(stripped);
  if (root === null) {
    return null;
  }
  return readSyncData(root);
}

// ---------------------------------------------------------------------------
// Format sniffing and top-level serialize/deserialize (read-both)
// ---------------------------------------------------------------------------

export enum SyncWireFormat {
  JSON = 0,
  GZIP_PROTO = 1,
  LEGACY_BASE64 = 2,
  UNKNOWN = 3
}

export class SyncDecodeResult {
  format: SyncWireFormat;
  data: SyncData | null;
  errorMessage: string;

  constructor(format: SyncWireFormat, data: SyncData | null, errorMessage: string) {
    this.format = format;
    this.data = data;
    this.errorMessage = errorMessage;
  }
}

export function isGzipData(content: Uint8Array): boolean {
  return content.length >= 2 && content[0] === 0x1F && content[1] === 0x8B;
}

export function looksLikeJsonData(content: Uint8Array): boolean {
  let i = 0;
  // Skip UTF-8 BOM.
  if (content.length >= 3 && content[0] === 0xEF && content[1] === 0xBB && content[2] === 0xBF) {
    i = 3;
  }
  while (i < content.length) {
    const b = content[i];
    if (b === 0x20 || b === 0x09 || b === 0x0A || b === 0x0D) {
      i++;
    } else {
      return b === 0x7B; // '{'
    }
  }
  return false;
}

/** Serializes as UTF-8 JSON bytes with the Android 8 MiB upload bound. */
export function serializeSyncDataJson(data: SyncData): Uint8Array {
  const text = syncDataToJsonText(data);
  const bytes = utf8EncodeText(text);
  if (bytes.length > MAX_JSON_BYTES) {
    throw new Error(`Sync data is too large to upload (${bytes.length} > ${MAX_JSON_BYTES} bytes)`);
  }
  return bytes;
}

/** Pre-deserialize size validation, mirroring ensureRemoteContentSize. */
export function ensureRemoteContentSize(content: Uint8Array): boolean {
  const limit = looksLikeJsonData(content) ? MAX_JSON_BYTES : MAX_COMPRESSED_BYTES;
  return content.length <= limit;
}

/**
 * Read-both entry point. Order matches Android: GZIP magic → proto, then
 * JSON, then legacy Base64. The binary branches are recognized but not yet
 * decoded (protobuf wire decoder + gzip inflate land with the D1 follow-up).
 */
export function deserializeSyncContent(content: Uint8Array): SyncDecodeResult {
  if (isGzipData(content)) {
    return new SyncDecodeResult(SyncWireFormat.GZIP_PROTO, null,
      'gzip+protobuf decoding is not available yet (D1 follow-up)');
  }
  if (looksLikeJsonData(content)) {
    if (content.length > MAX_JSON_BYTES) {
      return new SyncDecodeResult(SyncWireFormat.JSON, null,
        `sync JSON exceeds ${MAX_JSON_BYTES} bytes`);
    }
    const data = syncDataFromJsonText(utf8Decode(content));
    if (data === null) {
      return new SyncDecodeResult(SyncWireFormat.JSON, null, 'malformed sync JSON');
    }
    return new SyncDecodeResult(SyncWireFormat.JSON, data, '');
  }
  return new SyncDecodeResult(SyncWireFormat.LEGACY_BASE64, null,
    'legacy base64 gzip decoding is not available yet (D1 follow-up)');
}
