/**
 * Port of the four single-field validators under listentogether/validation/:
 * ListenTogetherRoomIdValidation.kt, ListenTogetherNicknameValidation.kt,
 * ListenTogetherJoinSecretValidation.kt and ListenTogetherUserUuidValidation.kt.
 *
 * Kept in one file because the four share the error type and are always used
 * together. Order of checks matches Android exactly (length before charset), so
 * the reported error code stays identical across platforms.
 *
 * Trim semantics are the ECMAScript ones; Kotlin `trim()` uses
 * `Char.isWhitespace()` and therefore keeps U+00A0 / U+FEFF, which ES strips.
 * Every allowed charset here excludes those code points anyway, so the only
 * effect is that a nickname padded with them is accepted after trimming here
 * and rejected on Android.
 */
import {
  ListenTogetherValidationCode,
  ListenTogetherValidationError,
  listenTogetherValidationError,
  throwListenTogetherValidation
} from './ListenTogetherValidationError';

export const LISTEN_TOGETHER_ROOM_ID_LENGTH: number = 6;
export const LISTEN_TOGETHER_NICKNAME_MIN_LENGTH: number = 1;
export const LISTEN_TOGETHER_NICKNAME_MAX_LENGTH: number = 24;
export const LISTEN_TOGETHER_JOIN_SECRET_MAX_LENGTH: number = 256;

/** Crockford-style alphabet: no I, O, 0 or 1, so room ids stay readable aloud. */
const ROOM_ID_REGEX: RegExp = /^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$/;

const USER_UUID_REGEX: RegExp =
  /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$/;

export function normalizeListenTogetherRoomId(value: string): string {
  return value.trim().toUpperCase();
}

export function validateListenTogetherRoomId(roomId: string): ListenTogetherValidationError | null {
  const normalized = normalizeListenTogetherRoomId(roomId);
  if (normalized.length !== LISTEN_TOGETHER_ROOM_ID_LENGTH) {
    return listenTogetherValidationError(
      ListenTogetherValidationCode.ROOM_ID_LENGTH,
      [LISTEN_TOGETHER_ROOM_ID_LENGTH]
    );
  }
  if (!ROOM_ID_REGEX.test(normalized)) {
    return listenTogetherValidationError(ListenTogetherValidationCode.ROOM_ID_CHARS);
  }
  return null;
}

export function requireValidListenTogetherRoomId(roomId: string): string {
  const normalized = normalizeListenTogetherRoomId(roomId);
  const error = validateListenTogetherRoomId(normalized);
  if (error !== null) {
    throwListenTogetherValidation(error);
  }
  return normalized;
}

export function validateListenTogetherNickname(
  nickname: string
): ListenTogetherValidationError | null {
  const normalized = nickname.trim();
  if (normalized.length < LISTEN_TOGETHER_NICKNAME_MIN_LENGTH ||
    normalized.length > LISTEN_TOGETHER_NICKNAME_MAX_LENGTH) {
    return listenTogetherValidationError(
      ListenTogetherValidationCode.NICKNAME_LENGTH,
      [LISTEN_TOGETHER_NICKNAME_MIN_LENGTH, LISTEN_TOGETHER_NICKNAME_MAX_LENGTH]
    );
  }
  if (!isValidListenTogetherNickname(normalized)) {
    return listenTogetherValidationError(ListenTogetherValidationCode.NICKNAME_CHARS);
  }
  return null;
}

export function sanitizeListenTogetherNicknameOrNull(nickname: string | null): string | null {
  const normalized = nickname === null ? '' : nickname.trim();
  if (normalized.length === 0) {
    return null;
  }
  return validateListenTogetherNickname(normalized) === null ? normalized : null;
}

export function requireValidListenTogetherNickname(nickname: string): string {
  const normalized = nickname.trim();
  const error = validateListenTogetherNickname(normalized);
  if (error !== null) {
    throwListenTogetherValidation(error);
  }
  return normalized;
}

export function validateListenTogetherJoinSecret(
  value: string | null
): ListenTogetherValidationError | null {
  const normalized = value === null ? '' : value.trim();
  if (normalized.length === 0) {
    return listenTogetherValidationError(ListenTogetherValidationCode.JOIN_SECRET_REQUIRED);
  }
  if (normalized.length > LISTEN_TOGETHER_JOIN_SECRET_MAX_LENGTH) {
    return listenTogetherValidationError(
      ListenTogetherValidationCode.JOIN_SECRET_LENGTH,
      [LISTEN_TOGETHER_JOIN_SECRET_MAX_LENGTH]
    );
  }
  return null;
}

