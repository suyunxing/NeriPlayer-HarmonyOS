// SPDX-License-Identifier: GPL-3.0

import { SongItem } from '../model/SongItem';
import { NeteaseApi } from '../network/NeteaseApi';
import { SyncSourceAdapter } from './SyncSourceAdapter';

/**
 * NetEase playlist source. The fingerprint comes from the playlist-level
 * updateTime on /api/v6/playlist/detail (degrades to trackCount when the
 * field is absent); the song list reuses getPlaylistDetail, which reassembles
 * the authoritative trackIds order in batches.
 */
export class NeteaseSyncSource implements SyncSourceAdapter {
  private readonly playlistId: number;

  constructor(playlistId: number) {
    this.playlistId = playlistId;
  }

  async peekFingerprint(): Promise<string> {
    return NeteaseApi.getPlaylistFingerprint(this.playlistId);
  }

  async fetchSongs(): Promise<SongItem[]> {
    return NeteaseApi.getPlaylistDetail(this.playlistId);
  }
}
