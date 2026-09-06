import { decodeBase64, utf8Decode } from '../util/Base64';

/*
 * Pure decoders for QQ Music lyric payloads, ported verbatim from Android
 * QQMusicSearchApi.kt (decodeQQMusicLyricPayload / stripUntranslatedPlaceholderLines).
 * Kept free of UI/network/system imports so the local hypium suite covers
 * every branch (same rationale as util/Base64.ets).
 *
 * Invalid payloads resolve to '' instead of throwing: a failed decode must
 * never break the search/detail flow, it only means "no lyric".
 */

const QQ_MUSIC_LRC_TIMESTAMP_PATTERN: RegExp = /\[(\d{1,3}):(\d{2})(?:[.:]\d{1,3})?\]/;

export function containsLrcTimestamp(value: string): boolean {
  return QQ_MUSIC_LRC_TIMESTAMP_PATTERN.test(value);
}

export function htmlUnescapeQQMusic(value: string): string {
  return value
    .replace(/&#39;/g, "'")
    .replace(/&apos;/g, "'")
    .replace(/&quot;/g, '"')
    .replace(/&amp;/g, '&');
}

/**
 * QQ Music ships lyrics either as plain LRC text (already HTML-escaped) or as
 * base64 of it. Plain text is returned when it already carries LRC timestamps;
 * otherwise one base64 round is tried and must itself decode into timestamped
 * LRC. Everything else is rejected as ''.
 */
export function decodeQQMusicLyricPayload(rawValue: string): string {
  const sanitized = rawValue.trim();
  if (sanitized.length === 0) {
    return '';
  }
  const plainText = htmlUnescapeQQMusic(sanitized);
  if (containsLrcTimestamp(plainText)) {
    return plainText;
  }
  const decoded = decodeQQMusicBase64Lyric(plainText);
  if (decoded.length === 0) {
    return '';
  }
  const unescaped = htmlUnescapeQQMusic(decoded);
  return containsLrcTimestamp(unescaped) ? unescaped : '';
}

export function decodeQQMusicBase64Lyric(value: string): string {
  const bytes = decodeBase64(value);
  if (bytes === null) {
    return '';
  }
  const text = utf8Decode(bytes);
  return containsLrcTimestamp(text) ? text : '';
}

/** True when the line body is nothing but slashes (half/full-width), i.e. "no translation". */
function isQQMusicUntranslatedPlaceholder(text: string): boolean {
  let normalized = '';
  for (const ch of text) {
    if (ch === ' ' || ch === '\t' || ch === '　') {
      continue;
    }
    normalized += ch === '／' ? '/' : ch;
  }
  if (normalized.length < 2) {
    return false;
  }
  for (const ch of normalized) {
    if (ch !== '/') {
      return false;
    }
  }
  return true;
}

/**
 * QQ marks untranslated lines with a slash-only body. Those lines are folded
 * to "[timestamp]//" so the translation matcher still has a time slot to pair
 * with; the render layer ignores the placeholder text.
 */
export function stripUntranslatedPlaceholderLines(lyric: string): string {
  const source = lyric.trim();
  if (source.length === 0) {
    return '';
  }
  const lines = source.split('\n');
  const out: string[] = [];
  for (const line of lines) {
    const closingBracket = line.indexOf(']');
    if (closingBracket < 0) {
      out.push(line);
      continue;
    }
    const text = line.substring(closingBracket + 1).trim();
    if (isQQMusicUntranslatedPlaceholder(text)) {
      out.push(line.substring(0, closingBracket + 1) + '//');
    } else {
      out.push(line);
    }
  }
  const joined = out.join('\n');
  return joined.trim().length > 0 ? joined : '';
}
