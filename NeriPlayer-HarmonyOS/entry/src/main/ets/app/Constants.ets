// SPDX-License-Identifier: GPL-3.0

/**
 * Global constants, mirroring the constants scattered through the Android codebase.
 */
export class Constants {
  static readonly APP_NAME: string = 'NeriPlayer';

  // Third-party platform endpoints.
  static readonly NETEASE_BASE: string = 'https://music.163.com';
  static readonly NETEASE_API_BASE: string = 'https://music.163.com/api';
  static readonly BILI_BASE: string = 'https://api.bilibili.com';
  static readonly YTM_BASE: string = 'https://music.youtube.com';
  static readonly LRCLIB_BASE: string = 'https://lrclib.net/api';

  // Public YouTube Music web client key (anonymous search only).
  static readonly YTM_WEB_API_KEY: string = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';

  // Stable identity markers shared with the Android/Desktop clients.
  static readonly YOUTUBE_MUSIC_IDENTITY_ALBUM: string = 'youtube_music';
  static readonly BILIBILI_IDENTITY_HINT: string = 'Bilibili';
  static readonly NETEASE_IDENTITY_HINT: string = 'Netease';
  static readonly YOUTUBE_MUSIC_MEDIA_PREFIX: string = 'youtube_music|';
}
