// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

import { Constants } from '../app/Constants';
import { HttpClient } from './HttpClient';
import { NeteaseApi, LyricPayload } from './NeteaseApi';

interface LrcLibResponse {
  syncedLyrics?: string;
  plainLyrics?: string;
  duration?: number;
}

/** Duration guard shared with the cross-source matcher (SongMatchScorer ±8s). */
const LRCLIB_DURATION_TOLERANCE_S: number = 8;

/**
 * A hit whose duration disagrees with the requested one by more than the
 * tolerance is a different song's lyrics (upstream #417 duration-mismatch
 * guard); pure and unit-testable.
 */
export function isLrcLibDurationPlausible(requestedMs: number, respondedSeconds: number): boolean {
  if (requestedMs <= 0 || respondedSeconds <= 0) {
    return true;
  }
  const requestedSeconds = requestedMs / 1000;
  return Math.abs(requestedSeconds - respondedSeconds) <= LRCLIB_DURATION_TOLERANCE_S;
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
    if (!isLrcLibDurationPlausible(durationMs, response.duration ?? 0)) {
      // Return no lyric rather than another song's text; the dispatcher's
      // netease supplement then gets a chance to fill in.
      return new LyricPayload('', '', '');
    }
    return new LyricPayload(response.syncedLyrics ?? response.plainLyrics ?? '', '');
  }

  static async fetchFromNetease(neteaseId: number): Promise<LyricPayload> {
    return NeteaseApi.getLyric(neteaseId);
  }
}
