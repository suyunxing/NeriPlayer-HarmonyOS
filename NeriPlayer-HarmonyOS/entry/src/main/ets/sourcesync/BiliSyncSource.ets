// SPDX-License-Identifier: GPL-3.0

import { SongItem } from '../model/SongItem';
import { BiliApi } from '../network/BiliApi';
import { biliFavMediaToSongItem } from '../network/BiliFavParser';
import { SyncSourceAdapter } from './SyncSourceAdapter';

/**
 * Bilibili favorite-folder source. The folder has no remote update timestamp,
 * so the fingerprint is the media count from one cheap first-page request;
 * the coordinator additionally forces a full diff at least once a day to
 * cover count-invariant changes (items replaced without a count change).
 */
export class BiliSyncSource implements SyncSourceAdapter {
  private readonly mediaId: number;

  constructor(mediaId: number) {
    this.mediaId = mediaId;
  }

  async peekFingerprint(): Promise<string> {
    const page = await BiliApi.getFavFolderPage(this.mediaId, 1);
    return `c${page.totalCount}`;
  }

  async fetchSongs(): Promise<SongItem[]> {
    const items = await BiliApi.getAllFavFolderItems(this.mediaId);
    const songs: SongItem[] = [];
    for (const item of items) {
      songs.push(biliFavMediaToSongItem(item));
    }
    return songs;
  }
}
