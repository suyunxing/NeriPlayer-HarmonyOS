// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

import { Constants } from '../app/Constants';
import { HttpClient } from './HttpClient';

/**
 * AMLL TTML lyrics database client, mirroring Android AmllTtmlClient:
 * search via POST /api/search-lyrics {"query","type":"title"}, raw lyrics
 * via GET /raw-lyrics/{file} where file must end with .ttml and contain no
 * path separator. The response body is the raw TTML XML; parsing lives in
 * lyrics/TtmlParser. Pure logic (scoring/selection) lives in
 * lyrics/AmllLyricsResolver so it stays unit-testable.
 */
export class AmllSearchResult {
  file: string = '';
  title: string = '';
  titles: string[] = [];
  artist: string = '';
  artists: string[] = [];
  albums: string[] = [];
  ncmIds: number[] = [];
  qqIds: number[] = [];
  score: number = 0;

  static fromRecord(raw: Record<string, Object>): AmllSearchResult {
    const result = new AmllSearchResult();
    result.file = String(raw['file'] ?? '');
    result.title = String(raw['title'] ?? '');
    result.artist = String(raw['artist'] ?? '');
    result.score = Number(raw['score'] ?? 0);
    result.titles = AmllSearchResult.stringArray(raw['titles']);
    result.artists = AmllSearchResult.stringArray(raw['artists']);
    result.albums = AmllSearchResult.stringArray(raw['albums']);
    result.ncmIds = AmllSearchResult.numberArray(raw['ncmIds']);
    result.qqIds = AmllSearchResult.numberArray(raw['qqIds']);
    return result;
  }

  private static stringArray(value: Object | undefined): string[] {
    if (!Array.isArray(value)) {
      return [];
    }
    const out: string[] = [];
    for (const item of value as Object[]) {
      const text = String(item ?? '');
      if (text.length > 0) {
        out.push(text);
      }
    }
    return out;
  }

  private static numberArray(value: Object | undefined): number[] {
    if (!Array.isArray(value)) {
      return [];
    }
    const out: number[] = [];
    for (const item of value as Object[]) {
      const num = Number(item);
      if (Number.isFinite(num)) {
        out.push(num);
      }
    }
    return out;
  }
}

export class AmllTtmlApi {
  static async searchLyrics(trackName: string): Promise<AmllSearchResult[]> {
    const body = JSON.stringify({ query: trackName, type: 'title' }) as string;
    const text = await HttpClient.postJson(
      `${Constants.AMLL_BASE}/api/search-lyrics`,
      body,
      15000,
      { 'User-Agent': 'NeriPlayer/1.0 (HarmonyOS port)' }
    );
    const parsed: Object = JSON.parse(text);
    if (!Array.isArray(parsed)) {
      return [];
    }
    const results: AmllSearchResult[] = [];
    for (const item of parsed as Object[]) {
      if (item !== null && typeof item === 'object') {
        results.push(AmllSearchResult.fromRecord(item as Record<string, Object>));
      }
    }
    return results;
  }

  /** Raw TTML text for a search result; file name is validated like Android. */
  static async fetchRawLyrics(file: string): Promise<string> {
    if (!file.endsWith('.ttml') || file.includes('/')) {
      throw new Error(`invalid amll lyrics file: ${file}`);
    }
    return HttpClient.getText(
      `${Constants.AMLL_BASE}/raw-lyrics/${encodeURIComponent(file)}`,
      { 'User-Agent': 'NeriPlayer/1.0 (HarmonyOS port)' },
      15000
    );
  }
}
