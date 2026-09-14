// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

import { LyricLine, LyricWord } from '../model/LyricLine';

/**
 * Minimal TTML lyric parser for the AMLL database (Apple Music style TTML):
 * <p begin end> lines whose children are word <span begin end> syllables plus
 * <span ttm:role="x-translation"> and ttm:role="x-roman" annotation spans.
 * Android delegates this to the accompanist-lyrics AutoParser from a git
 * submodule that is empty in the snapshot, so this is a purpose-built
 * reimplementation pinned by fixtures from Android's
 * PlayerLyricsProviderTest/AdvancedLyricsViewTest shapes.
 *
 * Supported time expressions: "HH:MM:SS(.fff)", "MM:SS(.fff)", "S(.fff)s",
 * plain milliseconds. Frame/tick expressions are rejected (null) — the AMLL
 * database does not use them.
 */
export class TtmlParser {
  private static readonly LAST_LINE_DURATION_MS: number = 5000;
  private static readonly P_TAG: RegExp = /<p\b([^>]*)>([\s\S]*?)<\/p>/gi;
  private static readonly SPAN_TAG: RegExp = /<span\b([^>]*)>([\s\S]*?)<\/span>|<span\b([^>]*)\/>/gi;

  /** Parses TTML text; returns null when no <p> line can be extracted. */
  static parse(ttml: string): LyricLine[] | null {
    if (ttml.trim().length === 0) {
      return null;
    }
    const lines: LyricLine[] = [];
    TtmlParser.P_TAG.lastIndex = 0;
    let pMatch = TtmlParser.P_TAG.exec(ttml);
    while (pMatch !== null) {
      const line = TtmlParser.parseLine(pMatch[1], pMatch[2]);
      if (line !== null) {
        lines.push(line);
      }
      pMatch = TtmlParser.P_TAG.exec(ttml);
    }
    if (lines.length === 0) {
      return null;
    }
    lines.sort((a: LyricLine, b: LyricLine) => a.timeMs - b.timeMs);
    TtmlParser.fillEndTimes(lines);
    return lines;
  }

  /** Parses a TTML time expression to ms; null when unsupported. */
  static timeToMs(value: string): number | null {
    const text = value.trim();
    if (text.length === 0) {
      return null;
    }
    if (text.endsWith('ms')) {
      const numeric = Number(text.slice(0, -2));
      return Number.isFinite(numeric) ? Math.round(numeric) : null;
    }
    let seconds: number | null = null;
    let body = text;
    if (text.endsWith('s')) {
      body = text.slice(0, -1);
      const numeric = Number(body);
      seconds = Number.isFinite(numeric) ? numeric : null;
    }
    if (seconds !== null) {
      return Math.round(seconds * 1000);
    }
    if (text.endsWith('t') || text.split(':').length > 3) {
      // ticks or HH:MM:SS:FF frames — not present in AMLL data.
      return null;
    }
    if (body.indexOf(':') < 0) {
      // Bare number without a unit: treated as milliseconds.
      const numeric = Number(body);
      return Number.isFinite(numeric) ? Math.round(numeric) : null;
    }
    const parts = body.split(':');
    if (parts.length < 2 || parts.length > 3) {
      return null;
    }
    let hours = 0;
    let minutes = 0;
    let secondsPart = 0;
    if (parts.length === 3) {
      hours = Number(parts[0]);
      minutes = Number(parts[1]);
      secondsPart = Number(parts[2]);
    } else {
      minutes = Number(parts[0]);
      secondsPart = Number(parts[1]);
    }
    if (!Number.isFinite(hours) || !Number.isFinite(minutes) || !Number.isFinite(secondsPart)) {
      return null;
    }
    return Math.round((hours * 3600 + minutes * 60 + secondsPart) * 1000);
  }

