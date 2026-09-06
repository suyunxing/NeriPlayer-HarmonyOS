import { LrcMetadata, LrcParseResult, LyricLine, LyricWord } from '../model/LyricLine';

/**
 * LRC parsing + translation merging, mirroring accompanist-lyrics-core
 * behavior. Beyond the Android in-app parser this also handles the
 * [offset:±ms] header (positive advances: every line shifts by -offset),
 * preserves [ti:]/[ar:]/[al:]/[by:] metadata, parses enhanced word LRC
 * (`<mm:ss.ff>` per-word prefixes) and fills per-line end times (next
 * line's start, last line + 5000ms, Android parseNeteaseLrc semantics).
 * serialize() is the inverse direction, added for AVMetadata.lyric.
 */
export class LrcParser {
  private static readonly TIMESTAMP_REGEX: RegExp = /\[(\d{1,2}):(\d{1,2})(?:[.:](\d{1,3}))?\]/g;
  private static readonly WORD_TAG_REGEX: RegExp = /<(\d{1,2}):(\d{1,2})(?:[.:](\d{1,3}))?>/g;
  private static readonly METADATA_LINE_REGEX: RegExp = /^\[(ti|ar|al|by|offset):(.*)\]\s*$/;
  private static readonly LAST_LINE_DURATION_MS: number = 5000;

  static parse(text: string): LyricLine[] {
    return LrcParser.parseWithMetadata(text).lines;
  }

  static parseWithMetadata(text: string): LrcParseResult {
    const result = new LrcParseResult();
    if (text.length === 0) {
      return result;
    }
    const lines: LyricLine[] = [];
    const sourceLines = text.split('\n');
    for (const sourceLine of sourceLines) {
      const trimmed = sourceLine.trim();
      if (trimmed.length === 0) {
        continue;
      }
      const metadataMatch = LrcParser.METADATA_LINE_REGEX.exec(trimmed);
      if (metadataMatch !== null) {
        LrcParser.applyMetadataTag(result.metadata, metadataMatch[1], metadataMatch[2].trim());
        continue;
      }
      const matches = LrcParser.collectTimestamps(trimmed);
      if (matches.length === 0) {
        continue;
      }
      const content = LrcParser.lineContent(trimmed);
      if (content.trim().length === 0) {
        continue;
      }
      for (const timeMs of matches) {
        lines.push(new LyricLine(timeMs, content, ''));
      }
    }
    lines.sort((a: LyricLine, b: LyricLine) => a.timeMs - b.timeMs);
    LrcParser.applyOffset(lines, result.metadata.offsetMs);
    LrcParser.fillWordTimings(lines);
    LrcParser.fillEndTimes(lines);
    result.lines = lines;
    return result;
  }

  /**
   * Merges a translated LRC block into parsed lines by timestamp.
   */
  static mergeTranslation(lines: LyricLine[], translatedText: string): LyricLine[] {
    if (translatedText.length === 0) {
      return lines;
    }
    const translated = LrcParser.parse(translatedText);
    for (const target of lines) {
      for (const source of translated) {
        if (Math.abs(target.timeMs - source.timeMs) < 150) {
          target.translated = source.text;
          break;
        }
      }
    }
    return lines;
  }

  /**
   * Merges a romanized LRC block (netease romalrc) into parsed lines by
   * timestamp; same ±150ms tolerance as translation merging.
   */
  static mergePhonetic(lines: LyricLine[], phoneticText: string): LyricLine[] {
    if (phoneticText.length === 0) {
      return lines;
    }
    const phonetic = LrcParser.parse(phoneticText);
    for (const target of lines) {
      for (const source of phonetic) {
        if (Math.abs(target.timeMs - source.timeMs) < 150) {
          target.phonetic = source.text;
          break;
        }
      }
    }
    return lines;
  }

  static formatTime(timeMs: number): string {
    const totalSeconds = Math.max(0, Math.floor(timeMs / 1000));
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    return `${minutes}:${`${seconds}`.padStart(2, '0')}`;
  }

  /**
   * Serializes parsed lines back into standard LRC text, the inverse of
   * parse(). Needed by AVSessionManager: AVMetadata.lyric is documented as
   * "should be in standard lyric format", and the system player derives the
   * scrolling-lyrics view in the media control center from it.
   *
   * Deliberately lossy in three ways, all so that players which do not
   * understand our extensions still render correctly:
   * - word timings (`<mm:ss.ff>`) are dropped, only line.text is written;
   *   an unsupported reader would otherwise show the tags as literal text.
   * - translation / phonetic lines are dropped (a same-timestamp second line
   *   reads as a duplicate in the control center).
   * - `[offset:]` is never written back: parse() already folded the offset
   *   into every timeMs, so re-emitting the tag would apply it twice.
   */
  static serialize(lines: LyricLine[], metadata?: LrcMetadata): string {
    const out: string[] = [];
    if (metadata !== undefined) {
      if (metadata.title.length > 0) {
        out.push(`[ti:${metadata.title}]`);
      }
      if (metadata.artist.length > 0) {
        out.push(`[ar:${metadata.artist}]`);
      }
      if (metadata.album.length > 0) {
        out.push(`[al:${metadata.album}]`);
      }
      if (metadata.author.length > 0) {
        out.push(`[by:${metadata.author}]`);
      }
    }
    for (const line of lines) {
      // Same empty-text fallback as LyricLineTracker.onPosition, so a
      // translation-only line is not silently dropped.
      const text = line.text.length > 0 ? line.text : line.translated;
      if (text.trim().length === 0) {
        continue;
      }
      out.push(`${LrcParser.toTimestamp(line.timeMs)}${text}`);
    }
    return out.join('\n');
  }

