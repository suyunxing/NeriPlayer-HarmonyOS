// SPDX-License-Identifier: GPL-3.0

import { Playlist } from '../model/Playlist';
import { SongItem } from '../model/SongItem';
import { MusicPlatform } from '../model/MusicPlatform';
import { stableKeyOf } from '../model/SongIdentity';
import { SyncPlaylist } from './SyncModels';
import { isLocalSongItem, playlistIdToSync, songItemFromSyncSong, syncPlaylistIdToLocal } from './SyncSongConvert';

/** Restore shared songs without exporting or losing this device's source bindings. */
export function restorePlaylistFromSync(syncPlaylist: SyncPlaylist, existing: Playlist | undefined,
  favoritesId: string): Playlist {
  // Keep the local id shape: both local_<ts> and imported numeric ids may share a sync id.
  const id = syncPlaylist.id === playlistIdToSync(favoritesId)
    ? favoritesId
    : (existing !== undefined ? existing.id : syncPlaylistIdToLocal(syncPlaylist.id));
  const playlist = new Playlist(id, syncPlaylist.name, MusicPlatform.LOCAL);
  playlist.createdAt = syncPlaylist.createdAt;
  playlist.updatedAt = syncPlaylist.modifiedAt;
  if (existing !== undefined) {
    const local = Playlist.fromJson(existing.toJson());
    playlist.coverUrl = local.coverUrl;
    playlist.description = local.description;
    playlist.source = local.source;
    playlist.syncSources = local.getSyncSources();
    playlist.syncSource = playlist.syncSources.length > 0 ? playlist.syncSources[0] : null;
    playlist.manualSongKeys = local.manualSongKeys.slice();
    playlist.manualOwnershipKnown = local.manualOwnershipKnown;
  }
  for (const syncSong of syncPlaylist.songs) {
    const song = songItemFromSyncSong(syncSong);
    playlist.songs.push(song);
    playlist.songKeys.push(stableKeyOf(song));
  }
  if (existing !== undefined) {
    for (const song of existing.songs) {
      if (isLocalSongItem(song) && playlist.songKeys.indexOf(stableKeyOf(song)) < 0) {
        // Local files do not travel through the shared format; keep their metadata too.
        const localSong = SongItem.fromJson(song.toJson());
        playlist.songs.push(localSong);
        playlist.songKeys.push(stableKeyOf(localSong));
      }
    }
  }
  return playlist;
}