  private static parseLine(attrs: string, inner: string): LyricLine | null {
    const begin = TtmlParser.attrValue(attrs, 'begin');
    if (begin === null) {
      return null;
    }
    const startMs = TtmlParser.timeToMs(begin);
    if (startMs === null) {
      return null;
    }
    const endAttr = TtmlParser.attrValue(attrs, 'end');
    const endMs = endAttr !== null ? TtmlParser.timeToMs(endAttr) : null;
    const line = new LyricLine(startMs, '', '');
    if (endMs !== null && endMs >= startMs) {
      line.endTimeMs = endMs;
    }
    // A <p> can carry its own text outside spans plus nested spans; the role
    // spans (x-translation / x-roman) go to dedicated slots, timed spans
    // become words, un-timed spans collapse into the plain text.
    let plainText = '';
    const words: LyricWord[] = [];
    let translation = '';
    let roman = '';
    TtmlParser.SPAN_TAG.lastIndex = 0;
    let cursor = 0;
    let spanMatch = TtmlParser.SPAN_TAG.exec(inner);
    while (spanMatch !== null) {
      const before = inner.substring(cursor, spanMatch.index);
      plainText += TtmlParser.decodeXml(before);
      const spanAttrs = spanMatch[1] !== undefined ? spanMatch[1] : (spanMatch[3] ?? '');
      const spanText = spanMatch[2] !== undefined ? TtmlParser.decodeXml(spanMatch[2]) : '';
      const role = TtmlParser.attrValue(spanAttrs, 'ttm:role');
      if (role === 'x-translation') {
        translation += spanText;
      } else if (role === 'x-roman') {
        roman += spanText;
      } else {
        const wordBegin = TtmlParser.attrValue(spanAttrs, 'begin');
        if (wordBegin !== null) {
          const wordStart = TtmlParser.timeToMs(wordBegin);
          if (wordStart !== null) {
            const wordEndAttr = TtmlParser.attrValue(spanAttrs, 'end');
            const wordEnd = wordEndAttr !== null ? TtmlParser.timeToMs(wordEndAttr) : null;
            // Android keeps the concatenated span text ("HelloWorld").
            const word = new LyricWord(spanText, wordStart, wordEnd !== null && wordEnd >= wordStart ? wordEnd : 0);
            words.push(word);
          } else {
            plainText += spanText;
          }
        } else {
          plainText += spanText;
        }
      }
      cursor = spanMatch.index + spanMatch[0].length;
      spanMatch = TtmlParser.SPAN_TAG.exec(inner);
    }
    plainText += TtmlParser.decodeXml(inner.substring(cursor));
    line.text = plainText.replace(/\s+/g, ' ').trim();
    line.translated = translation.replace(/\s+/g, ' ').trim();
    line.phonetic = roman.replace(/\s+/g, ' ').trim();
    if (line.text.length === 0 && words.length === 0 && line.translated.length === 0) {
      return null;
    }
    // Line text for word-timed lines = concatenation of the words, matching
    // Android's LyricEntry(text = "HelloWorld").
    if (words.length > 0) {
      line.text = words.map((word: LyricWord): string => word.text).join('');
    }
    line.words = words;
    return line;
  }

  private static fillEndTimes(lines: LyricLine[]): void {
    for (let i = 0; i < lines.length; i++) {
      const next = i + 1 < lines.length ? lines[i + 1].timeMs : lines[i].timeMs + TtmlParser.LAST_LINE_DURATION_MS;
      if (lines[i].endTimeMs <= 0) {
        lines[i].endTimeMs = next;
      }
      for (let w = 0; w < lines[i].words.length; w++) {
        const word = lines[i].words[w];
        if (word.endMs <= 0) {
          word.endMs = w + 1 < lines[i].words.length ? lines[i].words[w + 1].startMs : lines[i].endTimeMs;
        }
      }
    }
  }

  private static attrValue(attrs: string, name: string): string | null {
    const pattern = new RegExp(`\\b${name.replace(':', '\\:')}\\s*=\\s*"([^"]*)"`, 'i');
    const match = pattern.exec(attrs);
    if (match !== null) {
      return match[1];
    }
    const singlePattern = new RegExp(`\\b${name.replace(':', '\\:')}\\s*=\\s*'([^']*)'`, 'i');
    const singleMatch = singlePattern.exec(attrs);
    return singleMatch !== null ? singleMatch[1] : null;
  }

  private static decodeXml(text: string): string {
    let decoded = text;
    const named: [string, string][] = [
      ['&lt;', '<'],
      ['&gt;', '>'],
      ['&quot;', '"'],
      ['&apos;', "'"],
      ['&amp;', '&']
    ];
    for (const pair of named) {
      while (decoded.indexOf(pair[0]) >= 0) {
        decoded = decoded.split(pair[0]).join(pair[1]);
      }
    }
    decoded = decoded.replace(/&#(\d+);/g, (_all: string, code: string): string => {
      return String.fromCharCode(Number(code));
    });
    return decoded;
  }
}