export function sanitizeListenTogetherJoinSecretOrNull(value: string | null): string | null {
  const normalized = value === null ? '' : value.trim();
  return validateListenTogetherJoinSecret(normalized) === null ? normalized : null;
}

export function requireValidListenTogetherJoinSecret(value: string | null): string {
  const normalized = value === null ? '' : value.trim();
  const error = validateListenTogetherJoinSecret(normalized);
  if (error !== null) {
    throwListenTogetherValidation(error);
  }
  return normalized;
}

export function validateListenTogetherUserUuid(
  userUuid: string
): ListenTogetherValidationError | null {
  const normalized = userUuid.trim();
  if (normalized.length === 0) {
    return listenTogetherValidationError(ListenTogetherValidationCode.USER_UUID_REQUIRED);
  }
  if (!USER_UUID_REGEX.test(normalized)) {
    return listenTogetherValidationError(ListenTogetherValidationCode.USER_UUID_INVALID);
  }
  return null;
}

/** Returns the lower-cased uuid, matching Android `requireValid...`. */
export function requireValidListenTogetherUserUuid(userUuid: string): string {
  const normalized = userUuid.trim();
  const error = validateListenTogetherUserUuid(normalized);
  if (error !== null) {
    throwListenTogetherValidation(error);
  }
  return normalized.toLowerCase();
}

/**
 * Ranges whose Unicode script is Han, replacing
 * `Character.UnicodeScript.of(cp) == HAN`. Sorted ascending so the lookup can
 * stop early. Covers the radicals, the ideographic marks Android accepts and
 * every CJK extension up to Ext I.
 */
const HAN_CODE_POINT_RANGES: number[][] = [
  [0x2E80, 0x2E99],
  [0x2E9B, 0x2EF3],
  [0x2F00, 0x2FD5],
  [0x3005, 0x3005],
  [0x3007, 0x3007],
  [0x3021, 0x3029],
  [0x3038, 0x303B],
  [0x3400, 0x4DBF],
  [0x4E00, 0x9FFF],
  [0xF900, 0xFA6D],
  [0xFA70, 0xFAD9],
  [0x16FE2, 0x16FE3],
  [0x16FF0, 0x16FF1],
  [0x20000, 0x2A6DF],
  [0x2A700, 0x2B739],
  [0x2B740, 0x2B81D],
  [0x2B820, 0x2CEA1],
  [0x2CEB0, 0x2EBE0],
  [0x2EBF0, 0x2EE5D],
  [0x2F800, 0x2FA1D],
  [0x30000, 0x3134A],
  [0x31350, 0x323AF]
];

export function isListenTogetherHanCodePoint(codePoint: number): boolean {
  for (const range of HAN_CODE_POINT_RANGES) {
    if (codePoint < range[0]) {
      return false;
    }
    if (codePoint <= range[1]) {
      return true;
    }
  }
  return false;
}

function isAllowedNicknameCodePoint(codePoint: number): boolean {
  if (codePoint >= 0x30 && codePoint <= 0x39) {
    return true;
  }
  if (codePoint >= 0x41 && codePoint <= 0x5A) {
    return true;
  }
  if (codePoint >= 0x61 && codePoint <= 0x7A) {
    return true;
  }
  return isListenTogetherHanCodePoint(codePoint);
}

/** Walks code points, combining surrogate pairs like `Character.charCount`. */
function isValidListenTogetherNickname(value: string): boolean {
  let index = 0;
  while (index < value.length) {
    const unit = value.charCodeAt(index);
    let codePoint = unit;
    let step = 1;
    if (unit >= 0xD800 && unit <= 0xDBFF && index + 1 < value.length) {
      const low = value.charCodeAt(index + 1);
      if (low >= 0xDC00 && low <= 0xDFFF) {
        codePoint = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00);
        step = 2;
      }
    }
    if (!isAllowedNicknameCodePoint(codePoint)) {
      return false;
    }
    index += step;
  }
  return true;
}