  /**
   * `[mm:ss.SSS]`, millisecond precision so parse(serialize(x)) is lossless.
   * A negative time (reachable when a positive [offset:] advanced the first
   * lines past zero) clamps to 0 rather than emitting an unparsable stamp.
   */
  private static toTimestamp(timeMs: number): string {
    const safe = Math.max(0, Math.round(timeMs));
    const minutes = Math.floor(safe / 60000);
    const seconds = Math.floor((safe % 60000) / 1000);
    const millis = safe % 1000;
    const mm = `${minutes}`.padStart(2, '0');
    const ss = `${seconds}`.padStart(2, '0');
    const sss = `${millis}`.padStart(3, '0');
    return `[${mm}:${ss}.${sss}]`;
  }

  /** Positive [offset:] advances lyrics: effective time = timestamp - offset. */
  private static applyOffset(lines: LyricLine[], offsetMs: number): void {
    if (offsetMs === 0) {
      return;
    }
    for (const line of lines) {
      line.timeMs -= offsetMs;
    }
  }

  private static applyMetadataTag(metadata: LrcMetadata, tag: string, value: string): void {
    if (tag === 'ti') {
      metadata.title = value;
    } else if (tag === 'ar') {
      metadata.artist = value;
    } else if (tag === 'al') {
      metadata.album = value;
    } else if (tag === 'by') {
      metadata.author = value;
    } else if (tag === 'offset') {
      metadata.offsetMs = LrcParser.parseOffsetMs(value);
    }
  }

  private static parseOffsetMs(value: string): number {
    const normalized = value.replace(/\s/g, '');
    const parsed = Number(normalized);
    if (!Number.isFinite(parsed)) {
      return 0;
    }
    const clamped = Math.max(-60000, Math.min(60000, parsed));
    return Math.round(clamped);
  }

  /**
   * Parses `<mm:ss.ff>` word tags inside each line's content: the text
   * after a tag becomes a word starting at that time. Lines without word
   * tags keep their plain text and empty words.
   */
  private static fillWordTimings(lines: LyricLine[]): void {
    for (const line of lines) {
      const raw = line.text;
      if (!raw.includes('<')) {
        continue;
      }
      const words: LyricWord[] = [];
      const plainText = LrcParser.extractWords(raw, words);
      if (words.length === 0) {
        continue;
      }
      line.text = plainText;
      line.words = words;
    }
  }

  /** Splits "a<00:01.00>b<00:01.20>c" into plain text "abc" + timed words. */
  private static extractWords(content: string, words: LyricWord[]): string {
    LrcParser.WORD_TAG_REGEX.lastIndex = 0;
    let cursor = 0;
    let plainPrefix = '';
    let match = LrcParser.WORD_TAG_REGEX.exec(content);
    while (match !== null) {
      const textBefore = content.substring(cursor, match.index);
      if (words.length === 0) {
        plainPrefix += textBefore;
      } else {
        words[words.length - 1].text += textBefore;
      }
      const word = new LyricWord('', LrcParser.timestampToMs(match[1], match[2], match[3]), 0);
      words.push(word);
      cursor = match.index + match[0].length;
      match = LrcParser.WORD_TAG_REGEX.exec(content);
    }
    if (words.length === 0) {
      return content;
    }
    const tail = content.substring(cursor);
    if (tail.length > 0) {
      words[words.length - 1].text += tail;
    }
    let plainText = plainPrefix;
    for (const word of words) {
      plainText += word.text;
    }
    return plainText;
  }

  /** line.end = next line's start (last + 5000ms); word.end = next word's start. */
  private static fillEndTimes(lines: LyricLine[]): void {
    for (let i = 0; i < lines.length; i++) {
      lines[i].endTimeMs =
        i + 1 < lines.length ? lines[i + 1].timeMs : lines[i].timeMs + LrcParser.LAST_LINE_DURATION_MS;
    }
    for (const line of lines) {
      for (let i = 0; i < line.words.length; i++) {
        const word = line.words[i];
        word.endMs = i + 1 < line.words.length ? line.words[i + 1].startMs : line.endTimeMs;
      }
    }
  }

  private static timestampToMs(minutes: string, seconds: string, fraction?: string): number {
    const minutesValue = Number(minutes);
    const secondsValue = Number(seconds);
    let fractionMs = 0;
    if (fraction !== undefined) {
      // Two digits are centiseconds (x10), three are milliseconds.
      fractionMs = Math.round((Number(fraction) / Math.pow(10, fraction.length)) * 1000);
    }
    return minutesValue * 60000 + secondsValue * 1000 + fractionMs;
  }

  private static collectTimestamps(line: string): number[] {
    const timestamps: number[] = [];
    LrcParser.TIMESTAMP_REGEX.lastIndex = 0;
    let match = LrcParser.TIMESTAMP_REGEX.exec(line);
    while (match !== null) {
      timestamps.push(LrcParser.timestampToMs(match[1], match[2], match[3]));
      match = LrcParser.TIMESTAMP_REGEX.exec(line);
    }
    return timestamps;
  }

  private static lineContent(line: string): string {
    const lastBracket = line.lastIndexOf(']');
    return lastBracket >= 0 ? line.substring(lastBracket + 1) : line;
  }
}
