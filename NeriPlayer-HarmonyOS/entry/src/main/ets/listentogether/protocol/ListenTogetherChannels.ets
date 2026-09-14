// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Port of listentogether/protocol/ListenTogetherChannels.kt plus the ArkTS-only
 * channel normalizer.
 *
 * The wire channel ids are shared with the Android client and the room server,
 * so they must stay byte-identical (note the camelCase "youtubeMusic"). This
 * app stores the YouTube Music channel locally as "youtube_music"
 * (Constants.YOUTUBE_MUSIC_IDENTITY_ALBUM), so any local channel id has to be
 * normalized before it reaches a stable track key or the wire.
 */

export class ListenTogetherChannels {
  static readonly NETEASE: string = 'netease';
  static readonly BILIBILI: string = 'bilibili';
  static readonly YOUTUBE_MUSIC: string = 'youtubeMusic';
  static readonly LOCAL: string = 'local';
}

/**
 * Maps a locally stored channel id onto the wire value. Unknown channels are
 * passed through trimmed (Android keeps an explicit channelId verbatim), so a
 * future channel added on one side does not silently collapse into netease.
 */
export function normalizedListenTogetherChannelId(rawChannelId: string | null): string | null {
  if (rawChannelId === null) {
    return null;
  }
  const trimmed = rawChannelId.trim();
  if (trimmed.length === 0) {
    return null;
  }
  const lowered = trimmed.toLowerCase();
  if (lowered === 'netease') {
    return ListenTogetherChannels.NETEASE;
  }
  if (lowered === 'bilibili') {
    return ListenTogetherChannels.BILIBILI;
  }
  if (lowered === 'youtubemusic' || lowered === 'youtube_music' ||
    lowered === 'ytmusic' || lowered === 'youtube') {
    return ListenTogetherChannels.YOUTUBE_MUSIC;
  }
  if (lowered === 'local') {
    return ListenTogetherChannels.LOCAL;
  }
  return trimmed;
}

/** Android compares the channel against LOCAL case-insensitively. */
export function isListenTogetherLocalChannel(channelId: string): boolean {
  return channelId.toLowerCase() === ListenTogetherChannels.LOCAL;
}
