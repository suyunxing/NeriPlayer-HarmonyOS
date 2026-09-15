// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

import { Logger } from '../app/Logger';
import { SongItem } from '../model/SongItem';
import { MusicPlatform } from '../model/MusicPlatform';
import { SettingsRepository } from '../data/SettingsRepository';
import { BiliApi } from './BiliApi';
import { NeteaseApi } from './NeteaseApi';
import { YouTubeMusicApi } from './YouTubeMusicApi';

/**
 * Unified stream resolution with platform fallbacks, mirroring
 * PlayerManagerNeteaseAutoSourceSwitch and the YouTube layered fallbacks.
 */
export class StreamResolver {
  /**
   * Resolves a playable URL for a song. Returns '' when nothing is playable.
   */
  static async resolve(song: SongItem): Promise<string> {
    if (song.streamUrl.length > 0) {
      return song.streamUrl;
    }
    switch (song.platform) {
      case MusicPlatform.LOCAL:
        return song.localFilePath.length > 0 ? song.localFilePath : song.mediaUri;
      case MusicPlatform.NETEASE: {
        const numericId = Number(song.audioId);
        if (!Number.isNaN(numericId) && numericId > 0) {
          return NeteaseApi.getSongUrl(numericId);
        }
        return '';
      }
      case MusicPlatform.BILIBILI: {
        const bvid = song.audioId;
        if (bvid.length === 0) {
          return '';
        }
        return BiliApi.resolveAudioUrl(bvid);
      }
      case MusicPlatform.YOUTUBE_MUSIC: {
        const videoId = song.audioId;
        if (videoId.length === 0) {
          return '';
        }
        return YouTubeMusicApi.resolveStream(videoId);
      }
      default:
        return '';
    }
  }

  /**
   * NetEase auto source switch (PlayerManagerNeteaseAutoSourceSwitch):
   * when the Netease stream is unplayable and the setting is enabled,
   * search Bilibili for candidates and fall back to the best match.
   * A successful fallback URL is cached on the song for later resolves.
   */
  static async resolveWithNeteaseAutoFallback(song: SongItem): Promise<string> {
    const direct = await StreamResolver.resolve(song);
    if (direct.length > 0) {
      return direct;
    }
    if (song.platform !== MusicPlatform.NETEASE) {
      return '';
    }
    if (!SettingsRepository.getBoolean(SettingsRepository.KEY_NETEASE_AUTO_FALLBACK, true)) {
      return '';
    }
    try {
      const keyword = `${song.displayName} ${song.displayArtist}`.trim();
      const candidates = await BiliApi.search(keyword, 10);
      const url = await StreamResolver.resolveNeteaseFallback(song, candidates);
      if (url.length > 0) {
        song.streamUrl = url;
        Logger.info(`StreamResolver: netease auto-fallback matched a bilibili source for ${song.displayName}`);
      }
      return url;
    } catch (error) {
      const e = error as Error;
      Logger.warn(`StreamResolver netease auto-fallback failed: ${e.message}`);
      return '';
    }
  }

  /**
   * Scores Bilibili candidates by title and duration and resolves the best
   * fallback (PlayerManagerNeteaseAutoSourceSwitch).
   */
  static async resolveNeteaseFallback(song: SongItem, candidates: SongItem[]): Promise<string> {
    Logger.debug('StreamResolver.resolveNeteaseFallback: auto source switch not wired to UI yet');
    for (const candidate of candidates) {
      if (candidate.platform !== MusicPlatform.BILIBILI) {
        continue;
      }
      const score = StreamResolver.matchScore(song, candidate);
      if (score >= 2) {
        try {
          const url = await BiliApi.resolveAudioUrl(candidate.audioId);
          if (url.length > 0) {
            return url;
          }
        } catch (error) {
          const e = error as Error;
          Logger.warn(`Netease fallback failed for ${candidate.audioId}: ${e.message}`);
        }
      }
    }
    return '';
  }

  private static matchScore(source: SongItem, candidate: SongItem): number {
    let score = 0;
    const sourceName = source.name.trim().toLowerCase();
    const candidateName = candidate.name.trim().toLowerCase();
    if (sourceName.length > 0 && (candidateName.includes(sourceName) || sourceName.includes(candidateName))) {
      score += 1;
    }
    if (Math.abs(source.durationMs - candidate.durationMs) < 8000) {
      score += 1;
    }
    return score;
  }
}
