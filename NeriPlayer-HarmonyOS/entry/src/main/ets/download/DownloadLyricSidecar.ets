// SPDX-License-Identifier: GPL-3.0

import { Logger } from '../app/Logger';
import { SettingsRepository } from '../data/SettingsRepository';
import { SongItem } from '../model/SongItem';
import { LyricLine } from '../model/LyricLine';
import { LrcParser } from '../lyrics/LrcParser';
import { LyricDispatcher } from '../lyrics/LyricDispatcher';
import { DownloadStorage } from './DownloadStorage';

/**
 * Lyric sidecar for committed downloads (backlog §3.5, Android lyric/cover
 * companion): after a download lands, the resolved lyric ladder writes a
 * `<audio>.lrc` next to the audio file. ID3/FLAC tag writing has no public
 * HarmonyOS API (RELEASE_CHECKLIST §6 decided sidecar carriage), so the
 * sidecar is the offline lyric carrier for local re-imports and other
 * players. Gated by np.download_match_lyrics; failures never surface — the
 * audio download already succeeded.
 */
export class DownloadLyricSidecar {
  /** Fire-and-forget hook called after a download commits. */
  static async writeFor(song: SongItem, audioPath: string): Promise<void> {
    try {
      if (!SettingsRepository.getBoolean(SettingsRepository.KEY_DOWNLOAD_MATCH_LYRICS, true)) {
        return;
      }
      const lines = await LyricDispatcher.loadLyrics(song);
      if (lines.length === 0) {
        return;
      }
      DownloadStorage.writeSidecarText(
        DownloadLyricSidecar.sidecarPath(audioPath),
        DownloadLyricSidecar.buildSidecarText(lines));
      Logger.info(`DownloadLyricSidecar: wrote ${lines.length} lines for ${song.displayName}`);
    } catch (error) {
      Logger.info(`DownloadLyricSidecar skipped: ${(error as Error).message}`);
    }
  }

  /** `/path/song.m4a` (or file:// URI form) -> `/path/song.lrc`. */
  static sidecarPath(audioPath: string): string {
    const stripped = audioPath.startsWith('file://') ? audioPath.substring('file://'.length) : audioPath;
    const dot = stripped.lastIndexOf('.');
    const slash = stripped.lastIndexOf('/');
    const withoutExt = dot > slash ? stripped.substring(0, dot) : stripped;
    return `${withoutExt}.lrc`;
  }

  /**
   * Plain LRC text with translations carried as same-timestamp companion
   * lines (the standard LRC translation form; LrcParser.mergeTranslation
   * re-joins them on a ±150ms window — identical timestamps always match).
   * Pure so the round trip is unit-testable.
   */
  static buildSidecarText(lines: LyricLine[]): string {
    const main: string[] = [];
    const translations: string[] = [];
    for (const line of lines) {
      const text = line.text.length > 0 ? line.text : line.translated;
      if (text.trim().length === 0) {
        continue;
      }
      main.push(LrcParser.formatLrcTimestamp(line.timeMs) + text);
      if (line.translated.trim().length > 0 && line.text.trim().length > 0) {
        translations.push(LrcParser.formatLrcTimestamp(line.timeMs) + line.translated);
      }
    }
    return main.concat(translations).join('\n');
  }
}
