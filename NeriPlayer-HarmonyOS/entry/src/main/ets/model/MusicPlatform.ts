// SPDX-License-Identifier: GPL-3.0

/**
 * Music platform identifiers used across the app.
 */
export enum MusicPlatform {
  LOCAL = 0,
  NETEASE = 1,
  BILIBILI = 2,
  YOUTUBE_MUSIC = 3
}

export function platformName(platform: MusicPlatform): string {
  switch (platform) {
    case MusicPlatform.LOCAL:
      return 'Local';
    case MusicPlatform.NETEASE:
      return 'Netease';
    case MusicPlatform.BILIBILI:
      return 'Bilibili';
    case MusicPlatform.YOUTUBE_MUSIC:
      return 'YouTubeMusic';
    default:
      return 'Local';
  }
}
