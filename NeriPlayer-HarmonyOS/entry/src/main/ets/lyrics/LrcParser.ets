import { LyricLine } from '../model/LyricLine';

/**
 * LRC parsing + translation merging, mirroring accompanist-lyrics-core behavior.
 */
export class LrcParser {
  private static readonly TIMESTAMP_REGEX: RegExp = /\[(\d{1,2}):(\d{1,2})(?:[.:](\d{1,3}))?\]/g;

  static parse(text: string): LyricLine[] {
    const lines: LyricLine[] = [];
    if (text.length === 0) {
      return lines;
    }
    const sourceLines = text.split('\n');
    for (const sourceLine of sourceLines) {
      const matches = LrcParser.collectTimestamps(sourceLine);
      if (matches.length === 0) {
        continue;
      }
      const content = LrcParser.lineContent(sourceLine);
      if (content.trim().length === 0) {
        continue;
      }
      for (const timeMs of matches) {
        lines.push(new LyricLine(timeMs, content, ''));
      }
    }
    lines.sort((a: LyricLine, b: LyricLine) => a.timeMs - b.timeMs);
    return lines;
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

  static formatTime(timeMs: number): string {
    const totalSeconds = Math.max(0, Math.floor(timeMs / 1000));
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    return `${minutes}:${`${seconds}`.padStart(2, '0')}`;
  }

  private static collectTimestamps(line: string): number[] {
    const timestamps: number[] = [];
    LrcParser.TIMESTAMP_REGEX.lastIndex = 0;
    let match = LrcParser.TIMESTAMP_REGEX.exec(line);
    while (match !== null) {
      const minutes = Number(match[1]);
      const seconds = Number(match[2]);
      let fraction = 0;
      if (match[3] !== undefined) {
        const raw = match[3];
        fraction = Number(raw) / Math.pow(10, raw.length);
      }
      timestamps.push(minutes * 60000 + seconds * 1000 + fraction * 1000);
      match = LrcParser.TIMESTAMP_REGEX.exec(line);
    }
    return timestamps;
  }

  private static lineContent(line: string): string {
    const lastBracket = line.lastIndexOf(']');
    return lastBracket >= 0 ? line.substring(lastBracket + 1) : line;
  }
}
