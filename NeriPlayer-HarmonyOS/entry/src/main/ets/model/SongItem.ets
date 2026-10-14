// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

import { MusicPlatform } from './MusicPlatform';
import { SyncCausalToken, normalizedSyncCausalTokens } from '../sync/SyncModels';

/**
 * Faithful port of the Android SongItem data class (moe.ouom.neriplayer.data.model.SongItem).
 * ArkTS has no data classes, so equality/parceling are replaced by stable keys (SongIdentity).
 */
export class SongItem {
  id: number;
  name: string;
  artist: string;
  album: string;
  albumId: number;
  /** Primary artist id (NetEase ar[0].id); 0 when the platform has none. */
  artistId: number;
  durationMs: number;
  coverUrl: string;
  mediaUri: string;
  matchedLyric: string;
  matchedTranslatedLyric: string;
  matchedPhoneticLyric: string;
  matchedSongId: string;
  userLyricOffsetMs: number;
  customCoverUrl: string;
  customName: string;
  customArtist: string;
  originalName: string;
  originalArtist: string;
  originalCoverUrl: string;
  originalLyric: string;
  originalTranslatedLyric: string;
  localFileName: string;
  localFilePath: string;
  channelId: string;
  audioId: string;
  subAudioId: string;
  playlistContextId: string;
  sourceStableKey: string;
  streamUrl: string;
  addedAt: number;
  syncMembershipTokens: SyncCausalToken[];
  syncIdText: string;
  platform: MusicPlatform;

  constructor(
    id: number = 0,
    name: string = '',
    artist: string = '',
    album: string = '',
    albumId: number = 0,
    durationMs: number = 0,
    coverUrl: string = '',
    mediaUri: string = '',
    platform: MusicPlatform = MusicPlatform.NETEASE
  ) {
    this.id = id;
    this.name = name;
    this.artist = artist;
    this.album = album;
    this.albumId = albumId;
    this.artistId = 0;
    this.durationMs = durationMs;
    this.coverUrl = coverUrl;
    this.mediaUri = mediaUri;
    this.matchedLyric = '';
    this.matchedTranslatedLyric = '';
    this.matchedPhoneticLyric = '';
    this.matchedSongId = '';
    this.userLyricOffsetMs = 0;
    this.customCoverUrl = '';
    this.customName = '';
    this.customArtist = '';
    this.originalName = '';
    this.originalArtist = '';
    this.originalCoverUrl = '';
    this.originalLyric = '';
    this.originalTranslatedLyric = '';
    this.localFileName = '';
    this.localFilePath = '';
    this.channelId = '';
    this.audioId = '';
    this.subAudioId = '';
    this.playlistContextId = '';
    this.sourceStableKey = '';
    this.streamUrl = '';
    this.addedAt = 0;
    this.syncMembershipTokens = [];
    this.syncIdText = '';
    this.platform = platform;
  }

  get displayName(): string {
    return this.customName.length > 0 ? this.customName : this.name;
  }

  get displayArtist(): string {
    return this.customArtist.length > 0 ? this.customArtist : this.artist;
  }

  get effectiveCoverUrl(): string {
    if (this.customCoverUrl.length > 0) {
      return this.customCoverUrl;
    }
    return this.coverUrl;
  }

  toJson(): string {
    return JSON.stringify(this);
  }

  static fromJson(json: string): SongItem {
    const raw: Record<string, Object> = JSON.parse(json) as Record<string, Object>;
    const song = new SongItem();
    song.id = Number(raw['id'] ?? 0);
    song.name = String(raw['name'] ?? '');
    song.artist = String(raw['artist'] ?? '');
    song.album = String(raw['album'] ?? '');
    song.albumId = Number(raw['albumId'] ?? 0);
    song.artistId = Number(raw['artistId'] ?? 0);
    song.durationMs = Number(raw['durationMs'] ?? 0);
    song.coverUrl = String(raw['coverUrl'] ?? '');
    song.mediaUri = String(raw['mediaUri'] ?? '');
    song.matchedLyric = String(raw['matchedLyric'] ?? '');
    song.matchedTranslatedLyric = String(raw['matchedTranslatedLyric'] ?? '');
    song.matchedPhoneticLyric = String(raw['matchedPhoneticLyric'] ?? '');
    song.matchedSongId = String(raw['matchedSongId'] ?? '');
    song.userLyricOffsetMs = Number(raw['userLyricOffsetMs'] ?? 0);
    song.customCoverUrl = String(raw['customCoverUrl'] ?? '');
    song.customName = String(raw['customName'] ?? '');
    song.customArtist = String(raw['customArtist'] ?? '');
    song.originalName = String(raw['originalName'] ?? '');
    song.originalArtist = String(raw['originalArtist'] ?? '');
    song.originalCoverUrl = String(raw['originalCoverUrl'] ?? '');
    song.originalLyric = String(raw['originalLyric'] ?? '');
    song.originalTranslatedLyric = String(raw['originalTranslatedLyric'] ?? '');
    song.localFileName = String(raw['localFileName'] ?? '');
    song.localFilePath = String(raw['localFilePath'] ?? '');
    song.channelId = String(raw['channelId'] ?? '');
    song.audioId = String(raw['audioId'] ?? '');
    song.subAudioId = String(raw['subAudioId'] ?? '');
    song.playlistContextId = String(raw['playlistContextId'] ?? '');
    song.sourceStableKey = String(raw['sourceStableKey'] ?? '');
    song.streamUrl = String(raw['streamUrl'] ?? '');
    song.addedAt = Number(raw['addedAt'] ?? 0);
    const rawTokens = raw['syncMembershipTokens'];
    if (rawTokens instanceof Array) {
      const tokenItems: Object[] = rawTokens as Object[];
      const tokens: SyncCausalToken[] = [];
      for (const rawToken of tokenItems) {
        const token = rawToken as Record<string, Object>;
        tokens.push(new SyncCausalToken(
          String(token['deviceId'] ?? ''), Number(token['counter'] ?? 0)));
      }
      song.syncMembershipTokens = normalizedSyncCausalTokens(tokens);
    }
    song.syncIdText = String(raw['syncIdText'] ?? '');
    song.platform = Number(raw['platform'] ?? MusicPlatform.NETEASE) as MusicPlatform;
    return song;
  }
}
