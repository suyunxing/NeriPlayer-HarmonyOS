// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

import { Constants } from '../app/Constants';
import { HttpClient } from './HttpClient';
import { NeteaseApi, LyricPayload } from './NeteaseApi';

interface LrcLibResponse {
  syncedLyrics?: string;
  plainLyrics?: string;
}

/**
 * Lyrics sources: LRCLIB (external) then NetEase, matching the Android app.
 */
export class LyricApi {
  static async fetchFromLrcLib(name: string, artist: string, durationMs: number): Promise<LyricPayload> {
    const url =
      `${Constants.LRCLIB_BASE}/get?track_name=${encodeURIComponent(name)}` +
      `&artist_name=${encodeURIComponent(artist)}&duration=${Math.round(durationMs / 1000)}`;
    const text = await HttpClient.getText(url);
    const response = JSON.parse(text) as LrcLibResponse;
    return new LyricPayload(response.syncedLyrics ?? response.plainLyrics ?? '', '');
  }

  static async fetchFromNetease(neteaseId: number): Promise<LyricPayload> {
    return NeteaseApi.getLyric(neteaseId);
  }
}
